import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewport: MolecularMTKView?
    @State private var width = "2400"
    @State private var height = "1800"
    @State private var dpi = "300"
    @State private var failure: String?

    private var settings: (width: Int, height: Int, dpi: Int)? {
        guard let width = Int(width), (1...4096).contains(width),
              let height = Int(height), (1...4096).contains(height),
              let dpi = Int(dpi), (1...1200).contains(dpi) else { return nil }
        return (width, height, dpi)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export PNG image").font(.title2)
            Form {
                TextField("Width (px)", text: $width)
                TextField("Height (px)", text: $height)
                TextField("Print DPI", text: $dpi)
            }
            if let settings {
                Text("Print size at \(settings.dpi) DPI: \(Double(settings.width) / Double(settings.dpi), specifier: "%.2f") × \(Double(settings.height) / Double(settings.dpi), specifier: "%.2f") in")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Enter whole numbers from 1 to 4096 pixels and 1 to 1200 DPI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save PNG…", action: save).keyboardShortcut(.defaultAction)
                    .disabled(settings == nil || viewport == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            viewport = AnimationExporter.viewport()
            guard let size = viewport?.bounds.size, size.width > 0, size.height > 0 else { return }
            let scale = 2400 / max(size.width, size.height)
            width = String(max(1, Int((size.width * scale).rounded())))
            height = String(max(1, Int((size.height * scale).rounded())))
        }
    }

    private func save() {
        guard let viewport, let settings else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "molecule.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewport.exportPNG(to: url, width: settings.width, height: settings.height, dpi: settings.dpi)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
