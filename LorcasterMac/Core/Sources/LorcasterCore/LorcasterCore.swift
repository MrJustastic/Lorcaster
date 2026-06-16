import Foundation
import Observation
import AVFoundation

/// Shared domain models and core services for Lorcaster.
/// CastItem represents a scanned media file (LibraryItem for MVP parity with Audiobookshelf-style items).
/// Enhanced for Phase 1: includes optional author (from AV metadata), relativePath (from library root for
/// future playback resolution without storing per-file bookmarks), and coverRelativePath (detected sibling/peer image).
/// All models are Sendable for safe crossing into actors (scanner) and Swift 6 strict concurrency.
public struct CastItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var author: String?
    public var duration: TimeInterval
    public var source: String          // library root folder name (for grouping + display)
    public var relativePath: String?   // path relative to its bookmarked library root, e.g. "Book/01.mp3" (for single-file) or book dir for multi-file
    public var coverRelativePath: String? // relative path to a cover image if detected, e.g. "Book/cover.jpg"
    public var chapters: [Chapter]     // for multi-file books or embedded chapters; each may have its own relativePath

    // MARK: - Phase 2 rich metadata (parity with Audiobookshelf provider fields)
    // All optional / defaulted so older persisted items and existing call sites keep working.
    public var subtitle: String?
    public var narrator: String?
    public var series: String?
    public var seriesSequence: String?      // string to preserve values like "1.5"
    public var publishedYear: String?
    public var publisher: String?
    public var bookDescription: String?     // long description / summary (named to avoid CustomStringConvertible clash)
    public var genres: [String]
    public var language: String?
    public var isbn: String?
    public var asin: String?
    public var remoteCoverURL: String?      // provider-supplied cover URL (used when no local cover image exists)
    /// True once the user has manually edited this book's chapters. The player then uses the stored
    /// chapter list verbatim instead of re-deriving embedded markers from the audio file on load.
    public var userEditedChapters: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        duration: TimeInterval,
        source: String,
        relativePath: String? = nil,
        coverRelativePath: String? = nil,
        chapters: [Chapter] = [],
        subtitle: String? = nil,
        narrator: String? = nil,
        series: String? = nil,
        seriesSequence: String? = nil,
        publishedYear: String? = nil,
        publisher: String? = nil,
        bookDescription: String? = nil,
        genres: [String] = [],
        language: String? = nil,
        isbn: String? = nil,
        asin: String? = nil,
        remoteCoverURL: String? = nil,
        userEditedChapters: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.duration = duration
        self.source = source
        self.relativePath = relativePath
        self.coverRelativePath = coverRelativePath
        self.chapters = chapters
        self.subtitle = subtitle
        self.narrator = narrator
        self.series = series
        self.seriesSequence = seriesSequence
        self.publishedYear = publishedYear
        self.publisher = publisher
        self.bookDescription = bookDescription
        self.genres = genres
        self.language = language
        self.isbn = isbn
        self.asin = asin
        self.remoteCoverURL = remoteCoverURL
        self.userEditedChapters = userEditedChapters
    }

    /// Convenience: "Series Name #1.5" when both present, else just the series name.
    public var seriesDisplay: String? {
        guard let series, !series.isEmpty else { return nil }
        if let seq = seriesSequence, !seq.isEmpty { return "\(series) #\(seq)" }
        return series
    }

    /// Returns a copy with metadata fields filled from an online provider result.
    /// Non-destructive: a provider value overrides only when present; the local file's
    /// duration and on-disk paths are always preserved (the file is authoritative for playback).
    public func merging(_ r: BookSearchResult) -> CastItem {
        var copy = self
        let newTitle = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty { copy.title = newTitle }
        copy.subtitle = r.subtitle ?? copy.subtitle
        copy.author = r.author ?? copy.author
        copy.narrator = r.narrator ?? copy.narrator
        copy.publisher = r.publisher ?? copy.publisher
        copy.publishedYear = r.publishedYear ?? copy.publishedYear
        copy.bookDescription = r.description ?? copy.bookDescription
        if !r.genres.isEmpty { copy.genres = r.genres }
        copy.series = r.series ?? copy.series
        copy.seriesSequence = r.seriesSequence ?? copy.seriesSequence
        copy.language = r.language ?? copy.language
        copy.isbn = r.isbn ?? copy.isbn
        copy.asin = r.asin ?? copy.asin
        copy.remoteCoverURL = r.coverURL ?? copy.remoteCoverURL
        return copy
    }
}

// MARK: - Robust Codable for model evolution (tolerates v1 items missing new optional fields)
extension CastItem {
    private enum CodingKeys: String, CodingKey {
        case id, title, author, duration, source, relativePath, coverRelativePath, chapters
        case subtitle, narrator, series, seriesSequence, publishedYear, publisher
        case bookDescription, genres, language, isbn, asin, remoteCoverURL
        case userEditedChapters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        source = try container.decode(String.self, forKey: .source)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        coverRelativePath = try container.decodeIfPresent(String.self, forKey: .coverRelativePath)
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        narrator = try container.decodeIfPresent(String.self, forKey: .narrator)
        series = try container.decodeIfPresent(String.self, forKey: .series)
        seriesSequence = try container.decodeIfPresent(String.self, forKey: .seriesSequence)
        publishedYear = try container.decodeIfPresent(String.self, forKey: .publishedYear)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        bookDescription = try container.decodeIfPresent(String.self, forKey: .bookDescription)
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language)
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        asin = try container.decodeIfPresent(String.self, forKey: .asin)
        remoteCoverURL = try container.decodeIfPresent(String.self, forKey: .remoteCoverURL)
        userEditedChapters = try container.decodeIfPresent(Bool.self, forKey: .userEditedChapters) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(duration, forKey: .duration)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(coverRelativePath, forKey: .coverRelativePath)
        try container.encode(chapters, forKey: .chapters)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(narrator, forKey: .narrator)
        try container.encodeIfPresent(series, forKey: .series)
        try container.encodeIfPresent(seriesSequence, forKey: .seriesSequence)
        try container.encodeIfPresent(publishedYear, forKey: .publishedYear)
        try container.encodeIfPresent(publisher, forKey: .publisher)
        try container.encodeIfPresent(bookDescription, forKey: .bookDescription)
        try container.encode(genres, forKey: .genres)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(isbn, forKey: .isbn)
        try container.encodeIfPresent(asin, forKey: .asin)
        try container.encodeIfPresent(remoteCoverURL, forKey: .remoteCoverURL)
        try container.encode(userEditedChapters, forKey: .userEditedChapters)
    }
}

/// Lightweight representation of a bookmarked library folder (the "Library" concept for Phase 1).
/// Stored names + bookmark data live in CoreStore; this is for UI / future expansion.
/// Parity with current folder conventions (lastPathComponent as name, like Audiobookshelf libraries).
public struct Library: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String   // lastPathComponent of the root folder

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// Represents a chapter within an audiobook or podcast episode.
/// For multi-file books (one audio file per chapter), `relativePath` points to the specific audio file.
/// For embedded chapters in a single file, `relativePath` may be nil (use the item's relativePath).
public struct Chapter: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var startTime: TimeInterval
    public var duration: TimeInterval?
    public let relativePath: String?   // audio file for this chapter, relative to library root (immutable: tied to a file)

    public init(id: UUID = UUID(), title: String, startTime: TimeInterval, duration: TimeInterval? = nil, relativePath: String? = nil) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.duration = duration
        self.relativePath = relativePath
    }
}

// MARK: - Background Scanner Actor (Swift 6 / Sendable isolation for strict concurrency)

/// Actor-isolated scanner for recursive discovery + metadata extraction.
/// - Uses FileManager enumeration (off main thread via actor executor).
/// - Uses AVAsset.load for duration + commonMetadata (title/artist) in async context.
/// - Performs cover detection by sibling file name heuristics matching common audiobook folder conventions
///   (cover.jpg, folder.png, artwork.* etc next to audio or in parent dir of track).
/// - Computes relativePath from the library root for each discovered media (enables future real playback
///   by re-resolving only the library bookmark + appending relative components).
/// - Yields items via AsyncStream for live incremental UI updates during long scans (no blocking main).
/// - Pure from side-effects; CoreStore owns persistence, scopes, dedup, and @Observable state.
/// Testability: actor can be unit-tested in isolation by passing temp URLs (with appropriate access).
public actor LibraryScanner {
    public static let shared = LibraryScanner()

    private init() {}

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "alac", "ogg", "opus",
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "m4b"   // m4b common for audiobooks
    ]

    private static let coverBaseNames: Set<String> = [
        "cover", "folder", "artwork", "poster", "front", "thumbnail", "albumart", "image"
    ]
    private static let coverExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"]

    /// Returns an AsyncStream that yields discovered CastItems as soon as their AV metadata is loaded.
    /// Callers on MainActor can iterate: for await item in stream { append... } for live progress.
    public func scanItems(root: URL) -> AsyncStream<CastItem> {
        AsyncStream { continuation in
            Task {
                await self.performScan(root: root, continuation: continuation)
                continuation.finish()
            }
        }
    }

    private func performScan(root: URL, continuation: AsyncStream<CastItem>.Continuation) async {
        let fm = FileManager.default
        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .nameKey, .parentDirectoryURLKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        // Collect audio file URLs first (lightweight FS walk).
        var audioFiles: [URL] = []
        if let enumerator {
            while let obj = enumerator.nextObject() as? URL {
                let ext = obj.pathExtension.lowercased()
                guard Self.supportedExtensions.contains(ext) else { continue }

                if let values = try? obj.resourceValues(forKeys: [.isRegularFileKey]),
                   let isFile = values.isRegularFile, !isFile {
                    continue
                }
                audioFiles.append(obj)
            }
        }

        // Group by immediate parent directory (the "book" folder).
        // This consolidates "books with chapters as separate audio files" into one CastItem
        // with multiple Chapter entries (one per audio file).
        // Single-file items will have a single chapter.
        var groups: [String: [URL]] = [:]  // key = relative dir of the book folder
        for fileURL in audioFiles {
            let parent = fileURL.deletingLastPathComponent()
            let relDir = Self.relativePath(from: root, to: parent)
            groups[relDir, default: []].append(fileURL)
        }

        let folderName = root.lastPathComponent

        // Process each group (book), load metadata for its files, build chapters, yield one CastItem per book.
        // This provides live updates per *book* as its chapter metadata loads.
        for (relDir, filesInGroup) in groups {
            // Sort files naturally (by filename) so chapters are in order.
            let sortedFiles = filesInGroup.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            var chapters: [Chapter] = []
            var bookTitle: String?
            var bookAuthor: String?
            var totalDuration: TimeInterval = 0
            var bookCoverRel: String?
            var cumulative: TimeInterval = 0  // for chapter start times within the book

            for fileURL in sortedFiles {
                let asset = AVURLAsset(url: fileURL)
                do {
                    let durationValue = try await asset.load(.duration)
                    let duration = max(0, durationValue.seconds)
                    totalDuration += duration

                    let (title, author) = await extractTitleAndAuthor(from: asset, fallbackFileURL: fileURL)
                    let chapterTitle = title  // use per-file title as chapter title
                    let relPath = Self.relativePath(from: root, to: fileURL)

                    // Use first file's author as book author if not set; prefer consistent one.
                    if bookAuthor == nil { bookAuthor = author }
                    if bookTitle == nil { bookTitle = (relDir.isEmpty ? nil : URL(fileURLWithPath: relDir).lastPathComponent) ?? title }

                    // Cover is per book dir, find once using first file or dir.
                    if bookCoverRel == nil {
                        bookCoverRel = Self.findCoverRelativePath(for: fileURL, relativeTo: root, fm: fm)
                    }

                    let chapter = Chapter(
                        title: chapterTitle,
                        startTime: cumulative,  // cumulative book time for display / progress
                        duration: duration,
                        relativePath: relPath
                    )
                    chapters.append(chapter)
                    cumulative += duration
                } catch {
                    // Skip unreadable file in group
                    continue
                }
            }

            guard !chapters.isEmpty else { continue }

            let bookRelPath = relDir.isEmpty ? sortedFiles.first.flatMap { Self.relativePath(from: root, to: $0) } : relDir

            let rawTitle = bookTitle ?? (relDir.isEmpty ? "Untitled Book" : URL(fileURLWithPath: relDir).lastPathComponent)

            // Detect an Audible ASIN from the folder/file/title (e.g. "Title [B08G9PRS1K]") so books
            // are exact-matchable without opening Get Info. Strip the token from the displayed title.
            let detectionSource = "\(rawTitle) \(relDir) \(sortedFiles.first?.lastPathComponent ?? "")"
            let detectedASIN = AudibleProvider.detectASIN(in: detectionSource)
            let cleanedTitle = Self.cleanedTitle(rawTitle, removingASIN: detectedASIN)

            let item = CastItem(
                title: cleanedTitle,
                author: bookAuthor,
                duration: totalDuration,
                source: folderName,
                relativePath: bookRelPath,
                coverRelativePath: bookCoverRel,
                chapters: chapters,
                asin: detectedASIN
            )
            continuation.yield(item)
        }
    }

    private func extractTitleAndAuthor(from asset: AVURLAsset, fallbackFileURL: URL) async -> (String, String?) {
        let commonMetadata: [AVMetadataItem] = (try? await asset.load(.commonMetadata)) ?? []
        var title: String?
        var artist: String?

        for item in commonMetadata {
            guard let value = (try? await item.load(.stringValue)), !value.isEmpty else { continue }
            if let key = item.commonKey {
                switch key {
                case .commonKeyTitle:
                    title = value
                case .commonKeyArtist, .commonKeyCreator, .commonKeyAuthor:
                    artist = value
                default:
                    break
                }
            } else if let identifier = item.identifier?.rawValue.lowercased() {
                // Fallback for ID3 / iTunes / QuickTime keys often present in audiobooks
                if title == nil && (identifier.contains("title") || identifier.contains("name")) {
                    title = value
                }
                if artist == nil && (identifier.contains("artist") || identifier.contains("author") || identifier.contains("composer") || identifier.contains("narrator")) {
                    artist = value
                }
            }
        }

        let finalTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackFileURL.deletingPathExtension().lastPathComponent
        let finalAuthor = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (finalTitle, finalAuthor)
    }

    /// Removes a detected ASIN token (bracketed, parenthesized, or a trailing bare token) from a
    /// title for cleaner display. Falls back to the original title if cleaning would empty it.
    private static func cleanedTitle(_ title: String, removingASIN asin: String?) -> String {
        guard let asin, !asin.isEmpty else { return title }
        var t = title
        for token in ["[\(asin)]", "(\(asin))", "{\(asin)}", asin] {
            t = t.replacingOccurrences(of: token, with: " ", options: [.caseInsensitive])
        }
        // Collapse runs of whitespace and trim leftover separators.
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -_.[](){}"))
        return t.isEmpty ? title : t
    }

    private static func relativePath(from root: URL, to file: URL) -> String {
        let rootStd = root.standardizedFileURL
        let fileStd = file.standardizedFileURL
        let rootPath = rootStd.path
        let filePath = fileStd.path
        if filePath.hasPrefix(rootPath + "/") {
            let rel = filePath.dropFirst(rootPath.count + 1)
            return String(rel)
        }
        // Fallback for edge (shouldn't normally happen)
        return file.lastPathComponent
    }

    /// Looks for cover in same directory as the audio file first (most common for per-book folders),
    /// falls back to scanning immediate parent if audio is in subdir like "CD1/01.mp3".
    /// Returns path relative to the library root if found.
    private static func findCoverRelativePath(for mediaFile: URL, relativeTo root: URL, fm: FileManager) -> String? {
        let mediaDir = mediaFile.deletingLastPathComponent()
        let candidatesDirs = [mediaDir, mediaDir.deletingLastPathComponent()] // self + parent

        for dir in candidatesDirs where dir.path.hasPrefix(root.path) || dir == mediaDir {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }

            for file in contents {
                let ext = file.pathExtension.lowercased()
                guard Self.coverExtensions.contains(ext) else { continue }
                let base = file.deletingPathExtension().lastPathComponent.lowercased()
                if Self.coverBaseNames.contains(base) || Self.coverBaseNames.contains(where: { base.hasPrefix($0) }) {
                    // Compute relative to root
                    let rel = Self.relativePath(from: root, to: file)
                    if !rel.isEmpty { return rel }
                }
            }
        }
        return nil
    }

    /// Loads embedded chapter markers (e.g. from an .m4b/mp4/m4a) at a file URL using AVFoundation.
    /// Chapters have file-absolute startTimes and nil relativePath (they live inside a single file).
    /// Returns an empty array if the file has no chapter metadata. Used by the chapter editor to
    /// populate the real chapter list for single-file books.
    public static func loadEmbeddedChapters(at url: URL) async -> [Chapter] {
        let asset = AVURLAsset(url: url)
        guard let locales = try? await asset.load(.availableChapterLocales),
              let locale = locales.first else {
            return []
        }
        do {
            let groups = try await asset.loadChapterMetadataGroups(
                withTitleLocale: locale,
                containingItemsWithCommonKeys: [.commonKeyTitle]
            )
            var result: [Chapter] = []
            for group in groups {
                let titleItem = group.items.first(where: { $0.commonKey == .commonKeyTitle })
                let titleStr: String = if let titleItem {
                    (try? await titleItem.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter"
                } else {
                    "Chapter"
                }
                let start = group.timeRange.start.seconds
                let dur = group.timeRange.duration.seconds
                result.append(Chapter(title: titleStr, startTime: max(0, start), duration: dur > 0 ? dur : nil))
            }
            return result.sorted { $0.startTime < $1.startTime }
        } catch {
            return []
        }
    }
}

@MainActor
@Observable
public final class CoreStore {
    public var items: [CastItem] = [
        CastItem(title: "Sample Episode 1", author: "Demo Narrator", duration: 1234, source: "local"),
        CastItem(title: "Sample Cast 2", duration: 567, source: "remote")
    ]
    public var lastError: String?

    /// When true (default), a detected local cover image is preferred for display; when false,
    /// artwork fetched from an online metadata provider is preferred. Persisted across launches.
    public var preferLocalArtwork: Bool = true {
        didSet { UserDefaults.standard.set(preferLocalArtwork, forKey: Self.preferLocalArtworkKey) }
    }
    private static let preferLocalArtworkKey = "LorcasterPreferLocalArtwork"

    /// Display names of currently bookmarked library roots (last path component).
    public private(set) var libraryRootNames: [String] = []

    /// Convenience for UI / future expansion (Library model mirroring ABS "libraries").
    public var libraries: [Library] {
        libraryRootNames.map { Library(name: $0) }
    }

    /// Number of active bookmarked folders (for UI display / parity).
    public var libraryCount: Int { libraryRootNames.count }

    /// True while a recursive folder scan is in progress.
    public private(set) var isScanning: Bool = false

    // MARK: - Playback and asset URL resolution (Phase 1+)
    /// Shared helper: finds and activates the security-scoped root for a given library source name.
    /// Returns the root URL (with access started) or nil if no matching bookmark.
    private func resolvedRoot(forSource sourceName: String) -> URL? {
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        for data in bookmarkDatas {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else { continue }

            if resolved.lastPathComponent != name { continue }

            // Ensure active scope (idempotent)
            if !scopedResources.contains(where: { $0.standardizedFileURL.path == resolved.standardizedFileURL.path }) {
                if resolved.startAccessingSecurityScopedResource() {
                    scopedResources.append(resolved)
                }
            }
            return resolved
        }
        return nil
    }

    /// Returns a file URL that can be passed to AVPlayer for a CastItem discovered by the scanner.
    /// Re-resolves the matching library root bookmark (by source folder name), starts security-scoped
    /// access if needed, and appends the item's relativePath (handling subfolders like "Book/CD1/01.mp3").
    /// Returns nil if no matching bookmark for the item's source or if the bookmark is stale/unresolvable.
    /// This is the key bridge from scanned metadata (which stores only relativePath + source name) back
    /// to a real on-disk URL without per-file persistence.
    public func playableURL(for item: CastItem) -> URL? {
        let sourceName = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = resolvedRoot(forSource: sourceName) else { return nil }

        guard let rel = item.relativePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !rel.isEmpty else {
            return root
        }

        // Safely append a relative path that may contain subdirectories
        var full = root
        for component in rel.split(separator: "/") {
            full = full.appendingPathComponent(String(component))
        }
        return full
    }

    /// Returns a URL to the cover image (if any) for a CastItem, using the same bookmark + scope
    /// resolution as playableURL. UI code (e.g. AsyncImage or NSImage) can use this directly while
    /// the library root scope is active.
    public func coverURL(for item: CastItem) -> URL? {
        let sourceName = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root = resolvedRoot(forSource: sourceName) else { return nil }

        guard let rel = item.coverRelativePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !rel.isEmpty else {
            return nil
        }

        var full = root
        for component in rel.split(separator: "/") {
            full = full.appendingPathComponent(String(component))
        }
        return full
    }

    /// Best available cover URL for display. The order honors the `preferLocalArtwork` setting:
    /// when true (default) a detected local cover image wins, falling back to provider artwork;
    /// when false the provider's remote artwork wins, falling back to the local cover.
    /// Returns a file URL (security scope started) or an https URL, or nil. Both are usable directly
    /// by AsyncImage; callers loading via NSImage should branch on `isFileURL` so remote URLs are
    /// fetched asynchronously rather than blocking.
    public func bestCoverURL(for item: CastItem) -> URL? {
        let local = coverURL(for: item)
        let remote: URL? = {
            guard let r = item.remoteCoverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !r.isEmpty else { return nil }
            return URL(string: r)
        }()
        return preferLocalArtwork ? (local ?? remote) : (remote ?? local)
    }

    /// Resolves an on-disk file URL for a given library source + relative path (starting security
    /// scope as needed). Used by the embedded server to stream arbitrary chapter files.
    public func fileURL(source: String, relativePath: String) -> URL? {
        guard let root = resolvedRoot(forSource: source.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let rel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !rel.isEmpty else { return root }
        var full = root
        for component in rel.split(separator: "/") {
            full = full.appendingPathComponent(String(component))
        }
        return full
    }

    public static let shared = CoreStore()

    // Persistence keys (v2 for enhanced CastItem with author/relative/cover fields + Library model prep)
    private let bookmarksKey = "LorcasterLibraryBookmarks.v1"
    private let itemsKey = "LorcasterLibraryItems.v2"

    private var bookmarkDatas: [Data] = []
    private var scopedResources: [URL] = []
    private var knownKeys: Set<String> = []

    // Per-book resume positions (book-absolute seconds), keyed by item id. Not observed (saved
    // frequently by the player; no UI binds to it directly).
    @ObservationIgnored private var playbackPositions: [String: TimeInterval] = [:]
    private let positionsKey = "LorcasterPlaybackPositions.v1"

    private init() {
        if UserDefaults.standard.object(forKey: Self.preferLocalArtworkKey) != nil {
            preferLocalArtwork = UserDefaults.standard.bool(forKey: Self.preferLocalArtworkKey)
        }
        loadBookmarksAndItems()
    }

    // MARK: - Public API for Library management (MVP Phase 1)

    /// Adds a user-chosen folder using NSOpenPanel (caller) + security-scoped bookmark.
    /// Persists bookmark (app-scope), starts access, updates root names, then uses LibraryScanner actor
    /// + AsyncStream for background recursive scan with *live* item-by-item progress in the @Observable UI.
    /// Clears demo samples on first real add. Dedups by bookmark data and by item key.
    public func addLibraryFolder(_ selectedURL: URL) async {
        guard selectedURL.hasDirectoryPath || (try? selectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            lastError = "Please choose a folder, not a file."
            return
        }

        // Create bookmark for persistent, secure access across launches (matches entitlement).
        let bookmark: Data
        do {
            bookmark = try selectedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            lastError = "Failed to bookmark folder: \(error.localizedDescription)"
            return
        }

        // Dedup identical bookmarks (data equality works for this purpose)
        if !bookmarkDatas.contains(bookmark) {
            bookmarkDatas.append(bookmark)
            persistBookmarks()
        }

        // On first real library addition, drop the placeholder samples for clean MVP data.
        if items.count <= 2 && items.contains(where: { $0.title.hasPrefix("Sample") }) {
            items.removeAll()
            knownKeys.removeAll()
        }

        // Resolve + start security-scoped access for this run.
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            lastError = "Could not resolve the selected folder (may have moved or permissions changed)."
            return
        }

        if !scopedResources.contains(where: { $0.standardizedFileURL.path == resolved.standardizedFileURL.path }) {
            if resolved.startAccessingSecurityScopedResource() {
                scopedResources.append(resolved)
            }
        }

        let folderName = resolved.lastPathComponent
        if !libraryRootNames.contains(folderName) {
            libraryRootNames.append(folderName)
        }

        isScanning = true
        lastError = nil
        defer {
            isScanning = false
            persistItems()
        }

        // Use actor + streaming for live progress (count and list update as each file's AV metadata loads).
        let scanner = LibraryScanner.shared
        let stream = await scanner.scanItems(root: resolved)
        for await discovered in stream {
            appendDiscovered([discovered])
        }
    }

    /// Removes a single bookmarked library folder (and all its discovered items) without clearing everything else.
    /// Stops its scoped resource if active, filters bookmarks, updates names + items + keys, persists.
    public func removeLibraryFolder(named name: String) {
        // Find and stop scope for matching root(s)
        var toStop: [URL] = []
        for url in scopedResources {
            if url.lastPathComponent == name {
                toStop.append(url)
            }
        }
        for url in toStop {
            url.stopAccessingSecurityScopedResource()
            scopedResources.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        }

        // Filter bookmarks by re-resolving and skipping the named one (best effort; names are last components)
        var keptBookmarks: [Data] = []
        for data in bookmarkDatas {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
               !isStale,
               resolved.lastPathComponent == name {
                // drop this one
                continue
            }
            keptBookmarks.append(data)
        }
        bookmarkDatas = keptBookmarks

        // Remove items belonging to this source + rebuild knownKeys for remaining
        let removedIDs = items.filter { $0.source == name }.map { $0.id.uuidString }
        items.removeAll { $0.source == name }
        knownKeys = Set(items.map { keyFor($0) })
        for id in removedIDs { playbackPositions.removeValue(forKey: id) }
        if !removedIDs.isEmpty { persistPositions() }

        // Rebuild displayed root names
        libraryRootNames.removeAll { $0 == name }
        // Note: if another root had identical lastPathComponent, the name may have been removed incorrectly.
        // For robust MVP+ we could key roots by bookmark or persistent UUID, but folder name is current convention.

        persistBookmarks()
        persistItems()
        lastError = nil
    }

    /// Clears all library items, bookmarks, and stops any active scoped access.
    public func clearLibrary() {
        items.removeAll()
        knownKeys.removeAll()
        libraryRootNames.removeAll()
        playbackPositions.removeAll()
        persistPositions()

        for url in scopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        scopedResources.removeAll()

        bookmarkDatas.removeAll()
        persistBookmarks()
        persistItems()
        lastError = nil
    }

    /// Re-scans all currently bookmarked folders and replaces current items with fresh results.
    /// Uses the actor scanner + live streaming appends.
    public func rescanAll() async {
        isScanning = true
        lastError = nil

        // Drop current items for a clean rescan result set.
        items.removeAll()
        knownKeys.removeAll()

        var refreshedNames: [String] = []
        var stillValidBookmarks: [Data] = []

        let scanner = LibraryScanner.shared

        for data in bookmarkDatas {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else {
                continue
            }

            stillValidBookmarks.append(data)

            if !scopedResources.contains(where: { $0.standardizedFileURL.path == resolved.standardizedFileURL.path }) {
                if resolved.startAccessingSecurityScopedResource() {
                    scopedResources.append(resolved)
                }
            }

            let name = resolved.lastPathComponent
            if !refreshedNames.contains(name) {
                refreshedNames.append(name)
            }

            // Live streaming append during rescan
            let stream = await scanner.scanItems(root: resolved)
            for await discovered in stream {
                appendDiscovered([discovered])
            }
        }

        bookmarkDatas = stillValidBookmarks
        libraryRootNames = refreshedNames
        persistBookmarks()
        persistItems()
        isScanning = false
    }

    // MARK: - Metadata editing (Phase 2)

    /// Replaces the stored item that shares `updated.id` and persists. Used by the Get Info / Match
    /// editor for both manual edits and applied online-provider results. Rebuilds the dedup key set
    /// since edited fields (author/title/relativePath) feed into the key.
    public func updateItem(_ updated: CastItem) {
        guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
        items[index] = updated
        knownKeys = Set(items.map { keyFor($0) })
        persistItems()
        lastError = nil
    }

    // MARK: - Resume positions (Phase 3)

    /// Saved book-absolute position (seconds) for a book, or nil if none / finished.
    public func playbackPosition(for id: UUID) -> TimeInterval? {
        playbackPositions[id.uuidString]
    }

    /// Stores the current book-absolute position for a book (called frequently by the player).
    public func savePlaybackPosition(_ seconds: TimeInterval, for id: UUID) {
        guard seconds.isFinite, seconds > 0 else {
            clearPlaybackPosition(for: id)
            return
        }
        playbackPositions[id.uuidString] = seconds
        persistPositions()
    }

    /// Clears a saved position (e.g. when a book is finished or removed).
    public func clearPlaybackPosition(for id: UUID) {
        if playbackPositions.removeValue(forKey: id.uuidString) != nil {
            persistPositions()
        }
    }

    private func persistPositions() {
        if let data = try? JSONEncoder().encode(playbackPositions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
    }

    // MARK: - Batch auto-match by ASIN (Phase 2)

    /// True while a batch auto-match run is in progress.
    public private(set) var isAutoMatching = false
    /// Number of books processed so far in the current/last run.
    public private(set) var autoMatchDone = 0
    /// Total books targeted by the current/last run.
    public private(set) var autoMatchTotal = 0
    /// Human-readable result of the last completed run (nil until one finishes).
    public private(set) var autoMatchSummary: String?

    /// Count of books that carry an ASIN and can therefore be auto-matched.
    public var asinMatchableCount: Int {
        items.reduce(0) { $0 + ((($1.asin?.isEmpty) == false) ? 1 : 0) }
    }

    /// Enriches every book that has an ASIN by looking it up via Audnexus and merging the result
    /// (non-destructive: local duration/paths are preserved). Runs sequentially to stay polite to
    /// the API; publishes live progress via the observable counters. Safe to call once at a time.
    public func autoMatchAllByASIN() async {
        guard !isAutoMatching else { return }

        let targets = items.filter { ($0.asin?.isEmpty) == false }
        autoMatchTotal = targets.count
        autoMatchDone = 0
        autoMatchSummary = nil

        guard !targets.isEmpty else {
            autoMatchSummary = "No books with an ASIN to match. Try Rescan, or set an ASIN in Get Info."
            return
        }

        isAutoMatching = true
        lastError = nil
        let provider = AudibleProvider()
        var matched = 0

        for target in targets {
            if let asin = target.asin, !asin.isEmpty {
                do {
                    let results = try await provider.searchByIdentifier(asin)
                    if let result = results.first,
                       let index = items.firstIndex(where: { $0.id == target.id }) {
                        items[index] = items[index].merging(result)
                        matched += 1
                    }
                } catch {
                    // Skip individual failures (network/not-found) and continue the batch.
                }
            }
            autoMatchDone += 1
        }

        knownKeys = Set(items.map { keyFor($0) })
        persistItems()
        isAutoMatching = false
        autoMatchSummary = "Matched \(matched) of \(targets.count) book\(targets.count == 1 ? "" : "s") by ASIN."
    }

    // MARK: - Private implementation

    private func keyFor(_ item: CastItem) -> String {
        // Include author + rel path for better dedup across similar titles in different books/folders
        "\(item.source)|\(item.author ?? "")|\(item.title)|\(item.relativePath ?? "")|\(Int(item.duration))"
    }

    private func appendDiscovered(_ discovered: [CastItem]) {
        for item in discovered {
            let k = keyFor(item)
            if !knownKeys.contains(k) {
                knownKeys.insert(k)
                items.append(item)
            }
        }
    }

    private func loadBookmarksAndItems() {
        // Load persisted bookmarks
        if let storedBookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] {
            bookmarkDatas = storedBookmarks
        }

        // Load persisted resume positions
        if let posData = UserDefaults.standard.data(forKey: positionsKey),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: posData) {
            playbackPositions = decoded
        }

        // Load persisted items or keep demo samples
        if let itemsData = UserDefaults.standard.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([CastItem].self, from: itemsData) {
            items = decoded
            knownKeys = Set(items.map { keyFor($0) })
        } else {
            // Seed demo samples; they will be cleared on first real folder add.
            knownKeys = Set(items.map { keyFor($0) })
        }

        // Asynchronously restore security-scoped access for any persisted bookmarks.
        // We do NOT auto-rescan here (expensive on large libraries at launch); user triggers via UI.
        Task { [weak self] in
            await self?.restoreScopes(performScan: false)
        }
    }

    private func restoreScopes(performScan: Bool) async {
        var validBookmarks: [Data] = []
        var names: [String] = []

        for data in bookmarkDatas {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else {
                continue
            }

            validBookmarks.append(data)

            if resolved.startAccessingSecurityScopedResource() {
                if !scopedResources.contains(where: { $0.standardizedFileURL.path == resolved.standardizedFileURL.path }) {
                    scopedResources.append(resolved)
                }
            }

            let name = resolved.lastPathComponent
            if !names.contains(name) {
                names.append(name)
            }

            if performScan {
                // Use actor for any future auto-scan on launch (currently disabled to keep launch fast)
                let scanner = LibraryScanner.shared
                let stream = await scanner.scanItems(root: resolved)
                for await discovered in stream {
                    appendDiscovered([discovered])
                }
                persistItems()
            }
        }

        bookmarkDatas = validBookmarks
        libraryRootNames = names
        if !validBookmarks.isEmpty {
            persistBookmarks()
        }
    }

    private func persistBookmarks() {
        UserDefaults.standard.set(bookmarkDatas, forKey: bookmarksKey)
    }

    private func persistItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }
}

public enum LorcasterCoreError: Error, LocalizedError {
    case notImplemented
    public var errorDescription: String? { "Core feature not implemented yet" }
}
