import AppKit
import AVFoundation
import Foundation
import LorcasterCore
import MediaPlayer
import Observation

/// Observable player controller with real AVFoundation playback (Phase 1+).
/// Uses CoreStore.playableURL(for:) + item.relativePath to resolve actual files from
/// security-scoped library bookmarks. Full time observer, rate control, seek, and natural end handling.
/// Matches current web player parity for basic load/play/pause/seek/speed (chapters/queue/sleep later).
@MainActor
@Observable
public final class PlayerController {
    public private(set) var isPlaying: Bool = false
    public private(set) var currentItem: CastItem?
    public private(set) var currentTime: TimeInterval = 0
    public var rate: Float = 1.0 {
        didSet {
            if let p = avPlayer, isPlaying {
                p.rate = rate
            }
        }
    }
    public private(set) var duration: TimeInterval = 0

    // Queue support (simple linear queue for now)
    public private(set) var queue: [CastItem] = []
    public private(set) var currentQueueIndex: Int?

    // Chapters for the current item (loaded on play)
    public private(set) var chapters: [Chapter] = []
    public private(set) var currentChapter: Chapter?

    // Used to suppress the "near end of chapter" auto-advance for a short time
    // right after the user (or skip button / chapter list tap) manually selects a chapter.
    // Also lets updateCurrentChapter() temporarily trust the explicitly chosen currentChapter
    // (prevents the time-based lookup from immediately flipping the highlight back to a
    // different chapter while the player seek is still propagating).
    private var lastChapterSwitchTime: Date = .distantPast

    public static let shared = PlayerController()

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?

    // For Now Playing integration
    private var nowPlayingInfo: [String: Any] = [:]

    // Current artwork object (set only once per item during #3 re-introduction).
    // Stored separately so we can re-attach it safely without full preservation logic yet.
    private var currentArtwork: MPMediaItemArtwork?

    private init() {}

    public func load(_ item: CastItem) {
        stop()
        currentItem = item
        duration = item.duration > 0 ? item.duration : 0
        currentTime = 0
        currentArtwork = nil   // reset for new item (#3 guarded re-introduction)
        rate = 1.0

        // Preserve chapters from the model (multi-file books have per-file relativePaths + cumulative startTimes).
        // We will only enrich with embedded metadata for single-chapter items.
        chapters = item.chapters
        currentChapter = nil
        updateCurrentChapter()  // pick a sensible initial currentChapter from the model's list.
                                // For embedded books this may be a placeholder; the enrichment task below
                                // will replace the list and re-establish the correct highlighted chapter.


        // Simple queue management: if this item is not already the "current" in queue,
        // treat "load" as "play this now" (replace queue with just this item for basic use).
        // More advanced enqueue/play-next is exposed via separate methods below.
        if queue.first?.id != item.id {
            queue = [item]
            currentQueueIndex = 0
        }

        // For books with chapters (especially multi-file books where each chapter is a separate audio file),
        // use the first chapter's relativePath for the initial audio file.
        // This consolidates "chapter files" into one book entry in the library.
        let initialAudioItem: CastItem
        if let firstChapter = item.chapters.first, let chRel = firstChapter.relativePath {
            initialAudioItem = CastItem(
                title: firstChapter.title,
                duration: firstChapter.duration ?? 0,
                source: item.source,
                relativePath: chRel
            )
            currentChapter = firstChapter
        } else {
            initialAudioItem = item
        }

        // Resolve real playable file URL via CoreStore's bookmark + relativePath logic.
        guard let url = CoreStore.shared.playableURL(for: initialAudioItem) else {
            print("[LorcasterPlayer] Could not resolve playable URL for \(item.title) (source: \(item.source), rel: \(item.relativePath ?? "nil"))")
            // Keep the item loaded in UI so user sees metadata; playback will be no-op until fixed (e.g. moved folder)
            updateNowPlaying()
            return
        }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: playerItem)
        avPlayer = p

        // Disable external/AirPlay playback. This app is a local audiobook player
        // (with server for other clients). Leaving it enabled causes internal
        // FigAirPlay_Route / MediaToolbox errors like kFigPlayerError_ParamErr
        // ("NULL or invalidated airplayRoute") especially when the app is in
        // accessory/menu-bar mode, the main window is closed, or during normal
        // load/play transitions. We can re-enable later if we add explicit
        // AirPlay UI/support.
        p.allowsExternalPlayback = false

        // Note on console noise during playback only:
        // When AVPlayer begins actual decoding/playback of a local file (resolved via
        // security-scoped bookmark in a sandboxed app), the CoreMedia/MediaToolbox stack
        // initializes internal persistent logging and signature handling. This uses
        // libsqlite3 and attempts to open the system path /private/var/db/DetachedSignatures
        // (used by the OS for notarization / code signature verification).
        //
        // In a sandboxed + LSUIElement app this always fails with ENOENT, producing:
        //   "os_unix.c:51044: (2) open(/private/var/db/DetachedSignatures) - No such file or directory"
        //   (category: logging-persist)
        //
        // It only appears on real playback (not during metadata scanning or asset creation)
        // because that's when the full decoder pipeline and media services engage.
        // The error is completely harmless — no playback functionality is affected.
        // This is common noise in sandboxed AVFoundation apps on macOS and cannot be
        // suppressed from user code without private APIs. Filter in Console if desired
        // (e.g. "libsqlite3" or "DetachedSignatures"). We document it here for developers.

        // Periodic time observer for live currentTime in UI (library list, player tab, menu)
        // Also drives chapter tracking and Now Playing updates.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let playerSecs = time.seconds
                if playerSecs < 0 { return }

                // For embedded chapters in a .m4b (single file), playerSecs is absolute from start of file.
                // Our currentTime / duration are chapter-local for consistency with multi-file books.
                // Compute local time for UI, chapter matching, and per-chapter end detection.
                let localSecs: TimeInterval
                if let ch = self.currentChapter, ch.relativePath == nil {
                    localSecs = max(0, playerSecs - ch.startTime)
                } else {
                    localSecs = playerSecs
                }

                self.currentTime = localSecs
                self.updateCurrentChapter()
                self.updateNowPlayingElapsedOnly()

                // Natural end detection for the *current chapter* (local time vs chapter duration)
                let dur = self.duration > 0 ? self.duration : (playerItem.duration.seconds > 0 ? playerItem.duration.seconds : 0)
                // Suppress the auto-advance for a short window after the user manually selected
                // a chapter (via list tap or Prev/Next buttons). This was causing "click a
                // chapter and it immediately jumps to the next one".
                let recentlySwitchedChapter = Date().timeIntervalSince(lastChapterSwitchTime) < 0.8
                if dur > 0 && localSecs >= dur - 0.3 && !recentlySwitchedChapter {
                    self.advanceToNextInQueueOrStop()
                }
            }
        }

        // Load chapters asynchronously (requires the asset to be loaded)
        // Only for single-file items (or items without file-based chapter list) to enrich
        // with embedded chapter metadata (e.g. m4b). For multi-file books we keep the
        // per-file chapters list provided by the scanner (with relativePaths).
        Task { [weak self] in
            guard let self else { return }
            // Respect user-edited chapters: when the user has manually defined chapters, use the stored
            // list verbatim and skip re-deriving embedded markers from the file.
            let shouldEnrichEmbedded = !item.userEditedChapters &&
                (self.chapters.count <= 1 || self.chapters.allSatisfy { $0.relativePath == nil })
            if shouldEnrichEmbedded {
                let loadedChapters = await self.loadChapters(from: asset)
                if self.currentItem?.id == item.id {
                    // When the async enrichment task replaces the chapters array with the detailed
                    // embedded markers, pick the one whose startTime is closest to where we were
                    // (usually the first chapter on a fresh load). This makes the black "currently
                    // playing" highlight appear right away and lets the Prev/Next buttons work
                    // from the very beginning, without needing a prior tap in the list.
                    let previous = self.currentChapter
                    self.chapters = loadedChapters
                    if let prev = previous,
                       let match = self.chapters.min(by: { abs($0.startTime - prev.startTime) < abs($1.startTime - prev.startTime) }) {
                        self.currentChapter = match
                    } else {
                        self.updateCurrentChapter()
                    }
                }
            }
        }

        // Also try to get a more accurate duration from the asset if the scan had 0 or placeholder
        Task { [weak self] in
            if let dur = try? await asset.load(.duration), dur.seconds > 0, let self = self {
                if self.currentItem?.id == item.id {
                    self.duration = dur.seconds
                }
            }
            await MainActor.run { [weak self] in self?.updateNowPlaying() }
        }

        // #3 in progress / bisecting:
        // - Safe cover loading (off-main) + realizedCopy pre-render on main is ACTIVE (with log).
        // - The actual MPMediaItemArtwork creation + set to nowPlayingInfo + updateNowPlaying()
        //   from this path is COMMENTED OUT because enabling it broke playback for art books.
        //
        // Test this version: if pre-render load alone works, then the culprit is creating the
        // MPMediaItemArtwork object (or setting it / calling update from the Task).
        //
        // The commented creation below includes the TIFF roundtrip in the handler for safety.
        //
        // currentArtwork var and nils in load/stop are left in place for when we re-enable.
        //
        // Still not doing: frequent re-attachment, full preservation (start from center info).
        Task { [weak self] in
            guard let self, self.currentItem?.id == item.id else { return }

            guard let coverURL = CoreStore.shared.coverURL(for: item) else {
                return
            }

            let loadedImage: NSImage? = await Task.detached {
                NSImage(contentsOf: coverURL)
            }.value

            guard let loadedImage, loadedImage.size.width > 0, loadedImage.size.height > 0 else {
                return
            }

            // Pre-render on main (this is the key "safe" part of #3).
            let realized = await MainActor.run { self.realizedCopy(of: loadedImage) }

            print("[LorcasterPlayer] Pre-rendered cover for \(item.title)")

            // The following (creation of MPMediaItemArtwork and installation) is currently
            // commented because it broke playback for art books. We are bisecting #3.
            // TODO: try re-enabling the creation + set in small steps (e.g. create but don't set,
            // or set but only on main explicitly, different handler, etc.)
            //
            // let artwork = MPMediaItemArtwork(boundsSize: realized.size) { _ in
            //     // Extra safety: TIFF roundtrip to realize on whatever queue the handler is called.
            //     if let tiff = realized.tiffRepresentation, let fresh = NSImage(data: tiff) {
            //         return fresh
            //     }
            //     return realized
            // }
            //
            // // Set only once per item.
            // if self.currentItem?.id == item.id && self.currentArtwork == nil {
            //     self.currentArtwork = artwork
            //     self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            //     self.updateNowPlaying()   // explicit "art arrived" full publish
            //     print("[LorcasterPlayer] Attached artwork for \(item.title) (once-per-item, pre-rendered)")
            // }
        }

        if nowPlayingInfo.isEmpty {
            setupRemoteCommands()
        }
        updateNowPlaying()
        print("[LorcasterPlayer] Loaded real item: \(item.title) from \(url.lastPathComponent) (scanned dur: \(Int(duration))s)")
    }

    /// Loads chapters using AVFoundation's chapter metadata groups (works well for m4b, many mp4/m4a audiobooks).
    /// Falls back gracefully to empty array for files without chapter metadata (e.g. plain mp3s).
    private func loadChapters(from asset: AVURLAsset) async -> [Chapter] {
        do {
            guard let locales = try? await asset.load(.availableChapterLocales),
                  let locale = locales.first else {
                return []
            }

            let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
            var result: [Chapter] = []

            for group in groups {
                let titleItem = group.items.first(where: { $0.commonKey == .commonKeyTitle })
                let titleStr = if let titleItem {
                    (try? await titleItem.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter"
                } else {
                    "Chapter"
                }

                let start = group.timeRange.start.seconds
                let dur = group.timeRange.duration.seconds
                let duration = dur > 0 ? dur : nil

                result.append(Chapter(title: titleStr, startTime: max(0, start), duration: duration))
            }

            // Sort by start time just in case
            return result.sorted { $0.startTime < $1.startTime }
        } catch {
            return []
        }
    }

    private func updateCurrentChapter() {
        guard !chapters.isEmpty else {
            currentChapter = nil
            return
        }

        // Trust an explicitly chosen currentChapter for a short time after the user
        // (or skip button) selected it. This prevents the time-based lookup from
        // immediately overriding it with a stale time value while the player seek
        // is still settling. The guard for relativePath (file-based) is kept as a
        // permanent rule; the recent-switch guard covers embedded chapters.
        if let ch = currentChapter, ch.relativePath != nil || Date().timeIntervalSince(lastChapterSwitchTime) < 1.0 {
            return
        }

        // Compute the "match time" against the chapters' startTimes.
        // For embedded chapters in a single file, our exposed currentTime is chapter-local (0-based),
        // so add the chapter's startTime offset to get the file-absolute time for matching.
        var matchTime = currentTime
        if let ch = currentChapter, ch.relativePath == nil {
            matchTime = ch.startTime + currentTime
        }

        let time = matchTime
        // Time-based matching only makes sense for embedded chapters within a single audio file
        // (where startTime is relative to the file).
        if let chapter = chapters.last(where: { $0.startTime <= time }) {
            if currentChapter?.id != chapter.id {
                currentChapter = chapter
            }
        } else {
            currentChapter = chapters.first
        }
    }

    /// Advances the queue when the current item naturally ends.
    /// If there's a next item, loads and plays it automatically.
    /// For books with multiple chapter files, first try to advance to the next chapter in the current book.
    private func advanceToNextInQueueOrStop() {
        // First, try to auto-advance to next chapter within the current book (for multi-file chapter books)
        if let currentCh = currentChapter,
           let chIdx = chapters.firstIndex(where: { $0.id == currentCh.id }),
           chIdx + 1 < chapters.count {
            let nextCh = chapters[chIdx + 1]
            lastChapterSwitchTime = Date()
            playChapter(nextCh)
            // stay in "playing" state
            if !isPlaying { play() }
            return
        }

        // Otherwise, advance outer queue
        guard let idx = currentQueueIndex, idx + 1 < queue.count else {
            stop()
            return
        }
        let nextItem = queue[idx + 1]
        currentQueueIndex = idx + 1
        // load will handle the rest and start playing
        load(nextItem)
        play()
    }

    // MARK: - Queue management (polish for player)

    /// Replaces the queue with a single item and plays it immediately.
    public func playNow(_ item: CastItem) {
        queue = [item]
        currentQueueIndex = 0
        load(item)
        play()
    }

    /// Appends an item to the end of the queue (does not interrupt current playback).
    public func enqueue(_ item: CastItem) {
        queue.append(item)
        // If nothing is playing, start it
        if currentItem == nil {
            currentQueueIndex = queue.count - 1
            load(item)
            play()
        }
    }

    /// Inserts an item right after the current one (play next).
    public func playNext(_ item: CastItem) {
        if let idx = currentQueueIndex {
            queue.insert(item, at: idx + 1)
        } else {
            queue.insert(item, at: 0)
        }
        if currentItem == nil {
            currentQueueIndex = 0
            load(item)
            play()
        }
    }

    public func skipToNext() {
        guard let idx = currentQueueIndex, idx + 1 < queue.count else { return }
        let next = queue[idx + 1]
        currentQueueIndex = idx + 1
        load(next)
        play()
    }

    public func skipToPrevious() {
        guard let idx = currentQueueIndex, idx > 0 else { return }
        let prev = queue[idx - 1]
        currentQueueIndex = idx - 1
        load(prev)
        play()
    }

    /// Plays a specific chapter, switching audio file if the chapter has its own relativePath (multi-file book case).
    /// This allows consolidating many chapter audio files into one book in the library.
    public func playChapter(_ chapter: Chapter) {
        guard let item = currentItem else { return }
        currentChapter = chapter
        lastChapterSwitchTime = Date()   // used by the time-observer end-detection poll

        let chRel = chapter.relativePath ?? item.relativePath
        guard let chRel else { return }

        let chAudioItem = CastItem(
            title: chapter.title,
            duration: chapter.duration ?? 0,
            source: item.source,
            relativePath: chRel
        )

        guard let url = CoreStore.shared.playableURL(for: chAudioItem) else {
            print("[LorcasterPlayer] Could not resolve chapter audio URL for \(chapter.title)")
            return
        }

        if chapter.relativePath != nil {
            // Multi-file chapter: the chapter lives in a *different* audio file.
            // We have to create a new AVPlayerItem for the new file and replace.
            let asset = AVURLAsset(url: url)
            let newPlayerItem = AVPlayerItem(asset: asset)
            avPlayer?.replaceCurrentItem(with: newPlayerItem)
        }
        // Embedded chapters inside one .m4b (relativePath == nil on the chapter):
        // We are already on the correct single file. We must NOT replace the AVPlayerItem.
        // Unconditionally replacing the item (even for the same underlying file) was
        // the direct cause of "clicking a chapter stops playback".
        // For the embedded case we just update our per-chapter local state and seek;
        // the seek(to:) method does the offset translation using chapter.startTime.

        // Per-chapter local time + duration so the UI, chapter list highlight,
        // progress, and "end of this chapter" detection all treat the current marker
        // consistently (same model as multi-file chapters).
        duration = chapter.duration ?? 0
        currentTime = 0

        if isPlaying {
            avPlayer?.play()
            avPlayer?.rate = rate
        }

        // Seek to local 0 of *this* chapter.
        // Translation for embedded chapters lives in the fixed seek(to:) implementation.
        seek(to: 0)

        updateCurrentChapter()   // ensure the chapter list highlight follows immediately
        updateNowPlaying()
        print("[LorcasterPlayer] Switched to chapter: \(chapter.title)")
    }

    // MARK: - Chapter navigation

    public func skipToNextChapter() {
        guard let current = currentChapter,
              let currentIdx = chapters.firstIndex(where: { $0.id == current.id }),
              currentIdx + 1 < chapters.count else { return }
        lastChapterSwitchTime = Date()
        let nextChapter = chapters[currentIdx + 1]
        playChapter(nextChapter)
    }

    public func skipToPreviousChapter() {
        guard let current = currentChapter,
              let currentIdx = chapters.firstIndex(where: { $0.id == current.id }) else { return }

        lastChapterSwitchTime = Date()
        let target: Chapter
        // currentTime is always the *local* (chapter-relative) time now, thanks to the
        // observer translation for embedded chapters. So the "how far into this chapter"
        // test is simply currentTime for both file-based and embedded.
        if currentTime > 3, currentIdx > 0 {
            // If more than a few seconds into the chapter, restart the current one
            target = chapters[currentIdx]
        } else if currentIdx > 0 {
            target = chapters[currentIdx - 1]
        } else {
            target = current
        }
        playChapter(target)
    }

    // MARK: - Now Playing / Media integration (Control Center, media keys, etc.)

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()

        guard let item = currentItem else {
            center.nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.title
        if let author = item.author, !author.isEmpty {
            info[MPMediaItemPropertyArtist] = author
        }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0

        // #3 support commented while bisecting the MPMediaItemArtwork creation:
        // if let artwork = currentArtwork {
        //     info[MPMediaItemPropertyArtwork] = artwork
        // }

        nowPlayingInfo = info
        center.nowPlayingInfo = info
    }

    /// Lightweight update used by the periodic time observer.
    /// Only touches elapsed time and rate. This avoids re-publishing the full info
    /// dictionary (and any MPMediaItemArtwork it may contain) on every 0.25s tick.
    /// Full updates are still used for explicit events (load, play/pause, seek, chapter,
    /// art arrival). This is a key mitigation for the libdispatch queue asserts that
    /// occurred when artwork was present.
    private func updateNowPlayingElapsedOnly() {
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? nowPlayingInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0
        center.nowPlayingInfo = info
        nowPlayingInfo = info
    }

    /// Forces a fully decoded bitmap copy of the NSImage on the current thread (called on main).
    /// This is critical before passing to MPMediaItemArtwork to avoid lazy decoding / cross-queue
    /// surprises that contributed to the previous libdispatch asserts.
    private func realizedCopy(of image: NSImage) -> NSImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        copy.unlockFocus()
        _ = copy.tiffRepresentation
        return copy
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
                return .success
            }
            return .commandFailed
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            if !(self?.chapters.isEmpty ?? true) {
                self?.skipToNextChapter()
            } else {
                self?.skipToNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            if !(self?.chapters.isEmpty ?? true) {
                self?.skipToPreviousChapter()
            } else {
                self?.skipToPrevious()
            }
            return .success
        }
    }

    public func play() {
        guard let p = avPlayer else {
            // No real player (e.g. unresolved URL) — still flip state for UI demos
            if currentItem != nil && !isPlaying {
                isPlaying = true
                // lightweight time advance for unresolved case (rare — only when playableURL failed)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    while self.isPlaying && self.currentTime < max(self.duration, 1) {
                        try? await Task.sleep(for: .milliseconds(400))
                        if self.isPlaying { self.currentTime += 0.4 }
                    }
                    if self.currentTime >= max(self.duration, 1) { self.stop() }
                }
            }
            return
        }
        guard !isPlaying else { return }
        isPlaying = true
        p.rate = rate
        p.play()
        updateNowPlaying()
        print("[LorcasterPlayer] Play @ \(rate)x")
    }

    public func pause() {
        guard isPlaying else { return }
        isPlaying = false
        avPlayer?.pause()
        updateNowPlaying()
        print("[LorcasterPlayer] Pause")
    }

    public func toggle() {
        if isPlaying { pause() } else { play() }
    }

    public func stop() {
        isPlaying = false
        currentTime = 0
        chapters = []
        currentChapter = nil

        if let obs = timeObserver, let p = avPlayer {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil

        avPlayer?.pause()
        avPlayer = nil

        // Clear Now Playing when stopping
        nowPlayingInfo = [:]
        currentArtwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        // Keep currentItem/duration visible in UI after stop (common for "now playing" history), or clear:
        // For parity with many players, clear on explicit stop:
        currentItem = nil
        duration = 0
        rate = 1.0
        currentQueueIndex = nil
        print("[LorcasterPlayer] Stop")
    }

    public func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration > 0 ? duration : time)
        currentTime = clamped
        guard let p = avPlayer else { return }

        // For embedded chapters, the seek 'time' from UI is chapter-local.
        // Translate to the actual player time within the single file.
        var playerSeekTime = clamped
        if let ch = currentChapter, ch.relativePath == nil {
            playerSeekTime = ch.startTime + clamped
        }

        let cmTime = CMTime(seconds: playerSeekTime, preferredTimescale: 600)
        p.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
        print("[LorcasterPlayer] Seeked to \(Int(clamped))s (chapter local)")
    }

    /// Sets playback rate (0.5x – 2.0x etc). Applies immediately if playing.
    public func setRate(_ newRate: Float) {
        let clamped = min(max(0.5, newRate), 2.0)
        rate = clamped
        if isPlaying, let p = avPlayer {
            p.rate = clamped
        }
    }
}
