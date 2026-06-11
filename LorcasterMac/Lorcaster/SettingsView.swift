import SwiftUI

struct SettingsView: View {
    @AppStorage("showDockIcon") private var showDockIcon = false
    
    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }
            
            Section("Server") {
                Text("Port: 3333 (configurable in future)")
                Text("The embedded server allows other Lorcaster consumption apps to connect and play your library.")
                    .font(.caption)
            }
            
            Section {
                Text("Lorcaster macOS • SwiftUI native app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 400, height: 200)
        .padding()
    }
}
