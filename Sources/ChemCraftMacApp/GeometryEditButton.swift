import AppKit
import SwiftUI

/// Commit the edited number before applying a geometry action; native activation
/// also lets physical-Mac acceptance exercise the same controls as the user.
struct GeometryEditButton: NSViewRepresentable {
    let title: String
    let id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.click(_:)))
        button.bezelStyle = .rounded; button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(id)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action; button.title = title; button.isEnabled = enabled
        button.setAccessibilityLabel(title)
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func click(_ sender: NSButton) {
            guard sender.window?.makeFirstResponder(nil) != false else { return }
            action()
        }
    }
}
