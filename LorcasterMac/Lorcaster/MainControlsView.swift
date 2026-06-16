import SwiftUI
import AppKit
import LorcasterCore
import LorcasterServer
import LorcasterPlayer

struct MainControlsView: View {
    @Bindable var coreStore: CoreStore
    let server: ServerController
    @Bindable var player: PlayerController

    var body: some View {
        TabView {
            DashboardTab(coreStore: coreStore, server: server, player: player)
                .tabItem { Label("Dashboard", systemImage: "house.fill") }

            PlayerTab(player: player, coreStore: coreStore)
                .tabItem { Label("Player", systemImage: "play.circle.fill") }

            LibraryTab(coreStore: coreStore, player: player)
                .tabItem { Label("Library", systemImage: "folder.fill") }

            ServerTab(server: server)
                .tabItem { Label("Server", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .padding()
    }
}

private struct DashboardTab: View {
    @Bindable var coreStore: CoreStore
    let server: ServerController
    @Bindable var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.title2)

            HStack {
                Label("Server", systemImage: "server.rack")
                Spacer()
                Text(server.status).foregroundStyle(server.isRunning ? .green : .secondary)
            }
            HStack {
                Label("Player", systemImage: "playpause")
                Spacer()
                Text(player.isPlaying ? "Playing" : "Idle").foregroundStyle(player.isPlaying ? .green : .secondary)
            }

            Divider()

            Text("Library (\(coreStore.items.count))")
                .font(.headline)

            List(coreStore.items) { item in
                VStack(alignment: .leading) {
                    Text(item.title)
                    if let a = item.author { Text(a).font(.caption2).foregroundStyle(.secondary) }
                    Text("\(Int(item.duration))s • \(item.source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    player.load(item)
                }
            }
            .frame(minHeight: 120)

            HStack {
                Button("Load First & Play") {
                    if let first = coreStore.items.first {
                        player.load(first)
                        player.play()
                    }
                }
                Button("Toggle Server") { Task { await server.toggle() } }
            }
        }
    }
}

private struct PlayerTab: View {
    @Bindable var player: PlayerController
    @Bindable var coreStore: CoreStore

    @State private var coverImage: NSImage?
    @State private var isLoadingCover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now Playing")
                .font(.title2)

            if let item = player.currentItem {
                // PlayerTab visual cover — now 3x larger with .scaledToFit() + padding for nice containment.
                if let coverURL = coreStore.bestCoverURL(for: item) {
                    // Sized container (like the working library grid) so the artwork area is
                    // always the desired large size, even while the image is loading.
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .frame(maxWidth: .infinity, maxHeight: 540)
                        .overlay {
                            Group {
                                if let img = coverImage {
                                    Image(nsImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(16)
                                } else if isLoadingCover {
                                    ProgressView()
                                } else {
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .task(id: coverURL) {
                            isLoadingCover = true
                            coverImage = nil
                            if coverURL.isFileURL {
                                // Local cover: read while the security scope is active.
                                let didStart = coverURL.startAccessingSecurityScopedResource()
                                defer { if didStart { coverURL.stopAccessingSecurityScopedResource() } }
                                coverImage = NSImage(contentsOf: coverURL)
                            } else {
                                // Remote provider artwork: fetch asynchronously so the main actor isn't blocked.
                                if let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                                    coverImage = NSImage(data: data)
                                }
                            }
                            isLoadingCover = false
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.headline)
                    if let author = item.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let chapter = player.currentChapter {
                        Text("Chapter: \(chapter.title)")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    Text("\(formatDuration(player.currentTime)) / \(formatDuration(player.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            } else {
                Text("No item loaded")
                    .foregroundStyle(.secondary)
            }

            // Playback controls + chapter navigation
            HStack(spacing: 12) {
                Button(action: { player.skipToPreviousChapter() }) {
                    Label("Prev Chapter", systemImage: "backward.fill")
                }
                .disabled(player.chapters.isEmpty)

                Button(action: { player.toggle() }) {
                    Label(player.isPlaying ? "Pause" : "Play",
                          systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .controlSize(.large)

                Button(action: { player.skipToNextChapter() }) {
                    Label("Next Chapter", systemImage: "forward.fill")
                }
                .disabled(player.chapters.isEmpty)

                Button("Stop", action: player.stop)

                Stepper(value: Binding(get: { player.rate }, set: { player.setRate($0) }), in: 0.5...2.0, step: 0.25) {
                    Text("Rate \(player.rate, specifier: "%.2f")x")
                }
            }

            // Queue navigation
            HStack {
                Button("Previous", action: player.skipToPrevious)
                    .disabled(player.currentQueueIndex.map { $0 == 0 } ?? true)
                Button("Next", action: player.skipToNext)
                    .disabled(player.currentQueueIndex.map { $0 + 1 >= player.queue.count } ?? true)
            }

            Divider()

            // Chapters
            if !player.chapters.isEmpty {
                Text("Chapters (\(player.chapters.count))")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(player.chapters) { chapter in
                            Button {
                                player.playChapter(chapter)
                            } label: {
                                HStack {
                                    Text(chapter.title)
                                        .foregroundStyle(player.currentChapter?.id == chapter.id ? .primary : .secondary)
                                    Spacer()
                                    if let dur = chapter.duration {
                                        Text(formatDuration(dur))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
            } else {
                Text("No chapters for current item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Up Next / Queue
            Text("Up Next (\(player.queue.count))")
                .font(.headline)
            if player.queue.isEmpty {
                Text("Queue is empty. Tap items in Library to play or enqueue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .font(index == (player.currentQueueIndex ?? -1) ? .headline : .body)
                                if let author = item.author {
                                    Text(author).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if index == (player.currentQueueIndex ?? -1) {
                                Text("Now Playing")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.playNow(item)   // jump to this item in queue
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 80, maxHeight: 160)
            }
        }
        .padding(.horizontal, 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

private struct ServerTab: View {
    let server: ServerController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Casting Server")
                .font(.title2)

            HStack {
                Text("Status:")
                Text(server.status)
                    .foregroundStyle(server.isRunning ? .green : .red)
                    .bold()
            }

            HStack {
                Text("Clients:")
                Text("\(server.connectedClients)")
            }

            Button(server.isRunning ? "Stop Server" : "Start Server") {
                Task { await server.toggle() }
            }
            .buttonStyle(.borderedProminent)

            Text("This is a placeholder. Real implementation would expose endpoints for casting audio/video to clients or network receivers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Library Tab
// Polished to match a modern macOS Music.app-style "Albums" / Books grid.
// Uses real covers from coverRelativePath, groups multi-chapter books (one entry per book folder with chapters),
// clean square artwork cards, header with search + sort, folder chips, etc.

private struct LibraryTab: View {
    @Bindable var coreStore: CoreStore
    @Bindable var player: PlayerController

    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .title
    @State private var hoveredItemID: UUID? = nil
    @State private var infoItem: CastItem? = nil
    @State private var chapterEditItem: CastItem? = nil
    // Persisted across launches; defaults to Series. Controls how the Books view is grouped.
    @AppStorage("libraryGroupBy") private var groupBy: GroupBy = .series
    @State private var selectedGroupID: String? = nil   // drilled-into author/series (by group id)

    private enum SortMode: String, CaseIterable, Identifiable {
        case title = "Title"
        case author = "Author"
        case duration = "Duration"
        case source = "Folder"
        var id: Self { self }
    }

    /// How the Books view is grouped. "None" is the flat all-books grid; Author/Series group accordingly.
    private enum GroupBy: String, CaseIterable, Identifiable {
        case none = "None"
        case author = "Author"
        case series = "Series"
        var id: Self { self }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: 18)]
    private static let unknownAuthorLabel = "Unknown Author"

    /// Items matching the current search text (no sort applied). Shared by all browse modes.
    private var filteredItems: [CastItem] {
        let base = coreStore.items
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { item in
            item.title.lowercased().contains(q) ||
            (item.author?.lowercased().contains(q) ?? false) ||
            (item.series?.lowercased().contains(q) ?? false) ||
            item.source.lowercased().contains(q) ||
            item.chapters.contains { $0.title.lowercased().contains(q) }
        }
    }

    private var filteredAndSortedItems: [CastItem] {
        let filtered = filteredItems
        switch sortMode {
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author:
            return filtered.sorted {
                ($0.author ?? "").localizedCaseInsensitiveCompare($1.author ?? "") == .orderedAscending
            }
        case .duration:
            return filtered.sorted { $0.duration > $1.duration }
        case .source:
            return filtered.sorted { ($0.source + $0.title).localizedCaseInsensitiveCompare($1.source + $1.title) == .orderedAscending }
        }
    }

    // MARK: - Grouping (Phase 2: Authors / Series)

    /// Books grouped by author, authors A→Z, each author's books ordered by series then title.
    private var authorGroups: [LibraryGroup] {
        let dict = Dictionary(grouping: filteredItems) { item -> String in
            let a = item.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return a.isEmpty ? Self.unknownAuthorLabel : a
        }
        return dict.map { key, items in
            LibraryGroup(id: key, name: key, items: items.sorted(by: Self.bySeriesThenTitle))
        }
        .sorted { lhs, rhs in
            // Keep "Unknown Author" last.
            if lhs.name == Self.unknownAuthorLabel { return false }
            if rhs.name == Self.unknownAuthorLabel { return true }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// One entry in the Series browse grid: either a real multi-book series (drills in) or a single
    /// standalone book (plays directly). Standalone books are listed alongside series alphabetically
    /// rather than collected into a separate "Singles" section.
    enum SeriesEntry: Identifiable {
        case series(LibraryGroup)
        case single(CastItem)

        var id: String {
            switch self {
            case .series(let g): return "series:\(g.id)"
            case .single(let i): return "single:\(i.id.uuidString)"
            }
        }
        /// Alphabetical sort key — series name or book title.
        var sortKey: String {
            switch self {
            case .series(let g): return g.name
            case .single(let i): return i.title
            }
        }
    }

    /// Splits the filtered library into genuine multi-book series and standalone books. A series is
    /// "real" when it has 2+ books, or any book carries a series position/sequence (the signal that
    /// distinguishes a real series from a one-off that merely has a series name). Everything else is a
    /// single. Series books are ordered by numeric sequence then title.
    private var seriesPartition: (groups: [LibraryGroup], singles: [CastItem]) {
        var bySeries: [String: [CastItem]] = [:]
        var singles: [CastItem] = []

        for item in filteredItems {
            let s = item.series?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if s.isEmpty {
                singles.append(item)
            } else {
                bySeries[s, default: []].append(item)
            }
        }

        var groups: [LibraryGroup] = []
        for (name, books) in bySeries {
            let isRealSeries = books.count >= 2 || books.contains { ($0.seriesSequence?.isEmpty) == false }
            if isRealSeries {
                groups.append(LibraryGroup(id: name, name: name, items: books.sorted(by: Self.bySequenceThenTitle)))
            } else {
                singles.append(contentsOf: books)   // one-off with a series name but no real series
            }
        }
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (groups, singles)
    }

    /// Series + standalone books merged into one alphabetically-sorted list of browse entries.
    private func seriesEntries(from part: (groups: [LibraryGroup], singles: [CastItem])) -> [SeriesEntry] {
        var entries: [SeriesEntry] = part.groups.map { .series($0) }
        entries += part.singles.map { .single($0) }
        return entries.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
    }

    /// Numeric value of a book's series sequence ("1.5" → 1.5); books without a sequence sort last.
    private static func sequenceValue(_ item: CastItem) -> Double {
        guard let s = item.seriesSequence, let d = Double(s) else { return .greatestFiniteMagnitude }
        return d
    }

    private static func bySequenceThenTitle(_ lhs: CastItem, _ rhs: CastItem) -> Bool {
        let l = sequenceValue(lhs), r = sequenceValue(rhs)
        if l != r { return l < r }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func bySeriesThenTitle(_ lhs: CastItem, _ rhs: CastItem) -> Bool {
        let ls = lhs.series ?? "", rs = rhs.series ?? ""
        if ls != rs {
            // Books in a series first (grouped), then standalone.
            if ls.isEmpty != rs.isEmpty { return rs.isEmpty }
            return ls.localizedCaseInsensitiveCompare(rs) == .orderedAscending
        }
        return bySequenceThenTitle(lhs, rhs)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Music.app-style header
            HStack {
                Text("Books")
                    .font(.title2.weight(.semibold))

                if coreStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 6)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Search scoped to this view (like "Find in Albums")
                TextField("Search books, authors, series", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                // Group the library by Author or Series (or None for a flat list).
                Picker("Group by", selection: $groupBy) {
                    ForEach(GroupBy.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                if groupBy == .none {
                    Picker("Sort", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                // Action buttons on the right, like toolbar items
                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .help("Add a folder containing books or chapter files")

                Button {
                    Task { await coreStore.rescanAll() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(coreStore.libraryRootNames.isEmpty)
                .help("Re-scan all bookmarked folders")

                Button {
                    coreStore.clearLibrary()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(coreStore.items.isEmpty)
                .help("Clear library")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            // Folder chips (the "Library" sources)
            if !coreStore.libraryRootNames.isEmpty {
                HStack(spacing: 6) {
                    Text("Sources:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)

                    ForEach(coreStore.libraryRootNames, id: \.self) { name in
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.caption2)
                            Button {
                                coreStore.removeLibraryFolder(named: name)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Status line
            HStack {
                let count = filteredAndSortedItems.count
                Text("\(count) book\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)

                Spacer()

                if let err = coreStore.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.trailing, 12)
                }
            }
            .padding(.bottom, 4)

            // Main content — flat Books grid, or grouped by Author / Series.
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    coreStore.items.isEmpty ? "No books in library" : "No matches",
                    systemImage: coreStore.items.isEmpty ? "books.vertical" : "magnifyingglass",
                    description: Text(coreStore.items.isEmpty
                        ? "Add a folder with audiobook files. Multi-chapter books (separate audio files per chapter) are now shown as single entries with chapters."
                        : "Try a different search or clear the filter.")
                )
                .frame(maxHeight: .infinity)
            } else {
                switch groupBy {
                case .none:
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 18) {
                            ForEach(filteredAndSortedItems) { item in
                                BookCard(item: item, coreStore: coreStore, player: player,
                                         hoveredItemID: $hoveredItemID, infoItem: $infoItem,
                                         chapterItem: $chapterEditItem)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                case .author:
                    groupedBrowse(authorGroups, backLabel: "Authors")
                case .series:
                    seriesBrowse()
                }
            }

            // Bottom status (sources + count)
            HStack {
                Text("\(filteredAndSortedItems.count) shown • \(coreStore.libraryCount) source(s)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 16)
                    .padding(.bottom, 8)
                Spacer()
            }
        }
        .sheet(item: $infoItem) { item in
            BookInfoView(item: item, coreStore: coreStore)
        }
        .sheet(item: $chapterEditItem) { item in
            ChapterEditorView(item: item, coreStore: coreStore, player: player)
        }
        .onChange(of: groupBy) { _, _ in selectedGroupID = nil }
    }

    /// Two-level grouped browsing: a grid of group cards, drilling into a focused detail view.
    @ViewBuilder
    private func groupedBrowse(_ groups: [LibraryGroup], backLabel: String) -> some View {
        if let id = selectedGroupID, let group = groups.first(where: { $0.id == id }) {
            groupDetail(group, backLabel: backLabel)
        } else {
            groupGrid(groups)
        }
    }

    /// Series browse: a single alphabetical grid mixing series cards (drill-in) and standalone books
    /// (which play directly). Drilling into a series shows its focused detail view.
    @ViewBuilder
    private func seriesBrowse() -> some View {
        let part = seriesPartition
        if let id = selectedGroupID, let group = part.groups.first(where: { $0.id == id }) {
            groupDetail(group, backLabel: "Series")
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(seriesEntries(from: part)) { entry in
                        switch entry {
                        case .series(let group):
                            GroupCard(group: group, coreStore: coreStore) {
                                selectedGroupID = group.id
                            }
                        case .single(let item):
                            BookCard(item: item, coreStore: coreStore, player: player,
                                     hoveredItemID: $hoveredItemID, infoItem: $infoItem,
                                     chapterItem: $chapterEditItem)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    /// Grid of author/series cards (representative artwork + name + count). Tapping drills in.
    private func groupGrid(_ groups: [LibraryGroup]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 18) {
                ForEach(groups) { group in
                    GroupCard(group: group, coreStore: coreStore) {
                        selectedGroupID = group.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// Focused detail for a single author/series: back button, header with stacked artwork + count,
    /// then that group's books.
    private func groupDetail(_ group: LibraryGroup, backLabel: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    selectedGroupID = nil
                } label: {
                    Label(backLabel, systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)

                GroupArtwork(group: group, coreStore: coreStore, compact: true)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text("\(group.items.count) book\(group.items.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(group.items) { item in
                        BookCard(item: item, coreStore: coreStore, player: player,
                                 hoveredItemID: $hoveredItemID, infoItem: $infoItem,
                                 chapterItem: $chapterEditItem)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Media Library Folder"
        panel.message = "Choose a folder containing audiobooks. Folders with multiple chapter files will be shown as single books."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add to Library"

        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                await coreStore.addLibraryFolder(url)
            }
        }
    }
}

// MARK: - Group browsing (Authors / Series cards + drill-in)

/// A named bucket of books (one author or one series).
private struct LibraryGroup: Identifiable {
    let id: String
    let name: String
    let items: [CastItem]
}

/// Representative artwork for a group: the first book's cover, with a subtle "stacked" look when the
/// group holds more than one book. `compact` (used in the detail header) drops the stack + fills a fixed frame.
private struct GroupArtwork: View {
    let group: LibraryGroup
    @Bindable var coreStore: CoreStore
    var compact: Bool = false

    private var coverURL: URL? {
        group.items.first.flatMap { coreStore.bestCoverURL(for: $0) }
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    if !compact && group.items.count > 1 {
                        backer.offset(x: 8, y: 8).opacity(0.4)
                        backer.offset(x: 4, y: 4).opacity(0.7)
                    }
                    coverImage
                }
            }
    }

    private var backer: some View {
        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
    }

    private var coverImage: some View {
        Group {
            if let coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private var placeholder: some View {
        Color.gray.opacity(0.15)
            .overlay {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
    }
}

/// A clickable card for one author or series in the grouped browse grid.
private struct GroupCard: View {
    let group: LibraryGroup
    @Bindable var coreStore: CoreStore
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupArtwork(group: group, coreStore: coreStore)
            Text(group.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(group.items.count) book\(group.items.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(6)
        .background(hovering ? Color.gray.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
    }
}

// MARK: - Book Card (reused by Books grid + Author/Series sections)

private struct BookCard: View {
    let item: CastItem
    @Bindable var coreStore: CoreStore
    @Bindable var player: PlayerController
    @Binding var hoveredItemID: UUID?
    @Binding var infoItem: CastItem?
    @Binding var chapterItem: CastItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Robust square thumbnail: a clear square sized by the grid cell, with the image
            // overlaid and clipped so it never exceeds the thumbnail bounds.
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Group {
                            // Prefer a detected local cover, fall back to provider artwork from Get Info.
                            if let coverURL = coreStore.bestCoverURL(for: item) {
                                AsyncImage(url: coverURL) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    } else if phase.error != nil {
                                        Color.gray.opacity(0.2)
                                    } else {
                                        Color.gray.opacity(0.15)
                                    }
                                }
                            } else {
                                Color.gray.opacity(0.15)
                                    .overlay {
                                        Image(systemName: "book.closed.fill")
                                            .font(.system(size: 42))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                    }
                            }
                        }
                        .clipped()
                        .cornerRadius(6)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)

                // Hover play button
                Button {
                    player.playNow(item)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.65)))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .opacity(hoveredItemID == item.id ? 1.0 : 0.0)
            }
            .onHover { isHovered in
                hoveredItemID = isHovered ? item.id : nil
            }
            .onTapGesture {
                player.playNow(item)
            }

            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let series = item.seriesDisplay {
                Text(series)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                if item.chapters.count > 1 {
                    Text("\(item.chapters.count) chapters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(formatDuration(item.duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contextMenu {
            Button("Play Now") { player.playNow(item) }
            Button("Play Next") { player.playNext(item) }
            Button("Add to Queue") { player.enqueue(item) }
            Divider()
            Button("Get Info…") { infoItem = item }
            Button("Edit Chapters…") { chapterItem = item }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Book Info / Match (Phase 2)
// Get Info editor: manual metadata editing + online provider lookup (Audible via Audnexus).
// Left column: editable details. Right column: search a provider and apply a result to the form.
// Saving writes the merged item back into CoreStore (the file's duration/paths stay authoritative).

private struct BookInfoView: View {
    let item: CastItem
    @Bindable var coreStore: CoreStore
    @Environment(\.dismiss) private var dismiss

    @State private var metadata = MetadataService()

    // Editable fields (initialized from the item).
    @State private var title: String
    @State private var subtitle: String
    @State private var author: String
    @State private var narrator: String
    @State private var series: String
    @State private var seriesSequence: String
    @State private var publishedYear: String
    @State private var publisher: String
    @State private var language: String
    @State private var isbn: String
    @State private var asin: String
    @State private var genresText: String
    @State private var bookDescription: String

    // Carried-through fields not directly edited but updated when a result is applied.
    @State private var remoteCoverURL: String?

    // Search state.
    @State private var searchTitle: String
    @State private var searchAuthor: String
    @State private var searchIdentifier: String   // precise lookup (e.g. ASIN)
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    init(item: CastItem, coreStore: CoreStore) {
        self.item = item
        self.coreStore = coreStore
        _title = State(initialValue: item.title)
        _subtitle = State(initialValue: item.subtitle ?? "")
        _author = State(initialValue: item.author ?? "")
        _narrator = State(initialValue: item.narrator ?? "")
        _series = State(initialValue: item.series ?? "")
        _seriesSequence = State(initialValue: item.seriesSequence ?? "")
        _publishedYear = State(initialValue: item.publishedYear ?? "")
        _publisher = State(initialValue: item.publisher ?? "")
        _language = State(initialValue: item.language ?? "")
        _isbn = State(initialValue: item.isbn ?? "")
        _asin = State(initialValue: item.asin ?? "")
        _genresText = State(initialValue: item.genres.joined(separator: ", "))
        _bookDescription = State(initialValue: item.bookDescription ?? "")
        _remoteCoverURL = State(initialValue: item.remoteCoverURL)
        _searchTitle = State(initialValue: item.title)
        _searchAuthor = State(initialValue: item.author ?? "")
        // Prefill the precise-lookup field: a stored ASIN, else one detected in the title/folder name.
        let detected = AudibleProvider.detectASIN(in: "\(item.title) \(item.relativePath ?? "")")
        _searchIdentifier = State(initialValue: item.asin ?? detected ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Book Info")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                detailsForm
                    .frame(width: 380)

                Divider()

                matchPanel
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    // MARK: Left — editable details

    private var detailsForm: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    coverPreview
                    Spacer()
                }
            }
            Section("Details") {
                TextField("Title", text: $title)
                TextField("Subtitle", text: $subtitle)
                TextField("Author", text: $author)
                TextField("Narrator", text: $narrator)
            }
            Section("Series") {
                TextField("Series", text: $series)
                TextField("Sequence", text: $seriesSequence)
            }
            Section("Publication") {
                TextField("Year", text: $publishedYear)
                TextField("Publisher", text: $publisher)
                TextField("Language", text: $language)
                TextField("Genres (comma separated)", text: $genresText)
                TextField("ISBN", text: $isbn)
                TextField("ASIN", text: $asin)
            }
            Section("Description") {
                TextEditor(text: $bookDescription)
                    .frame(minHeight: 90)
                    .font(.body)
            }
        }
        .formStyle(.grouped)
    }

    private var coverPreview: some View {
        Group {
            if let remote = remoteCoverURL, let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        coverPlaceholder
                    } else {
                        ProgressView()
                    }
                }
            } else if let localURL = coreStore.coverURL(for: item) {
                AsyncImage(url: localURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 120, height: 120)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(8)
    }

    private var coverPlaceholder: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: 36))
            .foregroundStyle(.secondary)
    }

    // MARK: Right — online match

    private var matchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find Metadata Online")
                .font(.headline)

            if metadata.providers.count > 1 {
                Picker("Provider", selection: $metadata.selectedProviderID) {
                    ForEach(metadata.providers, id: \.id) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
            } else if let provider = metadata.providers.first {
                Text("Provider: \(provider.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Title", text: $searchTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Author (optional)", text: $searchAuthor)
                .textFieldStyle(.roundedBorder)

            if let idLabel = metadata.identifierLabel {
                TextField("\(idLabel) — exact match (optional)", text: $searchIdentifier)
                    .textFieldStyle(.roundedBorder)
                Text("If set, \(idLabel) is used for a precise lookup and overrides title/author.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    runSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(!canSearch || isSearching)

                if isSearching {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            if let err = searchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            if results.isEmpty && !isSearching {
                ContentUnavailableView(
                    "No results yet",
                    systemImage: "magnifyingglass",
                    description: Text("Search a provider, then click a result to fill in the details.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding()
    }

    private func resultRow(_ result: BookSearchResult) -> some View {
        Button {
            apply(result)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let cover = result.coverURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color.gray.opacity(0.12)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .cornerRadius(4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if let author = result.author {
                        Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let year = result.publishedYear {
                            Text(year).font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let narrator = result.narrator {
                            Text("Read by \(narrator)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    if let series = result.series {
                        let seq = result.seriesSequence.map { " #\($0)" } ?? ""
                        Text("\(series)\(seq)").font(.caption2).foregroundStyle(.tint)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// Search is enabled when there's a title or a precise identifier to look up.
    private var canSearch: Bool {
        !searchTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !searchIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runSearch() {
        let t = searchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = searchAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = searchIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !identifier.isEmpty else { return }
        isSearching = true
        searchError = nil
        results = []
        Task {
            do {
                let found = try await metadata.search(
                    title: t,
                    author: a.isEmpty ? nil : a,
                    identifier: identifier.isEmpty ? nil : identifier
                )
                results = found
                if found.isEmpty { searchError = "No matches found." }
            } catch {
                searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSearching = false
        }
    }

    /// Fills the form from a chosen result, merged over the user's current edits.
    private func apply(_ result: BookSearchResult) {
        let merged = currentEditedItem().merging(result)
        title = merged.title
        subtitle = merged.subtitle ?? ""
        author = merged.author ?? ""
        narrator = merged.narrator ?? ""
        series = merged.series ?? ""
        seriesSequence = merged.seriesSequence ?? ""
        publishedYear = merged.publishedYear ?? ""
        publisher = merged.publisher ?? ""
        language = merged.language ?? ""
        isbn = merged.isbn ?? ""
        asin = merged.asin ?? ""
        genresText = merged.genres.joined(separator: ", ")
        bookDescription = merged.bookDescription ?? ""
        remoteCoverURL = merged.remoteCoverURL
    }

    /// Builds a CastItem from the current form fields (preserving id/duration/paths/chapters/source).
    private func currentEditedItem() -> CastItem {
        func nilIfEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var updated = item
        updated.title = nilIfEmpty(title) ?? item.title
        updated.subtitle = nilIfEmpty(subtitle)
        updated.author = nilIfEmpty(author)
        updated.narrator = nilIfEmpty(narrator)
        updated.series = nilIfEmpty(series)
        updated.seriesSequence = nilIfEmpty(seriesSequence)
        updated.publishedYear = nilIfEmpty(publishedYear)
        updated.publisher = nilIfEmpty(publisher)
        updated.language = nilIfEmpty(language)
        updated.isbn = nilIfEmpty(isbn)
        updated.asin = nilIfEmpty(asin)
        updated.bookDescription = nilIfEmpty(bookDescription)
        updated.remoteCoverURL = remoteCoverURL
        updated.genres = genresText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return updated
    }

    private func save() {
        coreStore.updateItem(currentEditedItem())
        dismiss()
    }
}

// MARK: - Chapter Editor (Phase 2)
// Edit a book's chapters. Two modes:
//  • Multi-file books (one audio file per chapter): rename chapters only; start times come from files.
//  • Single-file / embedded books (.m4b): edit titles + start times, add/remove chapters, or reload
//    embedded markers from the file. Saving marks the book as user-edited so the player uses this list.

private struct ChapterEditorView: View {
    let item: CastItem
    @Bindable var coreStore: CoreStore
    @Bindable var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var chapters: [Chapter] = []
    @State private var isLoading = true

    /// Multi-file book: each chapter is a separate audio file (has its own relativePath).
    private var isMultiFile: Bool {
        item.chapters.count > 1 && item.chapters.contains { $0.relativePath != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            infoBar

            if isLoading {
                ProgressView("Loading chapters…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chapters.isEmpty {
                ContentUnavailableView(
                    "No chapters",
                    systemImage: "list.bullet.indent",
                    description: Text(isMultiFile
                        ? "This book has no chapter files."
                        : "No embedded chapters were found. Add chapters manually below.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chapterList
            }

            if !isMultiFile {
                Divider()
                bottomBar
            }
        }
        .frame(minWidth: 580, minHeight: 540)
        .task { await loadInitialChapters() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("Edit Chapters")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            Text(isMultiFile
                 ? "One audio file per chapter — you can rename chapters; start times come from the files."
                 : "Edit titles and start times. Add or remove chapters, or reload embedded markers from the file.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(chapters.count) chapter\(chapters.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var chapterList: some View {
        List {
            ForEach($chapters) { $chapter in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Chapter title", text: $chapter.title)
                        .textFieldStyle(.plain)
                    Spacer(minLength: 8)
                    if isMultiFile {
                        Text(hms(chapter.startTime))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .font(.callout)
                    } else {
                        TextField("0:00", text: startBinding(for: $chapter))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }
            }
            .onDelete(perform: deleteAction)
        }
    }

    /// Delete is only allowed for single-file books (multi-file chapters map to physical files).
    private var deleteAction: ((IndexSet) -> Void)? {
        if isMultiFile { return nil }
        return { offsets in chapters.remove(atOffsets: offsets) }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                addChapter()
            } label: {
                Label("Add Chapter", systemImage: "plus")
            }

            Button {
                Task { await reloadFromFile() }
            } label: {
                Label("Load from File", systemImage: "arrow.clockwise")
            }
            .help("Replace the list with the embedded chapter markers from the audio file")

            Spacer()

            Text("Start times accept m:ss or h:mm:ss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    // MARK: Loading

    private func loadInitialChapters() async {
        // Use the stored list when the user already edited it, or for multi-file books (file-derived).
        if item.userEditedChapters || isMultiFile {
            chapters = item.chapters
            isLoading = false
            return
        }
        // Single-file: try to populate the real embedded markers from the audio file.
        if let url = coreStore.playableURL(for: item) {
            let embedded = await LibraryScanner.loadEmbeddedChapters(at: url)
            chapters = embedded.isEmpty ? item.chapters : embedded
        } else {
            chapters = item.chapters
        }
        isLoading = false
    }

    private func reloadFromFile() async {
        guard let url = coreStore.playableURL(for: item) else { return }
        isLoading = true
        let embedded = await LibraryScanner.loadEmbeddedChapters(at: url)
        if !embedded.isEmpty { chapters = embedded }
        isLoading = false
    }

    // MARK: Editing

    private func addChapter() {
        let start = chapters.last.map { $0.startTime + ($0.duration ?? 0) } ?? 0
        chapters.append(Chapter(title: "New Chapter", startTime: start, duration: nil))
    }

    private func save() {
        var finalChapters = chapters
        // For single-file books, normalize order and recompute per-chapter durations from start times
        // so the player's per-chapter local time + end detection stay correct.
        if !isMultiFile {
            finalChapters.sort { $0.startTime < $1.startTime }
            let total = item.duration
            for i in finalChapters.indices {
                let nextStart = (i + 1 < finalChapters.count)
                    ? finalChapters[i + 1].startTime
                    : (total > 0 ? total : finalChapters[i].startTime)
                let d = nextStart - finalChapters[i].startTime
                finalChapters[i].duration = d > 0 ? d : nil
            }
        }

        var updated = item
        updated.chapters = finalChapters
        updated.userEditedChapters = true
        coreStore.updateItem(updated)

        // If this exact book is loaded but paused/idle, reload so the new chapters take effect now.
        // Avoid interrupting active playback — the edits apply on the next load otherwise.
        if player.currentItem?.id == item.id && !player.isPlaying {
            player.load(updated)
        }
        dismiss()
    }

    // MARK: Time helpers

    private func startBinding(for chapter: Binding<Chapter>) -> Binding<String> {
        Binding(
            get: { hms(chapter.wrappedValue.startTime) },
            set: { if let secs = parseTime($0) { chapter.wrappedValue.startTime = secs } }
        )
    }

    private func hms(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Parses "h:mm:ss", "m:ss", or a plain seconds value.
    private func parseTime(_ str: String) -> TimeInterval? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if !trimmed.contains(":") { return Double(trimmed) }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count else { return nil }
        switch nums.count {
        case 2: return TimeInterval(nums[0] * 60 + nums[1])
        case 3: return TimeInterval(nums[0] * 3600 + nums[1] * 60 + nums[2])
        default: return nil
        }
    }
}
