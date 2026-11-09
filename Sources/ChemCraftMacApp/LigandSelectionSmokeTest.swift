import AppKit
import ChemCraftCore

@MainActor
enum LigandSelectionSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
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
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            func click(_ index: Int) async throws {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let point = view.projectedAtomPoint(index) else { throw ParseError.noGeometry }
                view.mouseDown(with: event(.leftMouseDown, point)); view.mouseUp(with: event(.leftMouseUp, point))
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            workspace.selectedAtomIndices = [0, 1]; workspace.chooseDragScope(.fragment)
            try require(workspace.selectedAtomIndices == [1,2,3,4,5], "Fragment did not stop at both Fe and Ru")
            workspace.clearSelection()
            try await click(1)
            try require(workspace.selectedAtomIndices == [1,2,3,4,5], "Native ligand click selected \(workspace.selectedAtomIndices) instead of ligand atoms 1–5")
            guard let start = view.projectedAtomPoint(1) else { throw ParseError.noGeometry }
            let end = CGPoint(x: start.x + 28, y: start.y + 15)
            view.mouseDown(with: event(.leftMouseDown, start)); view.mouseDragged(with: event(.leftMouseDragged, end)); view.mouseUp(with: event(.leftMouseUp, end))
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
            try await click(6); try require(workspace.selectedAtomIndices == [6,7], "Separate ligand click crossed the metal")
            try await click(9); try require(workspace.selectedAtomIndices == [9], "Terminal chloride selection crossed Ru")
            try await click(0); try require(workspace.selectedAtomIndices == [0], "Metal click selected its coordination sphere")
            try await click(10); try require(workspace.selectedAtomIndices == [10,11], "Metal-free connected motif failed")
            try require(try Data(contentsOf: source) == data, "Ligand editing modified the source fixture")
            print("LIGAND_SELECTION_PASS: actual native ligand click/drag; Fe chelate, Ru bridge, attached H, metal boundaries, isolated other ligands, metal-only seed, metal-free motif, intact coordination bonds, rigid displacement, one-step undo and unchanged source.")
            fflush(stdout); exit(0)
        } catch { fputs("LIGAND_SELECTION_FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
