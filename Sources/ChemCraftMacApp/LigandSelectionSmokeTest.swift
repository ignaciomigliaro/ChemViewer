import AppKit
import ChemCraftCore

@MainActor
enum LigandSelectionSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            // This synthetic graph tests fixed-topology ligand membership and pivots.
            // New-contact generation is exercised separately by InternalCoordinateSmokeTest.
            workspace.addBondsAfterDragging = false
            func require(_ value: Bool, _ text: String) throws {
                if !value { throw ParseError.malformed(text) }
            }
            func find(_ root: NSView) -> MolecularMTKView? {
                if let view = root as? MolecularMTKView { return view }
                return root.subviews.lazy.compactMap(find).first
            }
            // Same original graph as Tests/fixtures/integrated-building/synthetic-ligand-motif.cvproject.
            // Coordinates are test positions, not an optimized molecular structure.
            let rows: [(String, Float, Float)] = [("Fe",0,0),("N",2,0),("C",3,1),("C",2,2),("N",0,2),("H",3,2),("O",-2,0),("H",-3,0),("Ru",5,1),("Cl",7,1),("C",10,0),("H",11,0)]
            let atoms = rows.enumerated().map { Atom(id: $0.offset, element: $0.element.0, position: Vector3($0.element.1, $0.element.2, 0)) }
            let edges = [(0,1),(0,4),(1,2),(2,3),(3,4),(3,5),(0,6),(6,7),(2,8),(8,9),(10,11)]
            var project = try BuildingProject(atoms: atoms)
            project.explicitBonds = edges.enumerated().map { Bond(id: $0.offset, first: $0.element.0, second: $0.element.1) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-ligand-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let source = folder.appendingPathComponent("synthetic-ligand-motif.cvproject")
            let data = try JSONEncoder().encode(project); try data.write(to: source)
            workspace.open(source)
            for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
            workspace.activeTab = "Image"
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let view = NSApp.windows.compactMap({ $0.contentView.flatMap(find) }).first,
                  let window = view.window, let original = workspace.currentFrame else { throw ParseError.noGeometry }
            func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            func click(_ index: Int) async throws {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let point = view.projectedAtomPoint(index) else { throw ParseError.noGeometry }
                view.mouseDown(with: event(.leftMouseDown, point)); view.mouseUp(with: event(.leftMouseUp, point))
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            workspace.armAtom("Ru"); try await click(0)
            try require(workspace.currentFrame!.atoms.count == atoms.count && workspace.currentFrame!.atoms[0].element == "Ru", "Metal substitution inserted an extra atom")
            try require(workspace.currentFrame!.atoms[0].position == original.atoms[0].position && workspace.currentFrame!.bonds == original.bonds, "Metal substitution changed coordinates or connectivity")
            workspace.clearSelection(); workspace.undoGeometry()
            try require(workspace.currentFrame == original, "Metal substitution undo failed")
            workspace.selectedAtomIndices = [0, 1]; workspace.chooseDragScope(.fragment)
            try require(workspace.selectedAtomIndices == [1,2,3,4,5], "Fragment did not stop at both Fe and Ru")
            workspace.clearSelection()
            try await click(1)
            try require(workspace.selectedAtomIndices == [1,2,3,4,5], "Native ligand click selected \(workspace.selectedAtomIndices) instead of ligand atoms 1–5")
            guard let start = view.projectedAtomPoint(1) else { throw ParseError.noGeometry }
            let end = CGPoint(x: start.x + 28, y: start.y + 15)
            view.rightMouseDown(with: event(.rightMouseDown, start, flags: .control)); view.rightMouseDragged(with: event(.rightMouseDragged, end, flags: .control)); view.rightMouseUp(with: event(.rightMouseUp, end, flags: .control))
            try await Task.sleep(nanoseconds: 150_000_000)
            let moved = workspace.currentFrame!
            let delta = moved.atoms[1].position - original.atoms[1].position
            try require(delta.length > 0.01, "Ligand drag did not move")
            for index in atoms.indices {
                if (1...5).contains(index) {
                    try require(((moved.atoms[index].position - original.atoms[index].position) - delta).length < 1e-5, "Chelating ligand or its H did not move rigidly")
                } else { try require(moved.atoms[index] == original.atoms[index], "Ligand drag moved a metal or another ligand") }
            }
            try require(moved.bonds == original.bonds, "Ligand selection destroyed coordination bonds")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Ligand drag undo failed")
            // Activate the real native rotation button and compare an independent 90° oracle.
            func rotationButton(_ id: String, in root: NSView) -> NSButton? {
                if let button = root as? NSButton, button.identifier?.rawValue == id { return button }
                return root.subviews.lazy.compactMap { rotationButton(id, in: $0) }.first
            }
            workspace.rotationPivot = .metal; workspace.rotationMetalIndex = 8; workspace.rotationStep = 90
            try await Task.sleep(nanoseconds: 200_000_000)
            guard let content = window.contentView, let rotate = rotationButton("motif-rotate-Z-plus", in: content) else { throw ParseError.malformed("Native motif rotation button missing") }
            try require(workspace.selectedCoordinatingMetals == [0,8], "Metal pivot choices do not include both coordinating metals")
            rotate.performClick(nil)
            let rotated = workspace.currentFrame!
            let pivot = original.atoms[8].position
            for index in atoms.indices {
                if (1...5).contains(index) {
                    let r = original.atoms[index].position - pivot
                    let expected = pivot + Vector3(-r.y, r.x, r.z)
                    try require((rotated.atoms[index].position - expected).length < 1e-5, "Motif rotation did not use the selected Ru pivot")
                } else { try require(rotated.atoms[index] == original.atoms[index], "Motif rotation moved a metal or another ligand") }
            }
            try require(rotated.bonds == original.bonds, "Rotation changed connectivity")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Motif rotation undo failed")
            workspace.rotationPivot = .center
            rotate.performClick(nil)
            let centered = workspace.currentFrame!
            let center = (1...5).reduce(Vector3.zero) { $0 + original.atoms[$1].position } * (1 / Float(5))
            for index in 1...5 {
                let r = original.atoms[index].position - center
                try require((centered.atoms[index].position - (center + Vector3(-r.y,r.x,r.z))).length < 1e-5, "Group-center motif rotation failed")
            }
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Group rotation undo failed")
            try await click(6); try require(workspace.selectedAtomIndices == [6,7], "Separate ligand click crossed the metal")
            try await click(9); try require(workspace.selectedAtomIndices == [9], "Terminal chloride selection crossed Ru")
            try await click(0); try require(workspace.selectedAtomIndices == Array(0...7), "Metal click did not select its attached motif while stopping at Ru")
            try await click(10); try require(workspace.selectedAtomIndices == [10,11], "Metal-free connected motif failed")
            try require(try Data(contentsOf: source) == data, "Ligand editing modified the source fixture")
            if let path = ProcessInfo.processInfo.environment["CHEMVIEWER_MOTIF_REPRO_PATH"] {
                let url = URL(fileURLWithPath: path), before = try Data(contentsOf: URL(fileURLWithPath: path))
                workspace.open(url)
                for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
                try await Task.sleep(nanoseconds: 250_000_000)
                guard let repro = workspace.currentFrame, repro.atoms.count == 42,
                      repro.atoms[0].element == "Li", repro.atoms[1].element == "Li",
                      let live = NSApp.windows.compactMap({ $0.contentView.flatMap(find) }).first,
                      let liveWindow = live.window else { throw ParseError.malformed("Private two-Li reproduction layout changed") }
                var camera = live.captureViewportState(); camera.yaw = .pi/4; camera.pitch = 0.61548; camera.roll = 0
                live.restoreViewportState(camera)
                workspace.armAtom("Fe")
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let metalPoint = live.projectedAtomPoint(0) else { throw ParseError.noGeometry }
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let e = NSEvent.mouseEvent(with: type, location: live.convert(metalPoint, to: nil), modifierFlags: [], timestamp: 0,
                        windowNumber: liveWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                    if type == .leftMouseDown { live.mouseDown(with: e) } else { live.mouseUp(with: e) }
                }
                try await Task.sleep(nanoseconds: 150_000_000)
                let substituted = workspace.currentFrame!
                try require(substituted.atoms.count == 42 && substituted.atoms[0].element == "Fe" && substituted.bonds == repro.bonds,
                            "Private Li-to-Fe substitution changed atom count or connectivity")
                try require(zip(substituted.atoms,repro.atoms).allSatisfy { $0.0.position == $0.1.position }, "Private metal substitution moved coordinates")
                workspace.clearSelection(); workspace.undoGeometry()
                try require(workspace.currentFrame == repro, "Private metal substitution undo failed")
                workspace.clearSelection(); workspace.chooseDragScope(.fragment)
                for center in [0,1] {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    guard let point = live.projectedAtomPoint(center) else { throw ParseError.noGeometry }
                    func mouse(_ type: NSEvent.EventType) -> NSEvent {
                        NSEvent.mouseEvent(with: type, location: live.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                            windowNumber: liveWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                    }
                    live.mouseDown(with: mouse(.leftMouseDown)); live.mouseUp(with: mouse(.leftMouseUp))
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let indices = center == 0 ? [0] + Array(22...41) : [1] + Array(2...21)
                    try require(workspace.selectedAtomIndices == indices, "Private metal click selected \(workspace.selectedAtomIndices), expected one 21-atom motif")
                    try require(workspace.rotationPivot == .metal && workspace.rotationMetalIndex == center && workspace.selectedCoordinatingMetals == [center], "Metal click did not choose its own rotation center")
                    workspace.rotationStep = 90
                    for axis in ["X","Y","Z"] {
                        guard let content = liveWindow.contentView, let button = rotationButton("motif-rotate-" + axis + "-plus", in: content) else { throw ParseError.malformed("Private-case rotation button missing") }
                        button.performClick(nil)
                        let result = workspace.currentFrame!, pivot = repro.atoms[center].position
                        for i in repro.atoms.indices {
                            if indices.contains(i) {
                                let r = repro.atoms[i].position - pivot
                                let q = axis == "X" ? Vector3(r.x,-r.z,r.y) : axis == "Y" ? Vector3(r.z,r.y,-r.x) : Vector3(-r.y,r.x,r.z)
                                try require((result.atoms[i].position - (pivot+q)).length < 1e-5, "Private motif rotation disagrees with exact 90-degree oracle")
                            } else { try require(result.atoms[i] == repro.atoms[i], "Private motif rotation moved the other 21-atom unit") }
                        }
                        workspace.undoGeometry(); try require(workspace.currentFrame == repro, "Private motif rotation undo failed")
                    }
                }
                try require(try Data(contentsOf: url) == before, "Private source XYZ was modified")
                print("PRIVATE_METAL_MOTIF_PASS: Li-to-Fe replacement with fixed coordinates and connectivity; both 21-atom Li units selected by actual metal clicks; native X/Y/Z rotations about the clicked centers; other unit fixed; exact undo; source bytes unchanged.")
            }
            print("LIGAND_SELECTION_PASS: metal replacement without topology changes, native rotation buttons with Ru/center pivots and exact 90-degree coordinates, actual native ligand click/drag; Fe chelate, Ru bridge, attached H, metal boundaries, isolated other ligands, metal-centered motif, metal-free motif, intact coordination bonds, rigid displacement, one-step undo and unchanged source.")
            fflush(stdout); exit(0)
        } catch { fputs("LIGAND_SELECTION_FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
