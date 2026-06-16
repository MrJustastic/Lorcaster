import Foundation
import Hummingbird
import HTTPTypes
import LorcasterCore
import NIOCore
import UniformTypeIdentifiers

/// The embedded HTTP server (Hummingbird 2). Phase 4 first slice: a read-only LAN server with a
/// small custom JSON API (designed so an Audiobookshelf-compatibility layer can be added later).
/// Stateless + Sendable so it can run on a detached task supervised by `ServerController`.
struct LorcasterHTTPServer: Sendable {
    /// Builds the router and runs the server until the surrounding task is cancelled.
    func run(port: Int) async throws {
        let router = buildRouter()
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("0.0.0.0", port: port),
                serverName: "Lorcaster"
            )
        )
        // runService() runs until the task is cancelled (graceful shutdown on cancel).
        try await app.runService()
    }

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()

        // Health check + identity.
        router.get("ping") { _, _ -> String in
            "Lorcaster OK"
        }

        // Libraries (one per scanned source folder), with item counts.
        router.get("api/libraries") { _, _ -> Response in
            let items = await MainActor.run { CoreStore.shared.items }
            let dtos = Dictionary(grouping: items, by: { $0.source })
                .map { LibraryDTO(name: $0.key, itemCount: $0.value.count) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return Self.json(dtos)
        }

        // All books (summary). Optional ?source= filter by library folder name.
        router.get("api/items") { request, _ -> Response in
            let source = request.uri.queryParameters["source"].map(String.init)
            let items = await MainActor.run { CoreStore.shared.items }
            let filtered = source.map { src in items.filter { $0.source == src } } ?? items
            let dtos = filtered
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map(BookDTO.init)
            return Self.json(dtos)
        }

        // Single book detail (includes chapters + full metadata).
        router.get("api/items/:id") { _, context -> Response in
            guard let idStr = context.parameters.get("id"), let id = UUID(uuidString: idStr) else {
                return Response(status: .badRequest)
            }
            let item = await MainActor.run { CoreStore.shared.items.first { $0.id == id } }
            guard let item else { return Response(status: .notFound) }
            return Self.json(BookDetailDTO(item))
        }

        // Stream the book's primary audio file — the first chapter's file (its actual audio), which
        // works whether the book is a single file, a single file inside a per-book folder, or
        // multi-file (where this is chapter 1; use the chapter endpoint for others).
        router.get("api/items/:id/file") { request, context -> Response in
            guard let id = Self.uuid(context, "id") else { return Response(status: .badRequest) }
            let url = await MainActor.run { () -> URL? in
                guard let item = CoreStore.shared.items.first(where: { $0.id == id }) else { return nil }
                if let firstRel = item.chapters.first?.relativePath {
                    return CoreStore.shared.fileURL(source: item.source, relativePath: firstRel)
                }
                return CoreStore.shared.playableURL(for: item)
            }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                return Response(status: .notFound)
            }
            return Self.fileStreamResponse(url: url, rangeHeader: request.headers[.range])
        }

        // Stream a specific chapter's audio file (multi-file books) or the whole file (embedded chapters).
        router.get("api/items/:id/chapters/:index/file") { request, context -> Response in
            guard let id = Self.uuid(context, "id"),
                  let idxStr = context.parameters.get("index"), let index = Int(idxStr) else {
                return Response(status: .badRequest)
            }
            let url = await MainActor.run { () -> URL? in
                guard let item = CoreStore.shared.items.first(where: { $0.id == id }),
                      index >= 0, index < item.chapters.count else { return nil }
                let chapter = item.chapters[index]
                if let rel = chapter.relativePath {
                    return CoreStore.shared.fileURL(source: item.source, relativePath: rel)
                }
                return CoreStore.shared.playableURL(for: item)   // embedded chapter: same file
            }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                return Response(status: .notFound)
            }
            return Self.fileStreamResponse(url: url, rangeHeader: request.headers[.range])
        }

        // Local cover image (if any). Remote provider covers are just URLs the client can fetch itself.
        router.get("api/items/:id/cover") { _, context -> Response in
            guard let id = Self.uuid(context, "id") else { return Response(status: .badRequest) }
            let url = await MainActor.run { () -> URL? in
                guard let item = CoreStore.shared.items.first(where: { $0.id == id }) else { return nil }
                return CoreStore.shared.coverURL(for: item)
            }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                return Response(status: .notFound)
            }
            return Self.fileStreamResponse(url: url, rangeHeader: nil)
        }

        return router
    }

    private static func uuid(_ context: BasicRequestContext, _ name: String) -> UUID? {
        context.parameters.get(name).flatMap { UUID(uuidString: $0) }
    }

    /// Encodes a value as a JSON response.
    static func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) -> Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        var headers = HTTPFields()
        headers[.contentType] = "application/json; charset=utf-8"
        return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
    }

    // MARK: - File streaming (HTTP range)

    /// Streams a file with HTTP range support (206 Partial Content), chunked off-main so large
    /// audiobook files are never loaded entirely into memory.
    static func fileStreamResponse(url: URL, rangeHeader: String?) -> Response {
        guard let size = fileSize(url), size > 0 else { return Response(status: .notFound) }

        let parsed = parseRange(rangeHeader, size: size)
        guard let (start, end) = parsed.range else {
            // Unsatisfiable range.
            var headers = HTTPFields()
            headers[.contentRange] = "bytes */\(size)"
            return Response(status: .rangeNotSatisfiable, headers: headers)
        }
        let length = end - start + 1

        var headers = HTTPFields()
        headers[.contentType] = mimeType(for: url)
        headers[.acceptRanges] = "bytes"
        headers[.contentLength] = String(length)
        if parsed.isPartial {
            headers[.contentRange] = "bytes \(start)-\(end)/\(size)"
        }

        let body = ResponseBody(asyncSequence: fileChunks(url: url, start: start, length: length))
        return Response(status: parsed.isPartial ? .partialContent : .ok, headers: headers, body: body)
    }

    /// An async sequence of 64KB chunks read from `url` starting at `start` for `length` bytes.
    private static func fileChunks(url: URL, start: Int, length: Int) -> AsyncStream<ByteBuffer> {
        AsyncStream<ByteBuffer> { continuation in
            let task = Task.detached {
                guard let handle = try? FileHandle(forReadingFrom: url) else {
                    continuation.finish(); return
                }
                defer { try? handle.close() }
                try? handle.seek(toOffset: UInt64(start))
                var remaining = length
                let chunkSize = 64 * 1024
                while remaining > 0, !Task.isCancelled {
                    let toRead = min(chunkSize, remaining)
                    guard let data = try? handle.read(upToCount: toRead), !data.isEmpty else { break }
                    var buffer = ByteBuffer()
                    buffer.writeBytes(data)
                    continuation.yield(buffer)
                    remaining -= data.count
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    /// Parses a `Range: bytes=...` header. Returns the resolved byte range (inclusive) and whether
    /// it's a partial request. `range == nil` means the request was unsatisfiable.
    private static func parseRange(_ header: String?, size: Int) -> (range: (Int, Int)?, isPartial: Bool) {
        guard let header, header.hasPrefix("bytes=") else { return ((0, size - 1), false) }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return ((0, size - 1), false) }

        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].trimmingCharacters(in: .whitespaces)

        if startStr.isEmpty {
            // Suffix range: last N bytes.
            guard let suffix = Int(endStr), suffix > 0 else { return (nil, true) }
            let s = max(0, size - suffix)
            return ((s, size - 1), true)
        }

        guard let start = Int(startStr), start < size else { return (nil, true) }
        let end = endStr.isEmpty ? size - 1 : min(Int(endStr) ?? (size - 1), size - 1)
        guard start <= end else { return (nil, true) }
        return ((start, end), true)
    }

    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           let mime = type.preferredMIMEType {
            return mime
        }
        // Common audiobook fallbacks UTType may miss.
        switch url.pathExtension.lowercased() {
        case "m4b", "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - DTOs (custom minimal API)

struct LibraryDTO: Codable, Sendable {
    let name: String
    let itemCount: Int
}

struct BookDTO: Codable, Sendable {
    let id: String
    let title: String
    let author: String?
    let narrator: String?
    let series: String?
    let seriesSequence: String?
    let publishedYear: String?
    let duration: Double
    let source: String
    let chapterCount: Int
    let hasCover: Bool

    init(_ item: CastItem) {
        id = item.id.uuidString
        title = item.title
        author = item.author
        narrator = item.narrator
        series = item.series
        seriesSequence = item.seriesSequence
        publishedYear = item.publishedYear
        duration = item.duration
        source = item.source
        chapterCount = item.chapters.count
        hasCover = item.coverRelativePath != nil || item.remoteCoverURL != nil
    }
}

struct ChapterDTO: Codable, Sendable {
    let title: String
    let start: Double
    let duration: Double?
}

struct BookDetailDTO: Codable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let author: String?
    let narrator: String?
    let series: String?
    let seriesSequence: String?
    let publishedYear: String?
    let publisher: String?
    let description: String?
    let genres: [String]
    let language: String?
    let isbn: String?
    let asin: String?
    let duration: Double
    let source: String
    let hasCover: Bool
    let chapters: [ChapterDTO]

    init(_ item: CastItem) {
        id = item.id.uuidString
        title = item.title
        subtitle = item.subtitle
        author = item.author
        narrator = item.narrator
        series = item.series
        seriesSequence = item.seriesSequence
        publishedYear = item.publishedYear
        publisher = item.publisher
        description = item.bookDescription
        genres = item.genres
        language = item.language
        isbn = item.isbn
        asin = item.asin
        duration = item.duration
        source = item.source
        hasCover = item.coverRelativePath != nil || item.remoteCoverURL != nil
        chapters = item.chapters.map { ChapterDTO(title: $0.title, start: $0.startTime, duration: $0.duration) }
    }
}
