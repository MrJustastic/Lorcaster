import LorcasterCore
import LorcasterPlayer
import LorcasterServer
import SwiftUI

struct MenuContent: View {
    @Bindable var coreStore: CoreStore
    let server: ServerController
    @Bindable var player: PlayerController
    
    let openMainWindow: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = player.currentItem {
                Text(item.title)
                    .font(.headline)
                if player.isPlaying {
                    Text("Playing • \(Int(player.currentTime))s / \(Int(player.duration))s")
                        .font(.caption)
                }
                Button(player.isPlaying ? "Pause" : "Play") {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }
                Button("Stop") { player.stop() }
            } else {
                Text("No track playing")
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            Button("Open Controls…") {
                // The closure is provided by the App, which has direct access to the AppDelegate
                // instance (via @NSApplicationDelegateAdaptor). This is more reliable than casting
                // NSApp.delegate and avoids any cross-file visibility issues.
                openMainWindow()
            }
            
            Toggle("Server Running", isOn: Binding(
                get: { server.isRunning },
                set: { _ in Task { await server.toggle() } }
            ))
            
            Divider()
            
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 220)
        .onAppear {
            // Ensure server is running for menu bar presence
            if !server.isRunning {
                Task { await server.start() }
            }
        }
    }
}
