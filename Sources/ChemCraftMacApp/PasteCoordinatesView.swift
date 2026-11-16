import AppKit
import ChemCraftCore
import SwiftUI

struct PasteCoordinatesView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(embedded ? "Paste coordinates here (⌘V)" : "Paste coordinates").font(.title2.bold())
            Text("Paste a complete XYZ (atom count, comment, coordinates), or Element X Y Z rows. Coordinates are in Å. Render opens a new document tab.")
            TextEditor(text: $text).font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.4))
                .accessibilityIdentifier("pasted-coordinates-text")
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Paste from Clipboard") {
                    if let value = NSPasteboard.general.string(forType: .string) { text = value; error = nil }
                    else { error = "The clipboard contains no text." }
                }
                Spacer()
                if !embedded { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                GeometryEditButton(title: "Render", id: "render-pasted-coordinates", keyEquivalent: "\r") {
                    do {
                        let parsed = try PastedCoordinates.parse(text)
                        workspace.isPasteCoordinatesPresented = false
                        workspace.importPastedCoordinates(parsed, source: text)
                    } catch { self.error = error.localizedDescription }
                }.frame(width: 90, height: 28)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("render-pasted-coordinates")
            }
        }.padding()
            .frame(minWidth: 650, minHeight: embedded ? 220 : 470)
    }
}
