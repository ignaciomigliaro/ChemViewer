import AppKit
import ChemCraftCore
import ImageIO

@MainActor
enum DrawingAndLabelsSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func views() -> [NSView] { NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants) }
        func viewport() throws -> MolecularMTKView {
            guard let view = views().compactMap({ $0 as? MolecularMTKView }).first else { throw ParseError.noGeometry }; return view
        }
        func event(_ view: NSView, _ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        func gesture(_ canvas: MolecularDrawingCanvas, _ from: CGPoint, _ to: CGPoint? = nil) {
            canvas.mouseDown(with: event(canvas, .leftMouseDown, from))
            if let to { canvas.mouseDragged(with: event(canvas, .leftMouseDragged, to)) }
            canvas.mouseUp(with: event(canvas, .leftMouseUp, to ?? from))
        }
        func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }
        func waitForDrawing(_ drawing: MoleculeDrawingStore) async throws {
            for _ in 0..<500 { if !drawing.busy { return }; try await Task.sleep(nanoseconds: 100_000_000) }
            throw ParseError.malformed("Drawing runtime timed out")
        }
        do {
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-drawing-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            workspace.newMolecule()
            let atoms = [Atom(id: 0, element: "C", position: Vector3(-2, 0, 0)), Atom(id: 1, element: "C", position: .zero), Atom(id: 2, element: "O", position: Vector3(2, 1, 0)), Atom(id: 3, element: "N", position: Vector3(2, 1, 2))]
            workspace.applyBuildingProject(try BuildingProject(atoms: atoms))
            var nextFrame = MoleculeFrame(id: 1, atoms: atoms, comment: "Independent compatible trajectory frame")
            nextFrame.atoms[0].position.x = -2.3
            workspace.document?.frames.append(nextFrame); await pause()
            for indices in [[0, 1], [1, 2], [0, 1, 2], [0, 1, 2, 3]] {
                workspace.selectedAtomIndices = indices; workspace.setSelectionMeasurementVisible(true); workspace.clearSelection()
            }
            workspace.frameIndex = 1; await pause()
            let trajectoryView = try viewport(); trajectoryView.draw()
            try require(trajectoryView.measurementOverlay.annotations.count == 4, "Pinned labels disappeared when stepping a compatible trajectory")
            try require(abs(trajectoryView.measurementOverlay.annotations.first(where: { $0.atomIndices == [0, 1] })!.value - 2.3) < 1e-5, "Trajectory labels did not use the current frame coordinates")
            workspace.frameIndex = 0; await pause()
            let view = try viewport(); await pause(); view.draw()
            try require(workspace.pinnedMeasurementSelections.count == 4 && view.measurementOverlay.annotations.count == 4, "Persistent labels disappeared on deselection or replaced one another")
            var changed = atoms; changed[0].position.x = -3
            workspace.replaceCurrentAtoms(changed); await pause(); view.draw()
            try require(abs(view.measurementOverlay.annotations.first(where: { $0.atomIndices == [0, 1] })!.value - 3) < 1e-5, "Pinned label did not recompute after editing geometry")
            workspace.undoGeometry(); await pause(); view.draw()
            workspace.applyBuildingProject(try BuildingProject(atoms: atoms + [Atom(id: 4, element: "H", position: Vector3(5, 0, 0))]))
            try require(workspace.pinnedMeasurementSelections.count == 4, "Appending an unrelated atom hid existing labels")
            workspace.undoGeometry(); await pause(); view.draw()
            try require(workspace.pinnedMeasurementSelections.count == 4, "Geometry undo lost pinned labels")
            let rectangles = view.measurementOverlay.annotations.map { $0.labelRect(in: view.measurementOverlay.bounds) }
            for i in rectangles.indices { for j in rectangles.indices where j > i { try require(!rectangles[i].intersects(rectangles[j]), "Default labels overlap and hide one another") } }
            let originalCamera = view.viewingRotation
            let overlay = view.measurementOverlay
            let first = overlay.annotations.first { $0.atomIndices == [0, 1] }!
            let rect = first.labelRect(in: overlay.bounds), start = CGPoint(x: rect.midX, y: rect.midY), end = CGPoint(x: rect.midX - 45, y: rect.midY + 45)
            overlay.mouseDown(with: event(overlay, .leftMouseDown, start)); overlay.mouseDragged(with: event(overlay, .leftMouseDragged, end)); overlay.mouseUp(with: event(overlay, .leftMouseUp, end)); view.draw()
            try require(overlay.annotations.first(where: { $0.atomIndices == [0, 1] })!.labelOffset != .zero, "Individual persistent label did not move")
            try require(overlay.annotations.first(where: { $0.atomIndices == [1, 2] })!.labelOffset == .zero, "Dragging one label moved another")
            try require(view.viewingRotation == originalCamera, "Dragging a pinned label changed the camera")
            view.capture(to: evidence.appendingPathComponent("multiple-measurements.png"))
            let frame = workspace.currentFrame!
            let animation = MolecularAnimation(frames: [frame, frame], mode: nil, amplitude: 0, samples: 2, pingPong: false)
            let gif = evidence.appendingPathComponent("multiple-measurements.gif")
            try await AnimationExporter.export(animation, from: view, style: .paton, size: 256, fps: 4, to: gif, measurementSelections: workspace.pinnedMeasurementSelections) { _ in }
            let source = CGImageSourceCreateWithURL(gif as CFURL, nil)
            try require(source != nil && CGImageSourceGetCount(source!) == 2, "Multi-label GIF did not render")
            workspace.selectedAtomIndices = [1, 0]
            try require(workspace.isSelectionMeasurementVisible, "Reversed atom selection failed to identify the existing label")
            workspace.setSelectionMeasurementVisible(false); workspace.clearSelection(); await pause(); view.draw()
            workspace.frameIndex = 1
            try require(workspace.pinnedMeasurementSelections.count == 3, "Turning off a label did not update compatible trajectory frames")
            workspace.frameIndex = 0; await pause(); view.draw()
            try require(overlay.annotations.count == 3, "Turning off one label removed other labels")
            workspace.activeTab = "Abstract"; await pause(); workspace.activeTab = "Image"; await pause()
            let restoredView = try viewport(); restoredView.draw()
            try require(restoredView.measurementOverlay.annotations.count == 3, "Pinned labels did not survive switching tabs")
            print("PERSISTENT_LABELS_PASS: four simultaneous labels, deselection, independent dragging/removal, reversed selection, PNG/GIF and tab restoration"); fflush(stdout)

            let drawing = workspace.drawing; drawing.autoPreview = false
            workspace.activeTab = "Draw"; await pause()
            guard let canvas = views().compactMap({ $0 as? MolecularDrawingCanvas }).first else { throw ParseError.malformed("Draw tab has no native canvas") }
            try require(canvas.bounds.width >= 350 && canvas.bounds.height >= 250, "Draw workspace is too small")
            drawing.commit(MolecularSketch()); drawing.tool = .bond; drawing.element = "C"; drawing.order = 1; drawing.stereo = "none"
            let a = canvas.screen(CGPoint(x: -80, y: 0)), b = canvas.screen(CGPoint(x: -32, y: 0)), c = canvas.screen(CGPoint(x: -8, y: 42))
            gesture(canvas, a); gesture(canvas, a, b); drawing.element = "O"; gesture(canvas, b, c)
            try require(drawing.graph.atoms.map(\.element) == ["C", "C", "O"] && drawing.graph.bonds.count == 2, "Actual canvas gestures did not create ethanol")
            let ethanol = drawing.graph
            drawing.undo(); try require(drawing.graph.atoms.count == 2, "Drawing undo failed")
            drawing.redo(); try require(drawing.graph == ethanol, "Drawing redo failed")
            drawing.tool = .move; let oxygen = canvas.point(drawing.graph.atoms[2]); gesture(canvas, oxygen, CGPoint(x: oxygen.x + 20, y: oxygen.y + 15))
            try require(drawing.graph != ethanol, "Move tool did not move a drawn atom")
            drawing.undo(); try require(drawing.graph == ethanol, "Moving a drawn atom was not one undoable edit")
            drawing.tool = .erase; gesture(canvas, canvas.point(drawing.graph.atoms[2])); try require(drawing.graph.atoms.count == 2 && drawing.graph.bonds.count == 1, "Erase left dangling bonds")
            drawing.undo()
            drawing.tool = .positive; gesture(canvas, canvas.point(drawing.graph.atoms[2])); try require(drawing.graph.atoms[2].charge == 1, "Formal charge tool failed"); drawing.undo()
            let untouchedViewer = workspace.currentFrame!
            drawing.generate3D(); try await waitForDrawing(drawing); await pause()
            try require(drawing.previewIsCurrent && drawing.preview?.formula == "C2H6O" && drawing.preview?.frame?.atoms.count == 9, "Actual drawing-to-3D failed: " + drawing.status)
            try require(workspace.currentFrame == untouchedViewer, "Preview generation replaced the viewer structure")
            let previewView = try viewport(); try require(previewView.renderingReady && previewView.completedFrameCount > 0, "Actual 3D preview did not render")
            if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
                canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: evidence.appendingPathComponent("ethanol-canvas.png")) }
            }
            workspace.activeTab = "Image"; await pause(); workspace.activeTab = "Draw"; await pause()
            try require(drawing.graph == ethanol && drawing.previewIsCurrent, "Drawing/preview did not survive tab switching")
            drawing.autoPreview = true
            var amine = ethanol; amine.atoms[2].element = "N"; drawing.commit(amine)
            try await Task.sleep(nanoseconds: 900_000_000); try await waitForDrawing(drawing)
            try require(drawing.previewIsCurrent && drawing.preview?.formula == "C2H7N", "Auto 3D preview applied a stale drawing")
            drawing.autoPreview = false
            drawing.generate3D(); drawing.cancel(); await pause()
            try require(!drawing.busy, "Immediate generation cancellation failed")
            drawing.use3D(in: workspace, multiplicity: 1)
            try require(workspace.activeTab == "Image" && workspace.currentFrame?.atoms.count == 10, "Use 3D in Viewer did not transfer the full hydrogenated structure")
            workspace.undoGeometry(); try require(workspace.currentFrame == untouchedViewer, "Accepting drawing was not undoable")
            workspace.activeTab = "Draw"; await pause()
            drawing.smilesInput = "N[C@@H](C)C(=O)O"; drawing.importSMILES(); try await waitForDrawing(drawing)
            drawing.generate3D(); try await waitForDrawing(drawing)
            try require(drawing.previewIsCurrent && drawing.preview!.smiles.contains("@"), "SMILES-to-drawing-to-3D lost chirality")
            workspace.presentAtomPicker(); try await Task.sleep(nanoseconds: 500_000_000)
            guard let iron = views().compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "periodic-element-Fe" }) else { throw ParseError.malformed("Draw periodic-table picker missing") }
            iron.performClick(nil); await pause()
            try require(drawing.element == "Fe" && workspace.activeTab == "Draw" && workspace.pendingElement == nil, "Draw element picker activated the separate viewer placement tool")
            drawing.commit(MolecularSketch()); drawing.tool = .ring; drawing.ringSize = 6; drawing.aromatic = true
            guard let ringCanvas = views().compactMap({ $0 as? MolecularDrawingCanvas }).first else { throw ParseError.noGeometry }
            gesture(ringCanvas, CGPoint(x: ringCanvas.bounds.midX, y: ringCanvas.bounds.midY))
            drawing.generate3D(); try await waitForDrawing(drawing)
            try require(drawing.graph.atoms.count == 6 && drawing.preview?.formula == "C6H6", "Native benzene ring-to-3D failed: " + drawing.status)
            print("DRAWING_LABELS_PASS: native 2D bond drawing, move/erase/charge, undo/redo, local 3D/UFF, real Metal preview, auto updates, cancellation, tab preservation, undoable viewer transfer, chiral SMILES import, periodic picker and benzene ring generation")
            fflush(stdout); exit(0)
        } catch { workspace.drawing.cancel(); fputs("DRAWING_LABELS_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); exit(1) }
    }
}
