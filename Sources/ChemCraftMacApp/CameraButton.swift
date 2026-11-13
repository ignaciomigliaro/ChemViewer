import AppKit
import SwiftUI

/// Compact native controls with accessible axis labels and direct button acceptance.
struct CameraButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let action: String
    let help: String
    var showsTitle = false
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 9, weight: .semibold)
        button.imageScaling = .scaleProportionallyDown
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = showsTitle ? .imageAbove : .imageOnly
        button.identifier = NSUserInterfaceItemIdentifier("camera-" + action)
        button.toolTip = help
        button.setAccessibilityLabel(help)
    }
    final class Coordinator: NSObject {
        var action: String
        init(_ action: String) { self.action = action }
        @objc func click() {
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: action)
        }
    }
}
