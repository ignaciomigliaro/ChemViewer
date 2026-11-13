import AppKit
import ChemCraftCore
import simd

/// Native event and button acceptance. Only run in a UUID-isolated test bundle.
@MainActor enum CameraSmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func require(_ value: Bool, _ message: String) throws {
                if !value { throw ParseError.malformed(message) }
            }
            func close(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
                (0..<4).allSatisfy { simd_length(a[$0] - b[$0]) < 2e-5 }
            }
            func pause() async { try? await Task.sleep(nanoseconds: 150_000_000) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("camera-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let input = folder.appendingPathComponent("camera.xyz")
            let bytes = "4\noriginal asymmetric camera fixture\nC 0 0 -1\nO 1 1 0\nN -1 -1 0\nH -1 1 0\n"
            try bytes.write(to: input, atomically: true, encoding: .utf8)
            workspace.open(input)
            for _ in 0..<200 { if !workspace.isLoading { break }; await pause() }
            await pause()
            guard let view = AnimationExporter.viewport(), let window = view.window,
                  let root = window.contentView, let geometry = workspace.currentFrame else { throw ParseError.noGeometry }
            func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
            func button(_ id: String) throws {
                guard let b = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "camera-" + id }) else {
                    throw ParseError.malformed("Missing camera button: " + id)
                }
                b.performClick(nil)
            }
            func action(_ name: String) { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: name) }
            func drag(_ dx: CGFloat, _ dy: CGFloat, right: Bool = true) {
                let start = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                let end = CGPoint(x: start.x + dx, y: start.y + dy)
                func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                }
                if right {
                    view.rightMouseDown(with: event(.rightMouseDown, start))
                    view.rightMouseDragged(with: event(.rightMouseDragged, end))
                    view.rightMouseUp(with: event(.rightMouseUp, end))
                } else {
                    view.mouseDown(with: event(.leftMouseDown, start))
                    view.mouseDragged(with: event(.leftMouseDragged, end))
                    view.mouseUp(with: event(.leftMouseUp, end))
                }
            }
            try button("reset")
            let initial = view.captureViewportState(), initialRotation = view.viewingRotation
            workspace.selectedAtomIndices = [0, 1]; await pause()
            for turn in [Float(0), .pi / 2, .pi, .pi * 1.5] {
                workspace.chooseDragScope(.fragment); await pause()
            workspace.selectedAtomIndices = [0, 1]
            for (dx, dy) in [(40.0, 0.0), (-40, 0), (0, 40), (0, -40), (40, 40), (-40, 40), (40, -40), (-40, -40)] {
                    view.restoreViewportState(initial)
                    var state = initial; state.pitch = turn; view.restoreViewportState(state)
                    let before = view.viewingRotation
                    drag(dx, dy)
                    // Independent Rodrigues matrix for a view-space pointer axis.
                    let x = Float(dy), y = Float(-dx), length = hypot(x, y)
                    let u = x / length, v = y / length, angle = length * 0.01
                    let c = cos(angle), s = sin(angle), t = 1 - c
                    let delta = simd_float4x4(columns: (
                        SIMD4(c + u*u*t, u*v*t, -v*s, 0),
                        SIMD4(u*v*t, c + v*v*t, u*s, 0),
                        SIMD4(v*s, -u*s, c, 0), SIMD4(0, 0, 0, 1)))
                    try require(close(view.viewingRotation, delta * before), "Pointer axes changed across orientation/direction")
                    drag(-dx, -dy)
                    try require(close(view.viewingRotation, before), "Drag reversal failed")
                }
            }
            action("front")
            let a = view.projectedAtomPoint(0)!
            drag(40, 0)
            try require(view.projectedAtomPoint(0)!.x > a.x, "Horizontal drag inverted")
            action("front"); let b = view.projectedAtomPoint(0)!
            drag(0, 40)
            try require(view.projectedAtomPoint(0)!.y > b.y, "Vertical drag inverted")
            view.restoreViewportState(initial)
            for (dx, dy) in [(40.0, 0.0), (0, 40), (40, 40)] {
                drag(dx, dy, right: false)
                try require(close(view.viewingRotation, initialRotation) && view.captureViewportState().pan == initial.pan, "Left drag changed camera")
            }
            workspace.isDraggingEnabled = false
            for (name, axis) in [("x", SIMD3<Float>(1, 0, 0)), ("y", SIMD3<Float>(0, 1, 0)), ("z", SIMD3<Float>(0, 0, 1))] {
                view.restoreViewportState(initial)
                try button(name + "Plus")
                // 15 degree right-handed basis-vector rotation about each view axis.
                let q = simd_quatf(angle: .pi / 12, axis: axis)
                try require(close(view.viewingRotation, simd_float4x4(q) * initialRotation), name + "+ button axis/sign")
                try button(name + "Minus")
                try require(close(view.viewingRotation, initialRotation), name + "− button inverse")
            }
            try button("in"); try require(view.captureViewportState().zoom > initial.zoom, "Closer arrow did not enlarge")
            try button("out"); try require(abs(view.captureViewportState().zoom - initial.zoom) < 1e-5, "Further arrow did not restore scale")
            var displaced = view.captureViewportState(); displaced.pan = SIMD2(0.4, -0.3); displaced.zoom = 2
            view.restoreViewportState(displaced); drag(80, 40)
            try button("reset")
            let reset = view.captureViewportState()
            try require(close(view.viewingRotation, initialRotation) && reset.center == initial.center && reset.fitScale == initial.fitScale && reset.pan == .zero && reset.zoom == 1, "Reset did not restore centered initial view")
            try require(workspace.selectedAtomIndices == [0, 1] && workspace.currentFrame == geometry, "Camera edited selection/geometry")
            drag(80, 40)
            let saved = view.captureViewportState(), rotation = view.viewingRotation
            try button("reset"); view.restoreViewportState(saved)
            try require(close(view.viewingRotation, rotation), "Saved camera lost orbit")
            try require(close(view.animationRenderer(frames: [geometry]).viewingRotation, rotation), "Export lost orbit")
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--camera-evidence"), args.indices.contains(i + 1) {
                try button("reset"); view.capture(to: URL(fileURLWithPath: args[i + 1]))
                await pause()
                if args.contains("--capture-window") {
                    let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-l", String(window.windowNumber), URL(fileURLWithPath: args[i + 1]).deletingLastPathComponent().appendingPathComponent("camera-window.png").path]
                    try capture.run(); capture.waitUntilExit()
                    try require(capture.terminationStatus == 0, "Window capture failed")
                }
            }
            try require(try String(contentsOf: input) == bytes, "Source bytes changed")
            print("CAMERA_PASS: 32 directional/pole cases, inverse drags, screen tracking, left selection-only camera, six native axis buttons, closer/further, centered reset, preserved selection/coordinates/source, saved/export camera.")
            fflush(stdout); exit(0)
        } catch { fputs("CAMERA_FAIL: \(error)\n", stderr); exit(1) }
    }
}
