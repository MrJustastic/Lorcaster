# Lorcaster → SwiftUI App Conversion Plan

**Status**: Draft (as of June 2026)  
**Goal**: Convert the current web-based Lorcaster client (Nuxt/Vue 2) into a native SwiftUI macOS (and optionally iOS) application, while leveraging the existing robust Node.js backend where possible.  
**Context**: This is a personal fork of Audiobookshelf. The current stack is a Node/Express + Socket.IO backend (with SQLite) serving a feature-rich web client. The user wants to develop primarily in Xcode using SwiftUI.

## 1. Objectives & Success Criteria

- Deliver a high-quality native experience on macOS (primary target) with modern SwiftUI.
- Maintain feature parity with the web client over time (library management, playback, metadata, scanning, etc.).
- Keep the existing backend running for now (avoid a full rewrite initially).
- Enable easy local development: run backend + SwiftUI app side-by-side.
- Improve platform integration: native audio player, drag-and-drop, keyboard shortcuts, menu bar, widgets, notifications, etc.
- Support connecting to remote Lorcaster/Audiobookshelf servers (not just localhost).
- (Stretch) Share significant code with a future iOS/iPadOS version.
- (Long-term) Evaluate full native backend if desired for performance, distribution, or independence from Node.

**Success Metrics**:
- MVP: Auth + library browsing + basic playback working in < 4-6 weeks of focused work.
- Users can replace the web client for daily use on Mac.
- The web client remains available as a fallback/cross-platform option during transition.

## 2. Recommended Architecture

**High-level**:
- **Backend**: Keep the current Node.js/Express server (with FFmpeg, SQLite, scanning, etc.) as the "source of truth". It already has a solid REST API (documented in `docs/openapi.json`) and WebSocket support.
- **Client**: New native SwiftUI app (macOS app target, potentially multi-platform).
- **Communication**:
  - REST API for most operations (use `swift-openapi-generator` to create a type-safe client from the existing OpenAPI spec).
  - WebSockets (Socket.IO or raw) for real-time events (playback progress sync, library scans, notifications).
- **Data Layer**: SwiftData (or Core Data) for local caching of libraries, items, progress. Sync with server on launch/reconnect.
- **Audio**: AVFoundation + AVKit for playback. Report progress back to server to keep multi-device sync.
- **State Management**: SwiftUI + `@Observable` / `ObservableObject`. For complex flows (player queue, batch editing), consider The Composable Architecture (TCA) or a simple MVVM+.
- **UI/UX**: Replicate key screens from the Vue client (bookshelf grid, item details, player bar/modal, settings, uploads) but make them feel native. Use SF Symbols, native sheets, etc.
- **Distribution**: macOS app (App Store or direct download). The backend can remain a separate Node process (user runs via `npm run dev` or a packaged binary later).

**Alternative Paths** (for discussion):
- **Hybrid**: Embed a WKWebView for complex parts (e.g., chapter editor) while using native SwiftUI for the player and browsing. Faster initial delivery but less "pure" native.
- **Full Native Backend**: Eventually port the server to Swift (e.g., using Hummingbird or Vapor + SQLite + swift-ffmpeg). This would allow a self-contained app but is a multi-month effort. Start with client-only.
- **Thick Client**: Allow the app to manage local libraries directly (file scanning in Swift) without always needing the Node server. Hybrid mode possible.

**Project Structure Suggestion**:
```
/Lorcaster
  /server          # existing Node backend (keep mostly as-is)
  /web-client      # existing Nuxt (keep for reference + web fallback)
  /Lorcaster       # NEW Xcode project / Swift package
    /LorcasterApp  # SwiftUI macOS app target
    /LorcasterShared  # Models, API client, networking (sharable with iOS target later)
    /LorcasterPlayer # Audio engine module
  README.md
  SWIFTUI_CONVERSION_PLAN.md  # this file
```

The SwiftUI app can live in the same repo for easy monorepo development.

## 3. Phased Plan

### Phase 0: Foundation & Exploration (1-2 weeks)
- **Explore current system**:
  - Study `docs/openapi.json` and key server files (`server/controllers/`, `server/models/`).
  - Identify must-have endpoints (auth, libraries, items, sessions, metadata, etc.).
  - Map real-time events from SocketAuthority.
  - Review web client screens (pages/ and components/) as UI reference.
- **Project Setup**:
  - Create new Xcode project: macOS > App > SwiftUI + SwiftData.
  - Add Swift package dependencies: swift-openapi-generator, swift-openapi-runtime, swift-openapi-urlsession.
  - Generate API client from `docs/openapi.json` (or a local copy).
  - Set up basic networking layer with auth token handling (JWT from login).
  - Add Socket.IO client for Swift (or implement raw WebSocket + JSON).
- **Auth Flow MVP**:
  - Login screen (username/password or token).
  - Store token securely (Keychain).
  - Basic "Server could not be reached" handling + retry.
- **Deliverable**: App that can authenticate against a running local Lorcaster backend and show a simple "Connected" status.

**Tools**:
- Use the existing `dev.js` + backend for testing.
- Run backend with `npm run dev` and client app from Xcode.

### Phase 1: Core Browsing & Libraries (2-3 weeks)
- Fetch and display libraries (grid or list).
- Bookshelf view: paginated/grid of library items (books + podcasts) with covers (use AsyncImage or Nuke).
- Item detail view: metadata, chapters list, file list, description.
- Series and Author browsing (reuse patterns from item lists).
- Basic search (title/author).
- Local caching of library data with SwiftData.
- Error states, loading skeletons, pull-to-refresh.

**Key Models to Port**:
- Library, LibraryItem, Book, Podcast, Author, Series, MediaProgress, etc. (mirror OpenAPI schemas).

### Phase 2: Audio Player & Playback (2-3 weeks)
- Bottom player bar or full player window/sheet (common in music apps).
- Playback controls: play/pause, seek, skip chapters, speed, sleep timer.
- Integrate AVPlayer for streaming from backend (use the existing `/api/items/{id}/stream` or hls endpoints).
- Report progress back to server (`/api/session` or similar endpoints) so sync works with web/other clients.
- Queue management.
- Now Playing integration (macOS Control Center, lock screen on iOS later).
- Handle background playback and interruptions.

**Challenges**: Transcoding, format support (backend helps here), seeking in large files.

### Phase 3: Advanced Features & Parity (4+ weeks)
- Uploads (file picker + progress, using existing upload endpoints).
- Metadata editing (covers, tags, chapters) – port the complex modals from Vue.
- Library scanning / folder management.
- User settings, server config (if admin).
- Notifications (new episodes, scan complete) via server + local.
- Real-time updates: listen to sockets for library changes, playback from other devices.
- Playlists, collections, stats views.
- Ebook reader support (if keeping that feature – WebView or native?).
- Batch operations.

### Phase 4: macOS Polish, Distribution & Extras (3 weeks)
- Native macOS UI: sidebar navigation, toolbar, multiple windows (e.g., player detached), drag & drop for uploads.
- Keyboard shortcuts, menu bar app option (quick controls).
- Theming / dark mode (match or improve on current Tailwind theme).
- Accessibility (VoiceOver), localization (start with English).
- Performance: virtual scrolling for large libraries, image caching.
- Packaging: Build as standalone .app. Optionally bundle a way to launch the Node server (embedded Node binary is complex; document "run `npm run dev` alongside" for MVP).
- iOS target (adaptive layouts, SwiftUI previews).
- Testing: Unit tests for API client/models, UI tests for key flows.
- Onboarding: "Connect to server" flow (local + remote URLs), first-run library setup.

### Phase 5: Long-term / Optional (Future)
- **Backend Port**: Evaluate rewriting core server in Swift (file scanning with FileManager + metadata libs, FFmpeg via system or SwiftFFmpeg, SQLite via GRDB or SwiftData, auth with JWT libs).
  - Pros: Single language, better Mac integration, easier distribution (no Node dependency).
  - Cons: Huge effort (re-implement scanning logic, user management, etc.). Start only if client proves valuable.
- Offline mode enhancements (download for offline listening, local library mode).
- WatchOS / tvOS companions if desired.
- App Store submission (sandboxing, entitlements for file access, network).
- Community: Since this is a fork, decide on open-sourcing the SwiftUI client separately or merged.

## 4. Technical Stack & Tools

- **Language/UI**: Swift 6, SwiftUI (macOS 14+ / iOS 17+ recommended).
- **API Client**: swift-openapi-generator (best for staying in sync with backend OpenAPI).
- **Networking**: URLSession (or Alamofire for convenience).
- **WebSockets**: Socket.IO-Client-Swift or Starscream + custom handling.
- **Audio**: AVFoundation, AVKit.
- **Persistence**: SwiftData (modern, SwiftUI-friendly) or GRDB.swift.
- **Images**: AsyncImage + caching, or Nuke.
- **Architecture**: Start simple (MVVM with @Observable). Adopt TCA if state gets complex (player + queue + multiple views).
- **Other**:
  - Swift Concurrency (async/await, actors for player state).
  - KeychainAccess for tokens.
  - UniformTypeIdentifiers for file handling.
- **Dev Tools**: Xcode, Swift Package Manager. Run backend in parallel terminal. Use SwiftUI Previews heavily (mock API responses).
- **Testing**: XCTest + ViewInspector or similar for UI.

**Leverage Existing Assets**:
- The OpenAPI spec is gold for codegen.
- Web client components/strings as design/UX reference (don't copy pixel-perfect; make it native).
- Existing `dev.js` and local server for rapid iteration.

## 5. Risks, Challenges & Mitigations

- **Feature Surface Area**: The Vue client is very complete (modals for everything, batch editing, readers, stats). **Mitigation**: Prioritize ruthlessly (playback + browsing first). Use the web client for power-user features initially.
- **Real-time & Sync**: WebSockets + progress reporting must be solid for multi-device use. **Mitigation**: Start with polling if sockets are hard, then add sockets.
- **Media Complexity**: Streaming large files, chapters, different formats. **Mitigation**: Rely on backend for serving (it already does heavy lifting with FFmpeg).
- **Backend Dependency**: Users must run Node server. **Mitigation**: Clear docs, "one-click" local server launch helper in the app (launch `node` process), future embedded server option.
- **Performance on Large Libraries**: SwiftUI lists/grids can struggle with 10k+ items. **Mitigation**: Pagination, lazy loading, virtual views from day one.
- **Maintaining Two Frontends**: Web + native. **Mitigation**: Treat web as "reference implementation" or deprecate it over time for Mac users.
- **Distribution**: Sandboxing limits file access. Users with large local libraries may need "Full Disk Access".
- **Time Estimate**: 3-6 months part-time for a solid MVP-to-polished macOS app (depending on prior SwiftUI experience). Backend port would add 6+ months.

## 6. Milestones & Timeline (Rough)

- **M0 (Week 1)**: Project created, auth + "connected to server" working.
- **M1 (Week 3-4)**: Library list + item grid + detail view.
- **M2 (Week 6-7)**: Working audio player with progress sync.
- **M3 (Week 10+)**: Uploads, search, basic settings. Usable daily driver.
- **M4**: Polish, macOS integrations, beta testing.
- **Ongoing**: Feature parity sprints, iOS support.

Track in GitHub issues or a `Lorcaster/SwiftUI` milestone.

## 7. Immediate Next Steps (Actionable)

1. **Decide scope**: Confirm macOS-first, client-only (backend stays Node for now). Create the new Xcode project inside or alongside this repo.
2. **Set up API client**: Add swift-openapi-generator target. Generate models/endpoints from `docs/openapi.json`. Implement a `LorcasterClient` service.
3. **Auth screen**: Simple form + token storage. Test against your running local backend (`npm run dev`).
4. **Basic navigation**: Sidebar with Libraries / Books / Podcasts / Settings (inspired by current web layout but native).
5. **Spike player**: Minimal AVPlayer that can stream a known item URL from the backend.
6. **Update this plan**: As you discover API quirks or decide on architecture (e.g., adopt TCA?).
7. **Run in parallel**: Keep the web client working for reference/testing while building the native version.

**Questions to resolve soon**:
- macOS only for v1, or multi-platform from the start?
- Do we want the app to be able to *start/manage* the local backend process (e.g., embedded server toggle)?
- Any must-have macOS features (e.g., menu bar player, Shortcuts support, iCloud sync of settings)?
- Design direction: Match current look closely, or fresh modern SwiftUI design?

## 8. Resources

- Official OpenAPI: `docs/openapi.json` + `docs/` YAML files.
- Existing web client: Great for UX flows and strings (see `client/strings/en-us.json`, pages, components).
- SwiftUI + Audio examples from Apple.
- swift-openapi-generator docs.
- The original Audiobookshelf iOS app (separate repo) for inspiration on native patterns (even if not SwiftUI).

This plan is a living document. Update it as you build. The rebrand work you've done (Lorcaster naming, custom icon/banner) will carry over nicely to the native app.

If you'd like, I can:
- Help scaffold the initial Xcode project structure and API client.
- Generate starter Swift models from the OpenAPI.
- Create specific screens (e.g., LoginView, LibraryGrid) as code snippets.
- Refine this plan with more details on any phase.

Just say the word — and in the meantime, your backend should finish starting up! Check that terminal for the "Listening on port" message.