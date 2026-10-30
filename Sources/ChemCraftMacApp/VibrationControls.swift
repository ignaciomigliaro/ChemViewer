import AppKit
import SwiftUI

struct VibrationControls: View {
    @EnvironmentObject var workspace: WorkspaceStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                VibrationButton(title: workspace.showDisplacementVectors ? "Vectors: on" : "Vectors: off", id: "vibration-vectors") {
                    workspace.showDisplacementVectors.toggle()
                }.help("Show or hide normal-mode displacement arrows")
                VibrationButton(title: workspace.isVibrating ? "Freeze" : "Resume", id: "vibration-freeze") {
                    workspace.isVibrating.toggle()
                }.help("Freeze the current phase, or resume from that same phase")
                VibrationButton(title: "Max +", id: "vibration-max-positive") { workspace.freezeVibrationAtMaximum() }
                    .help("Freeze at the positive maximum of the selected mode")
                VibrationButton(title: "Max −", id: "vibration-max-negative") { workspace.freezeVibrationAtMaximum(negative: true) }
                    .help("Freeze at the opposite maximum; normal-mode sign is arbitrary")
                VibrationButton(title: "Save displaced XYZ…", id: "vibration-save") { workspace.saveDisplacedVibrationXYZ() }
                    .disabled(workspace.isVibrating)
                Text("Display amplitude × source vectors; original geometry is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(!workspace.canDisplaceMode).padding(.horizontal, 12).padding(.vertical, 6)
        }.frame(height: 40)
    }
}

/// Native buttons provide keyboard/accessibility activation and reproducible live-GUI checks.
private struct VibrationButton: NSViewRepresentable {
    let title: String
    let id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action; button.title = title; button.isEnabled = enabled
        button.setAccessibilityLabel(title)
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func click() { action() }
    }
}
