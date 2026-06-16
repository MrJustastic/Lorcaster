import AppKit
import LorcasterCore
import LorcasterPlayer
import LorcasterServer
import SwiftUI

@main
struct LorcasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coreStore = CoreStore.shared
    @State private var server = ServerController.shared
    @State private var player = PlayerController.shared
    
    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                coreStore: coreStore,
                server: server,
                player: player,
                openMainWindow: {
                    appDelegate.showMainWindow(coreStore: coreStore, server: server, player: player)
                }
            )
        } label: {
            Text("LC")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView(coreStore: coreStore)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained reference to the main controls window (created on demand).
    /// We keep it alive (isReleasedWhenClosed = false) so "Open Controls" can reuse it.
    private var mainWindow: NSWindow?

    /// We must retain the NSWindowDelegate ourselves because NSWindow.delegate is weak.
    private var mainWindowDelegate: MainWindowDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Respect the user's "Show Dock Icon" preference (stored via @AppStorage in SettingsView).
        // We no longer declare a Window(id:) scene for the main controls; it is created
        // imperatively in showMainWindow(...) so we have full control over activation timing.
        // This helps avoid BaseBoard "task name port right" errors that are common when
        // a declarative Window scene + LSUIElement + accessory policy interact at launch
        // or during policy flips.
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)

        Task {
            await ServerController.shared.start()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ServerController.shared.stop()
        PlayerController.shared.stop()
    }

    /// Called from the menu bar "Open Controls…" item (and potentially other places).
    /// Ensures the app is treated as a regular app long enough for the window to appear,
    /// creates (or reuses) a standard NSWindow hosting the SwiftUI MainControlsView,
    /// and wires a delegate that returns the app to pure menu-bar accessory mode
    /// when the window is closed (unless the user has "Show Dock Icon" enabled).
    func showMainWindow(coreStore: CoreStore, server: ServerController, player: PlayerController) {
        // Reuse existing window if we have one (even if it was previously closed/hidden).
        if let win = mainWindow {
            NSApp.setActivationPolicy(.regular)
            win.makeKeyAndOrderFront(nil)

            // Delayed activate for the same reason as below (reduces BaseBoard port errors).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // Become a normal app (Dock icon, app switcher, etc.) for the duration the window is visible.
        NSApp.setActivationPolicy(.regular)

        let controlsView = MainControlsView(
            coreStore: coreStore,
            server: server,
            player: player
        )
        .frame(minWidth: 480, minHeight: 700)

        let hostingView = NSHostingView(rootView: controlsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lorcaster"
        window.contentView = hostingView
        window.minSize = NSSize(width: 480, height: 700)
        window.center()
        window.isReleasedWhenClosed = false  // Keep the NSWindow instance so we can bring it back later.

        // The delegate will drop us back to .accessory on close (respecting the user's pref).
        // NSWindow.delegate is weak, so we must keep a strong reference ourselves.
        let delegate = MainWindowDelegate()
        window.delegate = delegate
        mainWindowDelegate = delegate

        mainWindow = window
        window.makeKeyAndOrderFront(nil)

        // Activate with a tiny delay. Immediate activate while transitioning from accessory
        // mode is a common source of the BaseBoard "task name port right" errors.
        // The short delay often lets the policy change and window ordering settle first,
        // reducing (but not always eliminating) the log while still ensuring the window
        // becomes key and the app is frontmost.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Window delegate for lifecycle (policy reset on close)

/// Small delegate whose only job is to return the app to menu-bar-only accessory mode
/// when the user closes the main controls window (unless they have opted into a persistent Dock icon).
private final class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let showDock = UserDefaults.standard.bool(forKey: "showDockIcon")
        if !showDock {
            // Async to let the close complete cleanly and avoid BaseBoard races.
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
