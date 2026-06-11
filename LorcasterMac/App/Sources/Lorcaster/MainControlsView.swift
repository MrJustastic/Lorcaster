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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now Playing")
                .font(.title2)

            if let item = player.currentItem {
                // Real cover art from coverRelativePath (resolved via bookmark + scope)
                if let coverURL = coreStore.coverURL(for: item) {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(height: 160)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 180)
                                .cornerRadius(8)
                        case .failure:
                            Color.secondary.frame(height: 120)
                        @unknown default:
                            EmptyView()
                        }
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

// MARK: - Library Tab (Phase 1: Add Folder with NSOpenPanel+bookmarks, real recursive FileManager+AVAsset scan via LibraryScanner actor, CoreStore updates with live progress, list/grid, add/remove/rescan/clear/filters. Matches Audiobookshelf parity conventions.)

private struct LibraryTab: View {
    @Bindable var coreStore: CoreStore
    @Bindable var player: PlayerController

    @State private var useGrid: Bool = false
    @State private var searchText: String = ""
    @State private var sortMode: SortMode = .title

    private enum SortMode: String, CaseIterable, Identifiable {
        case title = "Title"
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
                item.source.lowercased().contains(q)
            }
        }

        switch sortMode {
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .duration:
            return filtered.sorted { $0.duration > $1.duration }
        case .source:
            return filtered.sorted { ($0.source + $0.title).localizedCaseInsensitiveCompare($1.source + $1.title) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Library")
                    .font(.title2)

                if coreStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning… (\(coreStore.items.count) found)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Filters (Phase 1 MVP)
                TextField("Filter title/author/folder", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                // Basic list / grid toggle for UI parity update
                Picker("View", selection: $useGrid) {
                    Text("List").tag(false)
                    Text("Grid").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Button {
                    addFolder()
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
                .help("Choose a folder (NSOpenPanel). Creates security-scoped bookmark + recursive scan via actor.")

                Button("Rescan All") {
                    Task { await coreStore.rescanAll() }
                }
                .disabled(coreStore.libraryRootNames.isEmpty)
                .help("Re-scan all bookmarked folders using LibraryScanner actor")

                Button("Clear All") {
                    coreStore.clearLibrary()
                }
                .disabled(coreStore.items.isEmpty && coreStore.libraryRootNames.isEmpty)
                .help("Remove all bookmarks, items and stop scoped access")
            }

            // Show active bookmarked roots (from secure bookmarks) — removable for add/remove support
            if !coreStore.libraryRootNames.isEmpty {
                HStack(spacing: 6) {
                    Text("Folders:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(coreStore.libraryRootNames, id: \.self) { name in
                        HStack(spacing: 2) {
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
                            .help("Remove this folder and its items (bookmark revoked for this app)")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    }
                }
            }

            let displayCount = filteredAndSortedItems.count
            let totalCount = coreStore.items.count
            Text("\(displayCount) item(s)\(searchText.isEmpty ? "" : " (filtered from \(totalCount))") • \(coreStore.libraryCount) folder(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if coreStore.items.isEmpty {
                ContentUnavailableView(
                    "No media in library",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Add a folder with audio or video files (.mp3, .m4a, .m4b, .mp4 etc.). Bookmarks are stored securely (UserDefaults + app-scope) so access survives restarts. Scanner matches common audiobook folder layouts for covers + metadata.")
                )
            } else if filteredAndSortedItems.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different filter or clear search.")
                )
            } else if useGrid {
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
                                                if let coverURL = coreStore.coverURL(for: item) {
                                                    AsyncImage(url: coverURL) { phase in
                                                        if let image = phase.image {
                                                            image
                                                                .resizable()
                                                                .scaledToFill()
                                                        } else if phase.error != nil {
                                                            Color.gray.opacity(0.2)
                                                        } else {
                                                            Color.gray.opacity(0.15)
                                                        }
                                                    }
                                                } else {
                                                    // Placeholder
                                                    Color.gray.opacity(0.15)
                                                        .overlay {
                                                            Image(systemName: "book.closed.fill")
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
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 160)
            } else {
                // List view (matches existing Dashboard style but in dedicated Library tab)
                List(filteredAndSortedItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let author = item.author, !author.isEmpty {
                                Text(author).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("\(formatDuration(item.duration)) • \(item.source)\(item.coverRelativePath != nil ? " • 📷 cover" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load") { player.load(item) }
                            .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.load(item)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 160)
            }

            if let err = coreStore.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Phase 1 MVP: NSOpenPanel + security-scoped bookmarks (entitlements) + FileManager + AVAsset (title/author/duration) + cover detection (common names) + LibraryScanner actor (Sendable, AsyncStream for live progress) + relativePath for future play. Enhanced CastItem + Library model. Matches audiobook folder conventions. Clean separation: scanner in actor, store owns state/persist/scopes. (Hard fork, no upstream.)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Media Library Folder"
        panel.message = "Choose a folder containing audio or video files (or an audiobook tree). Access will be bookmarked securely with app-scope."
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
