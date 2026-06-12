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
                if let coverURL = coreStore.coverURL(for: item) {
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
                        .task(id: item.id) {
                            isLoadingCover = true
                            coverImage = nil
                            let didStart = coverURL.startAccessingSecurityScopedResource()
                            defer { if didStart { coverURL.stopAccessingSecurityScopedResource() } }
                            coverImage = NSImage(contentsOf: coverURL)
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

    private enum SortMode: String, CaseIterable, Identifiable {
        case title = "Title"
        case author = "Author"
        case duration = "Duration"
        case source = "Folder"
        var id: Self { self }
    }

    private var filteredAndSortedItems: [CastItem] {
        let base = coreStore.items
        let filtered: [CastItem]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = base
        } else {
            let q = searchText.lowercased()
            filtered = base.filter { item in
                item.title.lowercased().contains(q) ||
                (item.author?.lowercased().contains(q) ?? false) ||
                item.source.lowercased().contains(q) ||
                item.chapters.contains { $0.title.lowercased().contains(q) }
            }
        }

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
                TextField("Search books or chapters", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

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

            // Main grid — styled like Music.app Albums
            if filteredAndSortedItems.isEmpty {
                ContentUnavailableView(
                    coreStore.items.isEmpty ? "No books in library" : "No matches",
                    systemImage: coreStore.items.isEmpty ? "books.vertical" : "magnifyingglass",
                    description: Text(coreStore.items.isEmpty 
                        ? "Add a folder with audiobook files. Multi-chapter books (separate audio files per chapter) are now shown as single entries with chapters."
                        : "Try a different search or clear the filter.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(filteredAndSortedItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                // Robust square thumbnail for the grid.
                                // Color.clear + .aspectRatio(1, .fit) + .frame(maxWidth: .infinity) creates
                                // a square whose size is driven by the grid cell width. The actual image
                                // is overlaid and clipped to that exact square so it never exceeds the
                                // thumbnail bounds, even if the source image is huge or has wrong aspect.
                                ZStack(alignment: .bottomTrailing) {
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .overlay {
                                            Group {
                                                // Library grid artwork re-enabled (covers in the book grid).
                                                // Now Playing artwork and PlayerTab cover are still disabled
                                                // while we troubleshoot playback failures for audiobooks that have art.
                                                if let coverURL = coreStore.coverURL(for: item) {
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
                                                    // Placeholder when no cover image
                                                    Color.gray.opacity(0.15)
                                                        .overlay {
                                                            Image(systemName: "book-closed.fill")
                                                                .font(.system(size: 42))
                                                                .foregroundStyle(.secondary.opacity(0.6))
                                                        }
                                                }
                                            }
                                            .clipped()           // clip the scaled image to the square
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

                                // Title + artist (Music.app typography)
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

                                // Subtle chapter / duration hint
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
                                if !item.chapters.isEmpty {
                                    Button("Show Chapters") {
                                        // User can switch to Player tab; we could also auto-open Player later
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
