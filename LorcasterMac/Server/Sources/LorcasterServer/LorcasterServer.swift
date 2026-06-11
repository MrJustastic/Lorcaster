import Foundation
import LorcasterCore
import Observation

@MainActor
@Observable
public final class ServerController {
    public static let shared = ServerController()
    
    public private(set) var isRunning: Bool = false
    public private(set) var connectedClients: Int = 0
    public private(set) var port: Int = 3333
    
    /// Computed status string for UI (Dashboard/Server tabs). Kept in sync with isRunning for Phase 1 mocks.
    public var status: String {
        isRunning ? "Running (mock)" : "Stopped"
    }
    
    private init() {}
    
    public func start() async {
        guard !isRunning else { return }
        // TODO: Real embedded HTTP server (Hummingbird/Vapor) in later phase
        // For now, mock the server running and serving the Core library
        isRunning = true
        connectedClients = 1
        print("[LorcasterServer] Started on port \(port) (mock)")
    }
    
    public func stop() {
        isRunning = false
        connectedClients = 0
        print("[LorcasterServer] Stopped (mock)")
    }
    
    public func toggle() async {
        if isRunning {
            stop()
        } else {
            await start()
        }
    }
}
