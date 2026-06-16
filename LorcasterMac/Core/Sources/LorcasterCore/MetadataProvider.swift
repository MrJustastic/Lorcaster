import Foundation

// MARK: - Phase 2: Online metadata providers
//
// Mirrors the normalized book-metadata shape used by the Audiobookshelf/Lorcaster Node backend
// (server/providers/*). The first implemented provider is Audible (via the public Audnexus API),
// which is the richest source for audiobooks (narrator, series + sequence, ASIN, publisher, genres).
//
// The `MetadataProvider` protocol keeps this extensible — additional providers (iTunes, Google Books,
// Open Library, MusicBrainz, etc.) can be added later without changing call sites. All types are
// Sendable for safe use from Swift Concurrency.

/// A normalized book metadata search result, independent of any specific provider.
/// Field names follow the Node backend's canonical shape for parity.
public struct BookSearchResult: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let providerName: String     // which provider produced this result (for display)
    public var title: String
    public var subtitle: String?
    public var author: String?
    public var narrator: String?
    public var publisher: String?
    public var publishedYear: String?
    public var description: String?
    public var coverURL: String?
    public var asin: String?
    public var isbn: String?
    public var genres: [String]
    public var series: String?
    public var seriesSequence: String?
    public var language: String?
    public var duration: TimeInterval?  // seconds, if the provider reports a runtime

    public init(
        id: UUID = UUID(),
        providerName: String,
        title: String,
        subtitle: String? = nil,
        author: String? = nil,
        narrator: String? = nil,
        publisher: String? = nil,
        publishedYear: String? = nil,
        description: String? = nil,
        coverURL: String? = nil,
        asin: String? = nil,
        isbn: String? = nil,
        genres: [String] = [],
        series: String? = nil,
        seriesSequence: String? = nil,
        language: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.providerName = providerName
        self.title = title
        self.subtitle = subtitle
        self.author = author
        self.narrator = narrator
        self.publisher = publisher
        self.publishedYear = publishedYear
        self.description = description
        self.coverURL = coverURL
        self.asin = asin
        self.isbn = isbn
        self.genres = genres
        self.series = series
        self.seriesSequence = seriesSequence
        self.language = language
        self.duration = duration
    }
}

/// A source of online book metadata. Implementations perform their own network I/O.
public protocol MetadataProvider: Sendable {
    /// Stable identifier (lowercase, e.g. "audible").
    var id: String { get }
    /// Human-readable name for the UI (e.g. "Audible").
    var displayName: String { get }
    /// Label for the provider's precise identifier field (e.g. "ASIN"), or nil if unsupported.
    var identifierLabel: String? { get }
    /// Search for books matching a title (and optional author). Returns normalized results.
    func searchBooks(title: String, author: String?) async throws -> [BookSearchResult]
    /// Look up a single book by a precise identifier (e.g. ASIN/ISBN). Accepts a raw identifier
    /// or one embedded in a longer string.
    func searchByIdentifier(_ identifier: String) async throws -> [BookSearchResult]
}

public extension MetadataProvider {
    var identifierLabel: String? { nil }
    /// Default: providers without a precise identifier treat it as a title query.
    func searchByIdentifier(_ identifier: String) async throws -> [BookSearchResult] {
        try await searchBooks(title: identifier, author: nil)
    }
}

public enum MetadataProviderError: Error, LocalizedError {
    case emptyQuery
    case badResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .emptyQuery: return "Enter a title to search."
        case .badResponse: return "The metadata provider returned an unexpected response."
        case .network(let msg): return msg
        }
    }
}

// MARK: - Audible provider (via Audible catalog + Audnexus enrichment)

/// Two-step lookup matching the Node `Audible.js` provider:
/// 1. Query the Audible catalog for matching products (to obtain ASINs).
/// 2. Enrich each ASIN via the Audnexus API (`https://api.audnex.us/books/{asin}`) for full metadata.
public struct AudibleProvider: MetadataProvider {
    public let id = "audible"
    public let displayName = "Audible"
    public var identifierLabel: String? { "ASIN" }

    private let region: String
    private let maxResults: Int
    private let session: URLSession

    /// Maps a region code to the Audible TLD (matches the Node provider's regionMap).
    private static let regionMap: [String: String] = [
        "us": ".com", "ca": ".ca", "uk": ".co.uk", "au": ".com.au",
        "fr": ".fr", "de": ".de", "jp": ".co.jp", "it": ".it", "in": ".in", "es": ".es"
    ]

    public init(region: String = "us", maxResults: Int = 10, session: URLSession = .shared) {
        self.region = AudibleProvider.regionMap[region] != nil ? region : "us"
        self.maxResults = maxResults
        self.session = session
    }

    public func searchBooks(title: String, author: String?) async throws -> [BookSearchResult] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw MetadataProviderError.emptyQuery }

        // If the user typed an ASIN directly, enrich it straight away.
        if Self.isValidASIN(trimmedTitle) {
            if let result = try? await enrich(asin: trimmedTitle) {
                return [result]
            }
        }

        let asins = try await catalogASINs(title: trimmedTitle, author: author)
        guard !asins.isEmpty else { return [] }

        // Enrich ASINs concurrently, preserving catalog order.
        var enriched = [BookSearchResult?](repeating: nil, count: asins.count)
        try await withThrowingTaskGroup(of: (Int, BookSearchResult?).self) { group in
            for (index, asin) in asins.enumerated() {
                group.addTask {
                    let result = try? await enrich(asin: asin)
                    return (index, result)
                }
            }
            for try await (index, result) in group {
                enriched[index] = result
            }
        }
        return enriched.compactMap { $0 }
    }

    /// Precise lookup by ASIN. Accepts a raw ASIN or one embedded in a longer string
    /// (e.g. a folder name like "Project Hail Mary [B08G9PRS1K]").
    public func searchByIdentifier(_ identifier: String) async throws -> [BookSearchResult] {
        let raw = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw MetadataProviderError.emptyQuery }
        let asin = Self.isValidASIN(raw) ? raw.uppercased() : (Self.detectASIN(in: raw) ?? raw.uppercased())
        if let result = try await enrich(asin: asin) { return [result] }
        return []
    }

    // MARK: Step 1 — Audible catalog search for ASINs

    private func catalogASINs(title: String, author: String?) async throws -> [String] {
        let tld = Self.regionMap[region] ?? ".com"
        var components = URLComponents(string: "https://api.audible\(tld)/1.0/catalog/products")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "num_results", value: String(maxResults)),
            URLQueryItem(name: "products_sort_by", value: "Relevance"),
            URLQueryItem(name: "title", value: title)
        ]
        if let author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query.append(URLQueryItem(name: "author", value: author))
        }
        components.queryItems = query
        guard let url = components.url else { throw MetadataProviderError.badResponse }

        let data = try await fetch(url)
        let decoded = try JSONDecoder().decode(CatalogResponse.self, from: data)
        return decoded.products?.compactMap { $0.asin } ?? []
    }

    // MARK: Step 2 — Audnexus enrichment for a single ASIN

    private func enrich(asin: String) async throws -> BookSearchResult? {
        let upper = asin.uppercased()
        var components = URLComponents(string: "https://api.audnex.us/books/\(upper)")!
        components.queryItems = [URLQueryItem(name: "region", value: region)]
        guard let url = components.url else { return nil }

        let data = try await fetch(url)
        let book = try JSONDecoder().decode(AudnexusBook.self, from: data)
        guard let bookAsin = book.asin, !bookAsin.isEmpty else { return nil }
        return book.normalized(providerName: displayName)
    }

    // MARK: Networking

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw MetadataProviderError.badResponse
            }
            return data
        } catch let error as MetadataProviderError {
            throw error
        } catch {
            throw MetadataProviderError.network(error.localizedDescription)
        }
    }

    /// Audible ASINs are 10-character alphanumeric identifiers (matches the Node `isValidASIN`).
    static func isValidASIN(_ value: String) -> Bool {
        let v = value.uppercased()
        guard v.count == 10 else { return false }
        return v.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Finds an ASIN embedded in a string. Prefers a bracketed/parenthesized token (the common
    /// Audible folder convention, e.g. "Title [B08G9PRS1K]"), then a bare "B0…" token.
    /// Returns the uppercased ASIN, or nil if none is found.
    public static func detectASIN(in text: String) -> String? {
        let patterns = [
            "[\\[(]\\s*([A-Za-z0-9]{10})\\s*[\\])]",   // [B08G9PRS1K] or (B08G9PRS1K)
            "\\b(B0[A-Za-z0-9]{8})\\b"                 // bare B0XXXXXXXX
        ]
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges >= 2,
               let r = Range(match.range(at: 1), in: text) {
                let candidate = String(text[r]).uppercased()
                if isValidASIN(candidate) { return candidate }
            }
        }
        return nil
    }
}

// MARK: - Audible / Audnexus response models

private struct CatalogResponse: Decodable {
    let products: [Product]?
    struct Product: Decodable { let asin: String? }
}

/// Subset of the Audnexus book payload we care about; tolerant of missing fields.
private struct AudnexusBook: Decodable {
    let title: String?
    let subtitle: String?
    let asin: String?
    let isbn: String?
    let authors: [NamedEntity]?
    let narrators: [NamedEntity]?
    let publisherName: String?
    let summary: String?
    let releaseDate: String?
    let image: String?
    let genres: [Genre]?
    let seriesPrimary: SeriesEntry?
    let seriesSecondary: SeriesEntry?
    let language: String?
    let runtimeLengthMin: Int?

    struct NamedEntity: Decodable { let name: String? }
    struct Genre: Decodable { let name: String?; let type: String? }
    struct SeriesEntry: Decodable { let name: String?; let position: String? }

    func normalized(providerName: String) -> BookSearchResult {
        let authorNames = (authors ?? []).compactMap { $0.name }.joined(separator: ", ")
        let narratorNames = (narrators ?? []).compactMap { $0.name }.joined(separator: ", ")
        let genreNames = (genres ?? [])
            .filter { ($0.type ?? "genre") == "genre" }
            .compactMap { $0.name }
        let year = releaseDate.flatMap { $0.split(separator: "-").first.map(String.init) }

        // Audible sometimes sends sequences like "Book 1" — keep just the numeric portion.
        let cleanedSequence = seriesPrimary?.position.flatMap { Self.cleanSequence($0) }

        let langCapitalized = language.flatMap { lang -> String? in
            guard let first = lang.first else { return nil }
            return first.uppercased() + lang.dropFirst()
        }

        return BookSearchResult(
            providerName: providerName,
            title: title ?? "Untitled",
            subtitle: subtitle,
            author: authorNames.isEmpty ? nil : authorNames,
            narrator: narratorNames.isEmpty ? nil : narratorNames,
            publisher: publisherName,
            publishedYear: year,
            description: summary,
            coverURL: image,
            asin: asin,
            isbn: isbn,
            genres: genreNames,
            series: seriesPrimary?.name,
            seriesSequence: cleanedSequence,
            language: langCapitalized,
            duration: runtimeLengthMin.map { TimeInterval($0 * 60) }
        )
    }

    /// Extracts the first number (with optional decimal) from a sequence string.
    private static func cleanSequence(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: "\\.?\\d+(?:\\.\\d+)?", options: .regularExpression) {
            return String(trimmed[range])
        }
        return trimmed
    }
}

// MARK: - Metadata service facade

/// Registry + entry point for metadata lookups. Holds the available providers and exposes a
/// simple search API for the UI. @MainActor @Observable so the UI can bind selection state.
@MainActor
@Observable
public final class MetadataService {
    public static let shared = MetadataService()

    /// Available providers, in display order. Audible (Audnexus) is first for audiobook richness.
    public let providers: [MetadataProvider]

    /// Currently selected provider id (for the UI picker).
    public var selectedProviderID: String

    public init(providers: [MetadataProvider] = [AudibleProvider()]) {
        self.providers = providers
        self.selectedProviderID = providers.first?.id ?? ""
    }

    public var selectedProvider: MetadataProvider? {
        providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    /// The selected provider's precise-identifier label (e.g. "ASIN"), or nil if unsupported.
    public var identifierLabel: String? { selectedProvider?.identifierLabel }

    /// Searches using the currently selected provider. A non-empty `identifier` (e.g. ASIN) takes
    /// precedence and performs a precise single-item lookup; otherwise a title/author search runs.
    public func search(title: String, author: String?, identifier: String? = nil) async throws -> [BookSearchResult] {
        guard let provider = selectedProvider else { throw MetadataProviderError.badResponse }
        if let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty {
            return try await provider.searchByIdentifier(identifier)
        }
        return try await provider.searchBooks(title: title, author: author)
    }
}
