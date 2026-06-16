import SwiftUI
import LorcasterCore

struct SettingsView: View {
    @AppStorage("showDockIcon") private var showDockIcon = false
    @Bindable var coreStore: CoreStore
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }

            Section("Library") {
                HStack {
                    Button {
                        if let url = chooseLibraryFolder() {
                            Task { await coreStore.addLibraryFolder(url) }
                        }
                    } label: {
                        Label("Add Folder…", systemImage: "folder.badge.plus")
                    }
                    .disabled(coreStore.isScanning)

                    Button {
                        Task { await coreStore.rescanAll() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(coreStore.libraryRootNames.isEmpty || coreStore.isScanning)

                    if coreStore.isScanning {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear Library…", systemImage: "trash")
                    }
                    .disabled(coreStore.items.isEmpty || coreStore.isScanning)
                }

                Text("\(coreStore.libraryCount) folder\(coreStore.libraryCount == 1 ? "" : "s") • \(coreStore.items.count) book\(coreStore.items.count == 1 ? "" : "s"). Remove individual folders from the chips in the Library tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Artwork") {
                Toggle("Prefer Local Artwork", isOn: $coreStore.preferLocalArtwork)
                Text("When on, a cover image found in the book's folder is used. When off, artwork from online metadata lookups is preferred. Either source is used as a fallback when the other is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Metadata") {
                HStack {
                    Button {
                        Task { await coreStore.autoMatchAllByASIN() }
                    } label: {
                        Label("Auto-Match All by ASIN", systemImage: "wand.and.stars")
                    }
                    .disabled(coreStore.isAutoMatching || coreStore.asinMatchableCount == 0)

                    if coreStore.isAutoMatching {
                        ProgressView().controlSize(.small)
                        Text("\(coreStore.autoMatchDone)/\(coreStore.autoMatchTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if coreStore.isAutoMatching {
                    Text("Looking up metadata for \(coreStore.autoMatchTotal) book\(coreStore.autoMatchTotal == 1 ? "" : "s")…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let summary = coreStore.autoMatchSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Fills in series, narrator, year, cover and more for every book that has an ASIN (\(coreStore.asinMatchableCount) found). ASINs are detected automatically when scanning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .alert("Clear entire library?", isPresented: $showClearConfirm) {
            Button("Clear Library", role: .destructive) {
                coreStore.clearLibrary()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes all \(coreStore.items.count) book\(coreStore.items.count == 1 ? "" : "s") and every library folder from Lorcaster. Your audio files on disk are not deleted. This can’t be undone.")
        }
        .frame(width: 460, height: 540)
        .padding()
    }
}
