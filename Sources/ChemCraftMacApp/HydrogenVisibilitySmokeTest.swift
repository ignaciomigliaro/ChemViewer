import AppKit
import ChemCraftCore

@MainActor enum HydrogenVisibilitySmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
            func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }
            // Original synthetic planar water; exact Cartesian values, no chemistry calculation.
            let source = "O 0 0 0\nH 0.75 0.5 0\nH -0.75 0.5 0\n"
            workspace.loadPastedCoordinates(try PastedCoordinates.parse(source), source: source)
            workspace.activeTab = "Image"; workspace.isDraggingEnabled = false
            workspace.atomCaption = .elementNumbers
            workspace.selectedAtomIndices = [1]; workspace.showHydrogens = false
            await pause(); await pause()
            guard let view = AnimationExporter.viewport(), let window = view.window,
                  let frame = workspace.currentFrame else { throw ParseError.noGeometry }
            let atoms = frame.atoms, bonds = frame.bonds
            func captions(_ count: Int) throws {
                view.draw()
                try require(view.measurementOverlay.captions.count == count, "Visible H captions disagree with selection")
            }
            try require(view.renderingReady && !view.scene.showHydrogens && view.scene.selectedAtomIndices == [1], "Live selection/visibility not connected")
            try captions(2)
            let points = (0..<3).compactMap { view.projectedAtomPoint($0) }
            try require(points.count == 3, "Missing projection")
            func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x+b.x)/2, y: (a.y+b.y)/2) }
            try require(view.bondAt(midpoint(points[0], points[1])) != nil, "Selected H bond cannot be picked")
            try require(view.bondAt(midpoint(points[0], points[2])) == nil, "Hidden H bond remains pickable")
            let positions = atoms.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
            let exportRenderer = view.animationRenderer(frames: [frame])
            let refittedExportRenderer = exportRenderer.animationRenderer(frames: [frame])
            try require(refittedExportRenderer.scene.selectedAtomIndices.isEmpty && refittedExportRenderer.scene.isAtomVisible(1) && !refittedExportRenderer.scene.isAtomVisible(2), "GIF renderer lost selected H visibility after refitting")
            _ = try refittedExportRenderer.renderAnimationFrame(frame, positions: positions, size: 512)
            let selectedImage = try view.renderAnimationFrame(frame, positions: positions, size: 512)
            func click(_ point: CGPoint) throws {
                let location = view.convert(point, to: nil)
                guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                      let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { throw ParseError.noGeometry }
                view.mouseDown(with: down); view.mouseUp(with: up)
            }
            try click(points[2]); await pause()
            try require(workspace.selectedAtomIndices == [1], "Hidden H was picked")
            try click(points[1]); await pause()
            try require(workspace.selectedAtomIndices.isEmpty, "Visible selected H cannot be deselected")
            try captions(1)
            let hiddenImage = try view.renderAnimationFrame(frame, positions: positions, size: 512)
            try require((selectedImage.dataProvider?.data as Data?) != (hiddenImage.dataProvider?.data as Data?), "Export omitted selected H")
            workspace.selectedAtomIndices = [1, 2]; await pause(); try captions(3)
            workspace.selectedAtomIndices = [0]; await pause(); try captions(1)
            workspace.showHydrogens = true; await pause(); try captions(3)
            workspace.selectedAtomIndices = [1]; workspace.showHydrogens = false; await pause()
            try require(workspace.currentFrame?.atoms == atoms && workspace.currentFrame?.bonds == bonds, "H visibility changed geometry/connectivity")
            let args = CommandLine.arguments
            let folder = args.firstIndex(of: "--render-evidence").map { URL(fileURLWithPath: args[$0+1]) } ?? FileManager.default.temporaryDirectory
            view.capture(to: folder.appendingPathComponent("selected-hydrogen.png"))
            let bitmap = NSBitmapImageRep(cgImage: selectedImage)
            try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("selected-hydrogen-export.png"))
            await pause(); await pause()
            print("HYDROGEN_VISIBILITY_PASS: live selected H and bond/caption, hidden H/bond unpickable, mouse deselection hides H, multiple selected H, heavy-only/empty selection, show-all restoration, Metal export pixels and unchanged coordinates/connectivity.")
            fflush(stdout); exit(0)
        } catch { fputs("HYDROGEN_VISIBILITY_FAIL: \(error)\n", stderr); exit(1) }
    }
}
