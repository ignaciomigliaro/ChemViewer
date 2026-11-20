import AppKit
import ChemCraftCore

@MainActor enum ViewportActivationSmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw ParseError.malformed(message) }
        }
        func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }
        do {
            let source = "O 0 0 0\nH .9572 0 0\nH -.239 .9266 0\n"
            workspace.loadPastedCoordinates(try PastedCoordinates.parse(source), source: source)
            workspace.activeTab = "Image"; workspace.isVibrating = false
            workspace.selectedAtomIndices = [0, 1]
            await pause(); await pause()
            guard let view = AnimationExporter.viewport(), let window = view.window else { throw ParseError.noGeometry }
            let atoms = workspace.currentFrame!.atoms
            let camera = view.captureViewportState()
            let projection = view.projectedAtomPoint(1)
            try require(view.renderingReady && view.isPaused && view.enableSetNeedsDisplay, "Expected static on-demand renderer")
            // Let initial layout/display notifications drain. Merely returning to
            // the app must submit a fresh frame without a scene or camera edit.
            await pause(); await pause()
            for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.didDeminiaturizeNotification] {
                let before = view.completedFrameCount
                NotificationCenter.default.post(name: name, object: name == NSApplication.didBecomeActiveNotification ? NSApp : window)
                await pause(); await pause()
                try require(view.completedFrameCount > before, "No new GPU frame after \(name.rawValue)")
            }
            try require(view.projectedAtomPoint(1) == projection && view.captureViewportState().zoom == camera.zoom,
                        "Activation changed camera")
            try require(workspace.currentFrame!.atoms == atoms && workspace.selectedAtomIndices == [0, 1], "Activation changed molecule/selection")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "yPlus")
            await pause()
            try require(view.projectedAtomPoint(1) != projection, "Camera stopped responding after activation")
            var animated = view.scene
            animated.animate = true
            view.scene = animated
            await pause()
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            await pause()
            let before = view.completedFrameCount
            await pause()
            try require(!view.isPaused && !view.enableSetNeedsDisplay && view.completedFrameCount > before, "Activation stopped continuous rendering")
            animated.animate = false; view.scene = animated
            await pause()
            view.releaseDetachedResources()
            let detachedCount = view.completedFrameCount
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            await pause()
            try require(!view.renderingReady && view.completedFrameCount == detachedCount, "Activation revived a dismantled renderer")
            print("VIEWPORT_ACTIVATION_PASS: fresh completed GPU frames after app/window activation, occlusion and restore; unchanged geometry/selection/camera; responsive camera; continuous rendering retained; detached renderer stays released.")
            fflush(stdout); exit(0)
        } catch { fputs("VIEWPORT_ACTIVATION_FAIL: \(error)\n", stderr); exit(1) }
    }
}
