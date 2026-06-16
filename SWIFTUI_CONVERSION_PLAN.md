# Lorcaster → Native macOS SwiftUI App Conversion Plan

**Status**: Phase 0 complete (traditional .xcodeproj + menu bar + modular SPM). Phase 1 (Library + real playback + chapters + PlayerTab artwork) substantially complete: full library management + live scanner + real AVPlayer + robust chapter navigation for both multi-file books and embedded markers inside .m4b files + 3x larger .scaledToFit() now-playing artwork in PlayerTab (reliable scoped NSImage loading + sized Rounded container) + window minHeight raised so the large cover area is usable by default. System Now Playing artwork (MPMediaItemArtwork) intentionally left disabled for playback stability. (Current)  
**Project**: Lorcaster (personal fork of Audiobookshelf)  
**Target**: A single, fully self-contained macOS application built with Swift + SwiftUI.  
**Core Vision**: The "iTunes of Audiobooks" — a polished, native macOS app that handles library management, acts as a local server for other devices, *and* includes a full-featured built-in player. Users install one .app and never touch the terminal, Node.js, npm, web browsers for admin, or any external dependencies.

## Clarified Requirements (Direct from User)

- This is a **server-style app** that runs on **macOS only**.
- **Fully packaged and self-contained**: The end user never has to deal with the terminal, Node.js, npm, `dev.js`, separate processes, or web UIs. Everything is inside the .app bundle.
- It should feel like **iTunes / Music.app for audiobooks and podcasts** (beautiful native library management + server capabilities).
- The app **does contain a player** (matching the current web app's player features and parity). There is a separate consumption app for other platforms/devices, but this Mac app provides a complete local playback experience.
- Use **SwiftUI + Swift** for the best native look, feel, performance, and macOS integration.
- Maintain **feature parity** with the current Lorcaster (the rebranded version of what exists today): library scanning, metadata providers, chapters, OPML, users/permissions, backups, progress sync, real-time updates, etc.
- After conversion, the app will be **so different** (architecture, UI, packaging, internals) that **maintaining the upstream Audiobookshelf project will not be worth it**. This is a hard fork. We can redesign freely for native strengths.

**Important clarification on scope**:
- This single app = library manager UI + embedded server (for the separate consumption apps) + **full built-in player** (for the Mac user, with parity to the current web player: chapters, speed, sleep timer, queue, scrubbing, progress reporting, etc.).
- The separate consumption app handles playback on phones/tablets/other machines. This Mac app is self-sufficient with its own excellent player for direct local use.
- We are using a **traditional .xcodeproj** style (at `LorcasterMac/Lorcaster/Lorcaster.xcodeproj`) for the main app target. The three modular SPM packages (`LorcasterCore`, `LorcasterServer`, `LorcasterPlayer`) are added as local package dependencies. `MenuBarExtraAccess` is explicitly added to the target's Frameworks, Libraries, and Embedded Content. This approach gives better control over signing, entitlements, Info.plist, and future distribution/packaging scripts while preserving the modular SPM structure for the backend/player logic.
- The original Node.js backend + web client (in the parent `Lorcaster/` directory) are retained as the live reference implementation for maintaining feature parity during the port.

## High-Level Architecture

**Single native macOS .app ("Lorcaster")**

- **SwiftUI Layer** (the visible app):
  - iTunes/Music-style library browser (grid/list views, covers, progress bars, search, filters, sidebar navigation for Libraries / Authors / Series / Playlists / Stats / Settings).
  - Full-featured built-in player (bottom bar or dedicated window/panel) with chapter support, playback speed, sleep timer, queue, now-playing info, scrubbing, etc.
  - Management tools: Add libraries (local folders), manual metadata editing, chapter editor, OPML import/export, backups, user management.
  - Menu bar extra / status item for server status (even when the main window is closed) + quick controls.

- **Embedded Server Layer** (runs inside the same app):
  - Local file scanning and metadata extraction (using AVFoundation + other Swift libraries; bundle static ffmpeg if full current transcoding parity is required).
  - Database (SwiftData or GRDB + SQLite — replacing current Sequelize/SQLite).
  - HTTP server + REST API + WebSocket support (so the separate consumption apps can connect over the local network, Tailscale, etc.).
  - Media streaming with range requests (for remote players).
  - Progress sync from remote clients back to this server.
  - User authentication & permissions.
  - Real-time updates for connected clients.

- **No external Node.js or web frontend at runtime**. The current Node backend and Nuxt web client become reference material only during the port. The final app is 100% Swift.

**Packaging & Distribution**
- Standard macOS app bundle.
- Any necessary tools (e.g., a static `ffmpeg` binary if full current transcoding parity is required) are bundled inside the app.
- Users choose local folders via normal "Add Library" dialogs (using security-scoped bookmarks).
- The app can run the server in the background.
- Future: App Store or direct download + Sparkle updates. Code-signed and notarized.

**Data Flow**
- User adds local audiobook/podcast folders → app scans them (matching current folder structure conventions).
- Local Mac user browses the library and plays directly in the built-in SwiftUI player (full parity with current web player).
- Remote consumption apps connect to this Mac's Lorcaster instance for browsing + streaming + progress sync.

**Divergence Note**
Because this will be a complete native rewrite (no web layer, no Node), we are diverging heavily from the original Audiobookshelf. Parity is with *current features*, not the upstream project's future direction. We can (and should) make native-first decisions.

## Revised Phased Plan

### Phase 0: Project Setup & Core Architecture (1–2 weeks) — COMPLETE
- Created/used traditional .xcodeproj (macOS App using SwiftUI) at `LorcasterMac/Lorcaster/Lorcaster.xcodeproj` (project folder `LorcasterMac/Lorcaster/`).
- Scaffolded basic app target with `MenuBarExtra` (menu bar item labeled "LC" for background server operation).
- Modular SPM targets added as local package dependencies to the .xcodeproj:
  - `LorcasterCore/` (models, scanning logic, database)
  - `LorcasterServer/` (embedded HTTP/WebSocket server + API routes)
  - `LorcasterPlayer/` (AVFoundation-based player engine)
- (Previously used `MenuBarExtraAccess` v1.2.2 for extra status-item access + `isPresented` binding; removed in an attempt to reduce BaseBoard "task name port right" noise common to LSUIElement + sandbox + menu-bar apps. Plain `MenuBarExtra` + LSUIElement is used instead.)
- `LSUIElement` set via target's Custom macOS Application Target Properties (or matching the scaffold's `Resources/Info.plist`).
- App uses `@NSApplicationDelegateAdaptor(AppDelegate)` + `NSApp.setActivationPolicy(.accessory)` for proper menu-bar-first / agent behavior.
- The `.menuBarExtraAccess(isPresented:)` modifier is used for robustness.
- Menu bar "LC" item appears reliably when launching the built `.app` from Finder (Xcode's Run button can force regular app + Dock icon behavior).
- Project folder cleaned (removed nested SPM "App/" copy and .bak template files from the traditional project sources).
- The original Node.js backend + web client (in the parent directory) are retained in the repo as the live reference for feature parity during the port.
- SPM version of the app (in `LorcasterMac/App/`) remains available for quick terminal testing (`swift run Lorcaster` from the App dir).
- **Deliverable**: Working skeleton with menu bar item, main window (TabView with Library/Player/Server placeholders using mock wiring to the modules), Settings scene, and basic lifecycle. Runs cleanly in the traditional .xcodeproj.

### Phase 1: Library Management & Scanning + Real Local Playback (3–5 weeks) — Core spike DONE
- Add/remove local folders (with proper macOS security-scoped bookmarks + UserDefaults persistence + scoped lifetime).
- Recursive scanner using FileManager + AVAsset for metadata (title/author/duration/cover heuristics) + relativePath for playback resolution. Live via AsyncStream.
- Core data model (CastItem + Library with author/relative/cover; robust Codable).
- SwiftUI: LibraryTab (grid + list, search, sort, filters, folder chips w/ remove, rescan/clear, live scan progress, playable items).
- **Real playback spike**: PlayerController drives AVPlayer using CoreStore.playableURL (bookmark root + relativePath). Time observer, variable rate, seek, natural end all real (no more pure mock).
- Background scanning with live UI updates.
- Match current folder structure conventions and auto-detection.
- **Parity goal (achieved for MVP)**: User adds real audiobook folders via native dialog → items appear live with metadata → click to play the actual audio file in the built-in player with speed/scrub controls. Covers metadata detection is basic (filename heuristics + embedded); full providers in Phase 2.

### Phase 2: Metadata, Providers & Editing (3–4 weeks) — STARTED
- Implement metadata providers (Audible, iTunes, MusicBrainz, etc.) using URLSession + parsing. **[Audible done]**
- Chapter support (detection, editing, display in player). **[editing done]** *(detection/display were done in Phase 1)*
- OPML import/export for podcasts. *(pending)*
- Full metadata editing UI (titles, authors, covers, descriptions, etc. — matching current web capabilities). **[Get Info editor done]**
- Author/series grouping and management. **[grouping UI done]**
- **Parity goal**: All current metadata features from the web UI.

**Progress (first slice complete):**
- `CastItem` extended with rich metadata: `subtitle`, `narrator`, `series`, `seriesSequence`, `publishedYear`, `publisher`, `bookDescription`, `genres`, `language`, `isbn`, `asin`, `remoteCoverURL` (robust Codable; older persisted items decode fine; persistence key unchanged at `.v2`).
- New `Core/Sources/LorcasterCore/MetadataProvider.swift`: normalized `BookSearchResult`, a `MetadataProvider` protocol (extensible for iTunes/Google Books/etc.), `AudibleProvider` (two-step: Audible catalog product search → Audnexus ASIN enrichment, concurrent + order-preserving), and a `@MainActor @Observable MetadataService` facade with provider selection. Mirrors the Node `server/providers/Audible.js` field shape for parity. Validated live (e.g. "Project Hail Mary" → narrator/year/publisher/ASIN/cover/duration all populated).
- `CastItem.merging(_:)` (non-destructive provider merge; local file duration/paths stay authoritative) + `CoreStore.updateItem(_:)` (replace-by-id, rebuild dedup keys, persist).
- `BookInfoView` "Get Info / Match" sheet in `Lorcaster/MainControlsView.swift`: left = editable details form (title/subtitle/author/narrator/series/year/publisher/language/genres/ISBN/ASIN/description + cover preview), right = online provider search with clickable results that fill the form. Reached via the Library grid's right-click → "Get Info…". Saving writes the merged item back through `CoreStore`.
- Added `com.apple.security.network.client` entitlement (required for provider HTTP calls under the sandbox).
- Provider artwork now displays everywhere: `CoreStore.bestCoverURL(for:)` resolves the display cover, honoring a **"Prefer Local Artwork"** setting (`CoreStore.preferLocalArtwork`, default on, persisted): on → local cover wins (remote fallback); off → provider remote art wins (local fallback). Exposed as a toggle in Settings → Artwork. The Library grid and PlayerTab both use it (PlayerTab fetches remote covers asynchronously so the main actor isn't blocked; its load is keyed on the resolved URL so toggling the setting re-renders the now-playing art).
- **Precise ASIN lookup**: the `MetadataProvider` protocol gained `identifierLabel` + `searchByIdentifier(_:)` (default falls back to a title search). `AudibleProvider` exposes ASIN as its identifier and looks it up directly via Audnexus. `AudibleProvider.detectASIN(in:)` extracts an ASIN from common Audible folder naming (`Title [B08G9PRS1K]`, `(…)`, or a bare `B0…` token). The Get Info match panel now has an "ASIN — exact match" field that auto-prefills from a stored ASIN or one detected in the title/folder name, and overrides title/author when set for a single-item precise lookup. The **scanner** also auto-detects an ASIN from each book's folder/file/title during scanning, stores it on `CastItem.asin`, and strips the `[ASIN]` token from the displayed title (`LibraryScanner.cleanedTitle`) — so freshly scanned (or rescanned) books are exact-matchable out of the box. (Existing libraries pick this up on Rescan.)
- **Auto-Match All by ASIN** (batch): `CoreStore.autoMatchAllByASIN()` enriches every book that carries an ASIN via Audnexus and merges the result (non-destructive). Runs sequentially (polite to the API) with live observable progress (`isAutoMatching`, `autoMatchDone`/`autoMatchTotal`, `autoMatchSummary`, `asinMatchableCount`). Exposed as a button in Settings → Metadata with inline progress + a result summary; disabled while running or when no book has an ASIN.
- **Author/Series browsing**: a segmented "Books / Authors / Series" mode picker in the Library header. Authors mode groups A→Z (Unknown Author last); The library is a fixed **Books** view with a **"Group by" dropdown** (None / Author / Series), persisted via `@AppStorage("libraryGroupBy")` and defaulting to **Series** (reopens to the last-used grouping). "None" is the flat all-books grid (with the Sort menu); Author/Series use the grouped drill-in browsing. The Series grouping is a single alphabetical grid that mixes genuine multi-book series (drill-in cards) with standalone books (which play directly) — no separate "Singles" section. A series is "real" when it has 2+ books or any book carries a series position/sequence (the signal that distinguishes a real series from a one-off that merely has a series name); everything else is listed as an individual book among the series, sorted by title. Series detail orders books by numeric sequence ("1" < "1.5" < "2"). The flat **Books** view remains for an ungrouped layout. The book card was extracted into a reusable `BookCard` (shared by all modes); cards also show series + sequence. **Authors/Series are now navigable**: each mode shows a grid of group cards (representative "stacked" artwork from the first book + name + book count) that drill into a focused detail view (back button, header with artwork + count, that group's books). Selection is held by group id and resets when switching modes; `LibraryGroup` is file-scoped and reused by the card views (`GroupCard`/`GroupArtwork`). Search spans title/author/series/folder/chapters.
- **Chapter editing**: `Chapter` made mutable (title/startTime/duration) and `CastItem.userEditedChapters` added (robust Codable). The player now respects that flag — when set it uses the stored chapter list verbatim instead of re-deriving embedded `.m4b` markers on load. `LibraryScanner.loadEmbeddedChapters(at:)` (Core) loads embedded markers from a file URL so the editor can populate the real list. New `ChapterEditorView` sheet (reached via a book's right-click → "Edit Chapters…"): multi-file books allow title-only edits (times come from the files); single-file/embedded books allow full editing — titles, start times (m:ss / h:mm:ss parsing), add/remove, and "Load from File" to restore embedded markers. Save normalizes order + recomputes per-chapter durations from start times (keeps the player's per-chapter local-time + end detection correct), marks the book user-edited, and reloads the player if the book is loaded-but-idle.
- Note: work landed on the canonical xcodeproj tree (`Lorcaster/`) + the shared Core package; the stale SPM harness (`App/Sources/Lorcaster/`) was not retrofitted (it had already diverged at Phase 1).

### Phase 3: Built-in Player (Full Current Parity) (3–4 weeks)
- Native player using AVFoundation + AVKit (bottom bar + full expanded player view or separate window).
- Features to match web player parity:
  - Play/pause, seek, skip forward/back.
  - Chapter navigation and display.
  - Playback speed control.
  - Sleep timer.
  - Queue / playlist support.
  - Progress tracking and syncing (local + report to server for remote clients).
  - Now Playing integration (macOS Control Center, media keys).
  - Background playback and interruptions.
- UI: Chapter list, waveform if available, speed/sleep controls, queue editor.
- Handle the same audio formats as the current app (leveraging bundled ffmpeg for tricky cases or transcoding).
- **Parity goal**: Local Mac user can play exactly as they do in the current web client, with the same controls and behaviors.

### Phase 4: Embedded Server & Remote Client Support (4–6 weeks)
- Full HTTP server + the API surface needed by the separate consumption apps (match current API where practical for compatibility).
- Media streaming with range requests for seeking over the network.
- Real-time updates via WebSockets for connected players (new items, scan progress, etc.).
- User authentication and permissions for remote access.
- Progress reporting from remote consumption apps back to this server.
- Test compatibility with the existing consumption app(s).
- **Parity goal**: The separate consumption apps can connect and play from this Mac app exactly as they do from the current Node server.

### Phase 5: Users, Settings, Backups & Advanced Features (3–4 weeks)
- User accounts and permissions (match current multi-user support).
- Full settings UI (scanning options, metadata providers, server port, etc.).
- Backups of the internal database + settings.
- Statistics, listening history, etc.
- Any remaining features from the current web app (batch editing, custom metadata providers, etc.).

### Phase 6: macOS Polish, Packaging & Release (3–4 weeks)
- Deep macOS integration:
  - Sidebar + toolbar + inspector panels (native patterns).
  - Drag & drop folders and files.
  - Keyboard shortcuts, menu bar controls (play/pause, server start/stop).
  - Multiple windows (e.g., detached player).
  - Dark mode, accessibility (VoiceOver), localization.
- Performance: Efficient handling of large libraries (thousands of items) with lazy loading.
- Packaging: Self-contained .app (bundle ffmpeg if used; embed server logic).
- First-run experience: Welcome screen, add first library, create admin user.
- Code signing + notarization.
- Update mechanism (Sparkle recommended for direct downloads).
- Help/documentation inside the app.

### Phase 7: Metadata & Chapter Write-Back (Embed Into Files) (2–3 weeks)
Make the edits the user makes in the app (Phase 2 metadata editing, ASIN matching, and chapter editing) **portable** by writing them back into the actual audio files — parity with Audiobookshelf's "Embed Metadata" / chapter-embed feature. Today all edits live only in the app's own store (`CastItem` persisted to UserDefaults/DB) and the on-disk files are never modified; this phase adds an explicit, opt-in write-back.

- **Sandbox / file access**: the app currently holds `com.apple.security.files.user-selected.read-only`. Embedding requires **read-write** access to library files — switch to `com.apple.security.files.user-selected.read-write` and re-create the library folder security-scoped bookmarks with write permission. Keep writes strictly within user-granted folders.
- **Tooling**: bundle the static `ffmpeg`/`ffprobe` (already present at the repo root) inside the .app. AVFoundation/`AVAssetExportSession` can't write arbitrary chapter markers or the full range of tag formats, so ffmpeg is the reliable path:
  - Tags: ID3v2 (mp3), iTunes/MP4 atoms (m4a/m4b) — title, subtitle, author/artist, narrator/composer, album/series, track/sequence, year, publisher, genre, description/comment, ASIN/ISBN.
  - Chapters: generate an ffmetadata file (`[CHAPTER]` blocks with `START`/`END`/`title`) from `CastItem.chapters` and mux it in. Cover art via attached picture stream.
  - Prefer stream copy (`-c copy`) to avoid re-encoding when only metadata/chapters change.
- **Write strategy & safety** (modifying the user's own files — must be conservative):
  - Write to a temp file, verify by re-probing, then atomically replace the original.
  - Optional `.bak` backups + a clear confirmation dialog before any write; never destroy the original on failure.
  - Dry-run/preview of what will be written.
- **UI**: an "Embed into File" action in the Get Info and Chapter editors and the book context menu, plus a batch **"Embed All Edited"** (mirrors the Auto-Match-by-ASIN pattern: observable progress + summary, guarded while running). Only books with app-side edits (or a user selection) are written.
- **Parity goal**: metadata + chapters + cover edited in Lorcaster can be embedded into the audio files so they're correct in any other player, matching the current app's embed behavior.

### Phase 8: Future / Optional
- Widgets, Shortcuts support, Focus modes integration.
- Optional lightweight web interface (only if strong demand — try to avoid).
- iOS companion (if you later decide to expand the consumption side).
- App Store submission or direct distribution.

## Technical Recommendations

- **UI**: Pure SwiftUI. Use NavigationSplitView, lists with sections, inspectors, sheets, and SF Symbols. Target macOS 14+ for best modern APIs.
- **Server**: Hummingbird (lightweight recommendation) or Vapor.
- **Database**: SwiftData (preferred) or GRDB.swift.
- **Audio/Player**: AVFoundation + AVKit for the built-in player. Bundle a static `ffmpeg` binary inside the app for full format support and transcoding parity with the current implementation.
- **Scanning/Metadata**: FileManager + AVAsset for core, plus URLSession-based providers for online enrichment.
- **Networking (for remote clients)**: The embedded server handles it. Keep the public API as close as practical to the current one for consumption app compatibility.
- **Background operation**: Use a status item. The server runs even when the main window is closed.
- **Architecture**: Modular (LorcasterCore / LorcasterServer / LorcasterPlayer / LorcasterUI). Use Swift Concurrency heavily. Consider The Composable Architecture (TCA) for the more complex player + queue state if MVVM feels insufficient.

**Leverage Existing Assets**:
- The current OpenAPI spec (`docs/openapi.json`) is extremely useful for defining the server API that remote clients will use.
- The web client (pages, components, strings, player logic) is the best reference for exact feature parity and UX flows (don't copy pixel-perfect — make it native).
- Your existing local test libraries and `dev.js` setup can be used for validation during development.

## Risks, Challenges & Mitigations

- **Large scope** (full server port + rich player with parity + management UI in one app).  
  **Mitigation**: Strict prioritization. Get a working local library + built-in player first (Phases 1–3), then add the server layer for remote clients (Phase 4). Use the current web + Node version as a living reference for feature parity.
- **FFmpeg bundling & audio complexity** (to match current transcoding and format support).  
  **Mitigation**: Bundling a static binary is standard and reliable on macOS. Start with local playback using AVFoundation; add full transcoding support as needed.
- **API compatibility** with existing consumption apps.  
  **Mitigation**: Match the current public API surface as closely as possible in the early server phases. Since this is a hard fork, we can evolve or clearly document differences later.
- **Performance with large libraries**.  
  **Mitigation**: Design for pagination, lazy loading, and efficient SwiftUI lists from the beginning.
- **Maintaining parity while diverging**.  
  **Mitigation**: Treat the current web client as the spec for features. Replicate behaviors in native code rather than trying to share logic.
- **Sandboxing & file access**.  
  **Mitigation**: Use security-scoped bookmarks + clear UI for granting access to library folders. Users with large local libraries may need "Full Disk Access" in System Settings.
- **Console noise from AVFoundation / CoreMedia / libsqlite3 (only during playback)**.  
  **Mitigation**: Harmless but noisy Error logs appear when AVPlayer starts real decoding of sandboxed local files:
  - `FigAirPlay_Route` / `kFigPlayerError_ParamErr` (NULL airplayRoute) — mitigated by `allowsExternalPlayback = false`.
  - `libsqlite3` "logging-persist" + `open(/private/var/db/DetachedSignatures)` — internal to CoreMedia's persistent signature / logging VFS when the full playback pipeline initializes. Only on `play()`, not metadata scan. Documented in code; filter in Console ("libsqlite3", "DetachedSignatures", "logging-persist"). Cannot be eliminated from userland without private APIs. Expected in sandboxed + LSUIElement media apps; quiets somewhat after proper signing/notarization.
- **Time investment**.  
  **Mitigation**: This is a substantial but very achievable project. Expect 8–14 months part-time for a solid, parity-complete release (depending on experience level). The hard-fork decision removes a lot of ongoing maintenance burden.

## Milestones (Rough)

- **M0**: New Xcode project + menu bar app + stub server + basic player skeleton running.
- **M1**: Local library scanning + basic SwiftUI browser working.
- **M2**: Full built-in player with chapter/speed/sleep/queue support (local parity).
- **M3**: Embedded server + remote client can connect, browse, and play (server parity).
- **M4**: All current features ported + polished macOS experience.
- **M5**: Self-contained, signed .app ready for beta testing and release.

## Current Progress (as of June 2026)

- **Phase 0 complete and working** in a traditional .xcodeproj (`LorcasterMac/Lorcaster/Lorcaster.xcodeproj`).
- **Phase 1 (Library + real playback) in progress / core spike complete**:
  - Full library management in `LibraryTab` (and Dashboard list): Add Folder via `NSOpenPanel`, security-scoped app-scope bookmarks persisted in UserDefaults, folder chips with per-folder remove, Rescan All, Clear All, search filter, sort (title/dur/source), list vs grid view toggle, live scanning progress, error display, ContentUnavailable states.
  - `LorcasterCore`:
    - `CastItem` + `Library` models (Codable robust to evolution, Sendable, relativePath + coverRelativePath + author for parity).
    - `LibraryScanner` actor: recursive `FileManager.enumerator`, `AVURLAsset.load(.duration)` + `.commonMetadata` (title/artist fallbacks for ID3/iTunes), cover sibling detection (cover.jpg/folder.png etc heuristics), `relativePath` computation, yields via `AsyncStream<CastItem>` for **live incremental** UI population during long scans.
    - `CoreStore` (@MainActor @Observable): `addLibraryFolder` (bookmark + scope + live stream append + dedup + clear samples on first real add), `removeLibraryFolder`, `clearLibrary`, `rescanAll`, `playableURL(for:)` (re-resolve bookmark by source name + append relative components safely), persistence/restore of bookmarks+items, scoped resource lifetime mgmt.
  - `LorcasterPlayer`:
    - `PlayerController` now uses **real `AVPlayer` + `AVPlayerItem`** (not mock). `load(_:)` resolves via `CoreStore.shared.playableURL(for: item)` (the bookmark + relativePath bridge), creates player, installs periodic time observer (updates currentTime live), async loads more accurate asset duration, applies variable rate, seek with tolerance, natural end detection.
    - `play/pause/toggle/stop/seek/setRate` all drive the real AVPlayer (with fallback lightweight sim only for the rare unresolved-URL case so UI never completely dead).
    - Rate Stepper in PlayerTab now functional (binds through `setRate`).
    - **Chapter support complete for both types**:
      - Multi-file books (per-chapter audio files with `relativePath`): scanner populates chapters with cumulative startTimes + relativePaths; `playChapter` switches files via new `AVPlayerItem`; local per-chapter time/duration; reliable skip + auto-advance at end of chapter file.
      - Embedded chapters inside single .m4b files (no `relativePath`): `loadChapters` uses `AVAsset.loadChapterMetadataGroups`; explicit `currentChapter` + local-time translation in the time observer + time-based matching only when safe; `playChapter` does **not** replace the player item (prevents playback interruption); `updateCurrentChapter` trusts explicit choice for a short window after manual selection + uses file-absolute matchTime for embedded; enrichment task after initial load now preserves the correct starting chapter via closest `startTime` match.
    - **PlayerTab now-playing artwork polished**:
      - 3× larger (max 540 pt height, full available width).
      - Uses `.scaledToFit()` + 16 pt padding inside a sized `RoundedRectangle` container (same reliable pattern as the library grid) so the artwork fits nicely with breathing room and rounded corners.
      - Reliable loading via explicit `startAccessingSecurityScopedResource()` + `NSImage(contentsOf:)` in a `.task(id: item.id)` (more robust in the sandboxed app than `AsyncImage` for local cover files).
      - The system Now Playing artwork path (`MPMediaItemArtwork` / `MPNowPlayingInfoCenter`) remains intentionally disabled for stability — local UI covers in Library grid and PlayerTab are solid.
  - Cross-cutting: Menu bar, main window tabs, Settings (dock icon toggle that flips activation policy) all wired to the real Core/Player/Server controllers. Two source trees kept in sync (traditional `Lorcaster/` next to .xcodeproj + `App/Sources/Lorcaster/` for `swift run` SPM harness). Window minimum height raised to 700 (initial content height 720) so the large 540 pt artwork area in PlayerTab is visible by default without manual resizing.
- Scaffold/Phase 0 details still apply (MenuBarExtraAccess explicitly in target's Frameworks/Libraries/Embedded Content, LSUIElement, AppDelegate accessory policy, `.menuBarExtraAccess`, cleaned project, etc.).
- The SPM-based version (in `LorcasterMac/App/`) remains available for quick terminal testing (`swift run Lorcaster` from the App dir) and builds the same logic.
- Original Node.js backend + web client (in the parent `Lorcaster/` directory) retained as the live reference for feature parity during the port.
- All prior rebrand work carried forward.

## Immediate Recommended Next Steps

1. Open `LorcasterMac/Lorcaster/Lorcaster.xcodeproj` (or the SPM `LorcasterMac/App` package) and build/run. Use "Add Folder…" in the Library tab against one of your real audiobook directories (the same ones you used with the Node version). Verify items appear incrementally, folders can be removed individually, search/sort/grid work, and tapping an item plays the **actual audio file** with working speed stepper, seek (click in Player tab or future UI), pause/stop, and time updates in menu bar + tabs.
2. If a folder added via the app doesn't play (rare), check Console for "Could not resolve playable URL", verify the folder is still at the same path, and try Rescan or re-adding. (Security scope + bookmarks survive app restarts.)
3. Decide on the embedded server framework (Hummingbird recommended for lightness; Vapor as alternative) and media handling strategy (bundle the existing `ffmpeg`/`ffprobe` from repo root, or a static build, for full current transcoding parity in Phase 4) before heavy server work.
4. Keep the Node + web client running in parallel (`npm run dev` + client) as the living spec for exact feature parity (scanning layout, metadata fields, player behaviors, API surface for the consumption apps).
5. Next concrete pieces (player side now quite solid):
   - Chapters (both multi-file and embedded .m4b markers) are now working end-to-end with stable highlighting from initial playback and reliable Prev/Next + list navigation.
   - PlayerTab artwork is 3× larger, nicely fitted (`.scaledToFit()` + breathing room), reliably loaded via explicit security-scoped `NSImage`, inside a sized rounded container.
   - Window minimum height raised so the large artwork area is visible by default.
   - System Now Playing artwork (`MPMediaItemArtwork`) remains intentionally disabled for stability.
   - Remaining player polish ideas: auto-scroll chapter list to current chapter, persist last-played chapter/position per book, richer per-chapter metadata if the file provides it.
   - Decide whether/when (if ever) to re-enable system Now Playing artwork, then start the server framework spike.

This plan now fully incorporates:
- macOS-only, self-contained packaged app (no Node/terminal for end users).
- iTunes-like experience with full built-in player (parity with current web app).
- Embedded server for the separate consumption apps.
- Traditional .xcodeproj style (with local SPM packages for Core/Server/Player and MenuBarExtraAccess explicitly linked in the target's Frameworks, Libraries, and Embedded Content).
- Hard fork / parity only with current features.
- Native SwiftUI + Swift throughout.
- Retention of the original Node/web as live reference.
- The rebrand work (Lorcaster naming, custom assets, fork positioning in README, etc.) carried forward.

The team review (Swift expert, engineer, quality expert, critic) shaped the modular structure and cautioned against over-engineering the initial scaffold; we started with a minimal but functional skeleton using proven patterns from similar apps in the workspace.

Let me know the next concrete piece you'd like to tackle (e.g., real scanning + AVPlayer spike, or server framework decision).