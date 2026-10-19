import AppKit
import SwiftUI

struct GeometryNavigationKeys: NSViewRepresentable {
    var enabled: Bool
    var step: (Int) -> Void
    var clear: () -> Void
    var selectAll: () -> Void
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) {
        view.enabled = enabled; view.step = step; view.clear = clear; view.selectAll = selectAll
    }
    final class KeyView: NSView {
        var enabled = true
        var step: (Int) -> Void = { _ in }
        var clear: () -> Void = {}
        var selectAll: () -> Void = {}
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }; return self.handle(event)
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, event.window === window, window?.attachedSheet == nil,
                  !(window?.firstResponder is NSTextView) else { return event }
            if event.keyCode == 0 && event.modifierFlags.contains(.command) { selectAll(); return nil }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 123, 126: step(-1); return nil
            case 124, 125: step(1); return nil
            case 53: clear(); return nil
            default: return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
