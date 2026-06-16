import Foundation
import LorcasterCore
import Observation

@MainActor
@Observable
public final class ServerController {
    public static let shared = ServerController()

    public private(set) var isRunning: Bool = false
    public private(set) var connectedClients: Int = 0
    public var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Self.portKey) }
    }
    public private(set) var lastError: String?

    private static let portKey = "LorcasterServerPort"

    /// Computed status string for the Dashboard / Server tabs.
    public var status: String {
        if isRunning { return "Running on port \(port)" }
        if lastError != nil { return "Error" }
        return "Stopped"
    }

    /// The host address other devices on the LAN can use (Bonjour `.local` name).
    public var hostName: String {
        ProcessInfo.processInfo.hostName
    }

    /// Convenience base URL for display (e.g. http://My-Mac.local:3333).
    public var connectURL: String {
        "http://\(hostName):\(port)"
    }

    /// Supervises the running Hummingbird app; cancelling it triggers graceful shutdown.
    private var serverTask: Task<Void, Never>?
    /// Bonjour advertisement so LAN clients can discover this server.
    private var netService: NetService?

    private init() {
        let saved = UserDefaults.standard.integer(forKey: Self.portKey)
        port = saved > 0 ? saved : 3333
    }

    public func start() async {
        guard !isRunning else { return }
        lastError = nil
        isRunning = true
        let port = self.port
        let server = LorcasterHTTPServer()

        serverTask = Task.detached {
            do {
                try await server.run(port: port)
                await ServerController.shared.handleServerExited(error: nil)
            } catch {
                await ServerController.shared.handleServerExited(error: error)
            }
        }
        publishBonjour(port: port)
        print("[LorcasterServer] Starting on port \(port)")
    }

    public func stop() {
        serverTask?.cancel()
        serverTask = nil
        netService?.stop()
        netService = nil
        isRunning = false
        connectedClients = 0
        print("[LorcasterServer] Stopped")
    }

    /// Advertises the server over Bonjour/mDNS as `_lorcaster._tcp` on the LAN.
    private func publishBonjour(port: Int) {
        netService?.stop()
        let service = NetService(domain: "local.", type: "_lorcaster._tcp.", name: "", port: Int32(port))
        service.publish()
        netService = service
    }

    public func toggle() async {
        if isRunning {
            stop()
        } else {
            await start()
        }
    }

    /// Called when the server task exits on its own (e.g. a bind error). Cancellation is expected
    /// (from stop()) and not surfaced as an error.
    private func handleServerExited(error: Error?) {
        serverTask = nil
        netService?.stop()
        netService = nil
        isRunning = false
        connectedClients = 0
        if let error, !(error is CancellationError) {
            lastError = error.localizedDescription
            print("[LorcasterServer] Exited with error: \(error.localizedDescription)")
        }
    }
}
