# Lorcaster → Native macOS SwiftUI App Conversion Plan

**Status**: Phase 0 complete (traditional .xcodeproj + menu bar + modular SPM). Phase 1 (Library Management & Scanning + real local playback) actively implemented: real NSOpenPanel + security-scoped bookmarks + recursive AVAsset scanner with live AsyncStream updates + full add/remove/rescan/clear + filters/grid/list in LibraryTab + CoreStore + LibraryScanner actor. PlayerController now performs **real AVPlayer playback** of files resolved via CoreStore.playableURL (using bookmark + relativePath). Rate control, seek, time observer, and natural end all wired. (June 2026)  
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

### Phase 2: Metadata, Providers & Editing (3–4 weeks)
- Implement metadata providers (Audible, iTunes, MusicBrainz, etc.) using URLSession + parsing.
- Chapter support (detection, editing, display in player).
- OPML import/export for podcasts.
- Full metadata editing UI (titles, authors, covers, descriptions, etc. — matching current web capabilities).
- Author/series grouping and management.
- **Parity goal**: All current metadata features from the web UI.

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

### Phase 7: Future / Optional
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
  - Cross-cutting: Menu bar, main window tabs, Settings (dock icon toggle that flips activation policy) all wired to the real Core/Player/Server controllers. Two source trees kept in sync (traditional `Lorcaster/` next to .xcodeproj + `App/Sources/Lorcaster/` for `swift run` SPM harness).
- Scaffold/Phase 0 details still apply (MenuBarExtraAccess explicitly in target's Frameworks/Libraries/Embedded Content, LSUIElement, AppDelegate accessory policy, `.menuBarExtraAccess`, cleaned project, etc.).
- The SPM-based version (in `LorcasterMac/App/`) remains available for quick terminal testing (`swift run Lorcaster` from the App dir) and builds the same logic.
- Original Node.js backend + web client (in the parent `Lorcaster/` directory) retained as the live reference for feature parity during the port.
- All prior rebrand work carried forward.

## Immediate Recommended Next Steps

1. Open `LorcasterMac/Lorcaster/Lorcaster.xcodeproj` (or the SPM `LorcasterMac/App` package) and build/run. Use "Add Folder…" in the Library tab against one of your real audiobook directories (the same ones you used with the Node version). Verify items appear incrementally, folders can be removed individually, search/sort/grid work, and tapping an item plays the **actual audio file** with working speed stepper, seek (click in Player tab or future UI), pause/stop, and time updates in menu bar + tabs.
2. If a folder added via the app doesn't play (rare), check Console for "Could not resolve playable URL", verify the folder is still at the same path, and try Rescan or re-adding. (Security scope + bookmarks survive app restarts.)
3. Decide on the embedded server framework (Hummingbird recommended for lightness; Vapor as alternative) and media handling strategy (bundle the existing `ffmpeg`/`ffprobe` from repo root, or a static build, for full current transcoding parity in Phase 4) before heavy server work.
4. Keep the Node + web client running in parallel (`npm run dev` + client) as the living spec for exact feature parity (scanning layout, metadata fields, player behaviors, API surface for the consumption apps).
5. Next concrete pieces after validation: richer cover art (load actual images from coverRelativePath using the same bookmark root), chapter detection (from files or embedded), and/or start the server framework spike.

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