import AppKit
import ChemCraftCore
import ImageIO

@MainActor
enum SmoothInteractionSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        var code: Int32 = 0
        do {
            func require(_ value: Bool, _ message: String) throws { if !value { throw NSError(domain: "SmoothInteraction", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
            func pause() async throws { try await Task.sleep(nanoseconds: 150_000_000) }
            func find(_ root: NSView) -> MolecularMTKView? { if let view = root as? MolecularMTKView { return view }; return root.subviews.lazy.compactMap(find).first }
            func currentView() throws -> MolecularMTKView { guard let view = NSApp.windows.compactMap(\.contentView).compactMap(find).first else { throw CocoaError(.coderReadCorrupt) }; return view }
            let fm = FileManager.default, args = CommandLine.arguments
            let temp = fm.temporaryDirectory.appendingPathComponent("ChemViewer-smooth-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: temp) }
            let evidence = args.firstIndex(of: "--smooth-evidence").flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil } ?? temp
            try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
            func open(_ name: String, text: String) async throws {
                let file = temp.appendingPathComponent(name); try text.write(to: file, atomically: true, encoding: .utf8)
                workspace.open(file)
                for _ in 0..<200 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 25_000_000) }
                try require(workspace.errorMessage == nil, workspace.errorMessage ?? "Load error"); try await pause()
            }
            func capture(_ view: MolecularMTKView, name: String) async throws {
                let file = evidence.appendingPathComponent(name + ".png")
                try? fm.removeItem(at: file)
                view.capture(to: file)
                for _ in 0..<100 { if fm.fileExists(atPath: file.path) { break }; try await Task.sleep(nanoseconds: 30_000_000) }
                try require(NSImage(contentsOf: file) != nil, "Annotated PNG export failed")
                if args.contains("--capture-window"), let window = view.window {
                    window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); try await pause()
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent(name + "-window.png").path]
                    try process.run(); process.waitUntilExit()
                }
            }
            try await open("dihedral.xyz", text: "4\nsynthetic measurement fixture\nC 0 0 0\nC 1.54 0 0\nC 2.31 1.3336791218 0\nC 3.08 1.3336791218 1.3336791218\n")
            let view = try currentView()
            view.window?.setContentSize(NSSize(width: 1100, height: 760)); try await pause()
            workspace.selectedAtomIndices = [0, 1]; try await pause(); view.draw()
            try require(view.measurementOverlay.annotation == nil, "Overlay default is not off")
            workspace.showMeasurementOverlay = true; try await pause(); view.draw()
            try require(abs((view.measurementOverlay.annotation?.value ?? 0) - 1.54) < 1e-5, "Distance annotation")
            try await capture(view, name: "distance")
            workspace.selectedAtomIndices = [0, 1, 2]; try await pause(); view.draw()
            try require(abs((view.measurementOverlay.annotation?.value ?? 0) - 120) < 1e-3, "Angle annotation")
            try await capture(view, name: "angle")
            workspace.selectedAtomIndices = [0, 1, 2, 3]; try await pause(); view.draw()
            try require(abs((view.measurementOverlay.annotation?.value ?? 0) - 116.565051) < 1e-3, "Signed dihedral annotation")
            try await capture(view, name: "dihedral")
            let labelGeometry = workspace.currentFrame!
            let labelCamera = view.viewingRotation
            for count in 2...4 {
                workspace.selectedAtomIndices = Array(0..<count); try await pause(); view.draw()
                let overlay = view.measurementOverlay
                guard let originalLabel = overlay.annotation else { throw CocoaError(.coderReadCorrupt) }
                let rectangle = originalLabel.labelRect(in: overlay.bounds)
                let start = CGPoint(x: rectangle.midX, y: rectangle.midY)
                let finish = CGPoint(x: start.x + 70, y: start.y + 30)
                try require(overlay.hitTest(start) === overlay, "Measurement label cannot receive a drag")
                try require(overlay.hitTest(CGPoint(x: 1, y: 1)) == nil, "Overlay blocks clicks outside the label")
                func labelEvent(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: overlay.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                }
                overlay.mouseDown(with: labelEvent(.leftMouseDown, start))
                overlay.mouseDragged(with: labelEvent(.leftMouseDragged, finish))
                overlay.mouseUp(with: labelEvent(.leftMouseUp, finish))
                view.draw(); try await pause()
                let moved = overlay.annotation!
                let movedRect = moved.labelRect(in: overlay.bounds)
                try require(abs(movedRect.midX - rectangle.midX - 70) < 0.05 && abs(movedRect.midY - rectangle.midY - 30) < 0.05, "Measurement label did not follow pointer")
                try require(moved.value == originalLabel.value && workspace.currentFrame == labelGeometry && view.viewingRotation == labelCamera, "Label dragging changed geometry, measurement or camera")
                try await capture(view, name: "moved-label-\(count)")
                let renderer = view.animationRenderer(frames: [labelGeometry]).animationRenderer(frames: [labelGeometry])
                let positions = labelGeometry.atoms.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
                try require(renderer.animationAnnotation(positions: positions, indices: Array(0..<count), size: 256)?.labelOffset == moved.labelOffset, "GIF lost normalized label placement")
                workspace.selectedAtomIndices = []; try await pause()
                workspace.selectedAtomIndices = Array(0..<count); try await pause(); view.draw()
                try require(overlay.annotation?.labelOffset == moved.labelOffset, "Reselecting atoms lost label placement")
            }
            let labelFrame2 = MoleculeFrame(id: 1, atoms: labelGeometry.atoms.enumerated().map { index, atom in
                var result = atom; if index == 3 { result.position.z += 0.3 }; return result
            })
            let labelGIF = evidence.appendingPathComponent("moved-dihedral-label.gif")
            try await AnimationExporter.export(MolecularAnimation(frames: [labelGeometry, labelFrame2], mode: nil, amplitude: 0, samples: 12, pingPong: false), from: view, style: .paton, size: 256, fps: 2, to: labelGIF, measurementIndices: [0, 1, 2, 3]) { _ in }
            try require(CGImageSourceGetCount(CGImageSourceCreateWithURL(labelGIF as CFURL, nil)!) == 2, "Moved-label GIF export failed")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "resetLabel")
            view.draw()
            try require(view.measurementOverlay.annotation?.labelOffset == .zero, "Reset label failed")
            workspace.showMeasurementOverlay = false; try await pause(); view.draw()
            try require(view.measurementOverlay.annotation == nil, "Overlay toggle did not clear")
            workspace.chooseDragScope(.atom); try await pause()
            let original = workspace.currentFrame!, revision = workspace.geometryRevision
            func event(_ view: MolecularMTKView, _ type: NSEvent.EventType, point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            let start = view.projectedAtomPoint(0)!
            view.mouseDown(with: event(view, .leftMouseDown, point: start))
            let time = CACurrentMediaTime()
            for i in 1...120 {
                view.mouseDragged(with: event(view, .leftMouseDragged, point: CGPoint(x: start.x + CGFloat(i) / 2, y: start.y + CGFloat(i) / 4)))
            }
            let elapsed = (CACurrentMediaTime() - time) * 1000
            try require(workspace.geometryRevision == revision && workspace.currentFrame == original, "Drag moves still publish document changes")
            let moved = view.projectedAtomPoint(0)!
            try require(abs(moved.x - start.x - 60) < 0.01 && abs(moved.y - start.y - 30) < 0.01, "Preview does not follow pointer")
            view.mouseUp(with: event(view, .leftMouseUp, point: CGPoint(x: start.x + 60, y: start.y + 30)))
            try require(workspace.currentFrame?.atoms != original.atoms, "Mouse-up did not commit")
            workspace.undoGeometry(); try require(workspace.currentFrame == original && !workspace.canUndoGeometry, "Drag undo count")
            try require(view.meshBuildCount == 1, "Meshes were rebuilt per frame")
            workspace.isDraggingEnabled = false
            try await open("camera.xyz", text: "4\nsynthetic camera grab fixture\nC 0 0 -1\nO 1 1 0\nN -1 -1 0\nH -1 1 0\n")
            let camera = try currentView()
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "front")
            let geometry = workspace.currentFrame!
            let a = camera.projectedAtomPoint(0)!
            camera.mouseDown(with: event(camera, .leftMouseDown, point: a))
            camera.mouseDragged(with: event(camera, .leftMouseDragged, point: CGPoint(x: a.x + 40, y: a.y)))
            camera.mouseUp(with: event(camera, .leftMouseUp, point: CGPoint(x: a.x + 40, y: a.y)))
            try require(camera.projectedAtomPoint(0)!.x > a.x, "Horizontal camera drag remains inverted")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "front")
            let b = camera.projectedAtomPoint(0)!
            camera.mouseDown(with: event(camera, .leftMouseDown, point: b))
            camera.mouseDragged(with: event(camera, .leftMouseDragged, point: CGPoint(x: b.x, y: b.y + 40)))
            camera.mouseUp(with: event(camera, .leftMouseUp, point: CGPoint(x: b.x, y: b.y + 40)))
            try require(camera.projectedAtomPoint(0)!.y > b.y, "Vertical camera drag does not follow pointer")
            try require(workspace.currentFrame == geometry, "Camera drag changed coordinates")
            // Selection must not resize/recreate the live viewport or move projected atoms.
            workspace.clearSelection(); try await pause()
            let stableView = try currentView()
            let stableBounds = stableView.bounds
            let stableRotation = stableView.viewingRotation
            let stablePoints = geometry.atoms.indices.map { stableView.convert(stableView.projectedAtomPoint($0)!, to: nil) }
            let picked = stableView.projectedAtomPoint(0)!
            stableView.mouseDown(with: event(stableView, .leftMouseDown, point: picked))
            let jitter = CGPoint(x: picked.x + 0.4, y: picked.y + 0.3)
            stableView.mouseDragged(with: event(stableView, .leftMouseDragged, point: jitter))
            stableView.mouseUp(with: event(stableView, .leftMouseUp, point: jitter))
            try await pause()
            try require(!workspace.selectedAtomIndices.isEmpty, "Actual atom click did not select")
            for indices in [[0], [0, 1], [0, 1, 2], [0, 1, 2, 3], []] {
                workspace.selectedAtomIndices = indices
                try await pause()
                let updated = try currentView()
                try require(updated === stableView, "Selection recreated the Metal viewport")
                try require(updated.viewingRotation == stableRotation, "Selection changed the camera rotation")
                try require(updated.bounds == stableBounds, "Selection resized the 3D canvas")
                for index in geometry.atoms.indices {
                    let point = updated.convert(updated.projectedAtomPoint(index)!, to: nil)
                    try require(hypot(point.x - stablePoints[index].x, point.y - stablePoints[index].y) < 0.05, "Selection shifted atoms on screen")
                }
            }
            print("Smooth interaction PASS: optional 2/3/4-atom annotations, signed dihedral, annotated PNGs, 120 local pointer moves with zero document publications in \(elapsed) ms, exact pointer tracking, one mouse-up commit/undo, one mesh build, horizontal/vertical grab rotation, stable viewport identity/size/camera/projected positions across selection and clearing, draggable 2/3/4 labels and retained PNG/GIF placement.")
            fflush(stdout)
        } catch { fputs("Smooth interaction FAIL: \(error.localizedDescription)\n", stderr); code = 1 }
        exit(code)
    }
}
