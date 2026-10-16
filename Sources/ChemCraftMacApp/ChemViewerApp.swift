import SwiftUI

@main
struct ChemViewerApp: App {
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspace)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { workspace.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
        }
    }
}
