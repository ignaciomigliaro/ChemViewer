import AppKit
import ChemCraftCore

@MainActor enum FragmentRotationSmokeTest {
    static func run(workspace: WorkspaceStore) async {
        do {
            func require(_ ok: Bool, _ message: String) throws { if !ok { throw ParseError.malformed(message) } }
            func pause() async throws { try await Task.sleep(nanoseconds: 200_000_000) }
            // Original synthetic substituted hexagon: atoms 0/1 fixed, ring 2...7.
            var atoms = [Atom(id: 0, element: "C", position: Vector3(-2.9, 0, 0)), Atom(id: 1, element: "C", position: Vector3(-1.4, 0, 0))]
            for i in 0..<6 {
                let angle = Float(i) * .pi / 3
                atoms.append(Atom(id: i + 2, element: "C", position: Vector3(1.4 - 1.4 * cos(angle), 1.4 * sin(angle), 0)))
            }
            workspace.applyBuildingProject(try BuildingProject(atoms: atoms))
            workspace.selectedAtomIndices = [1, 2]; workspace.chooseBondSide()
            try require(workspace.selectedAtomIndices.sorted() == Array(2...7), "Ring side was not isolated")
            try await pause()
            guard let view = AnimationExporter.viewport(), let window = view.window else { throw ParseError.noGeometry }
            let before = workspace.currentFrame!, camera = view.viewingRotation
            func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: .option,
                  timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            let p = view.projectedAtomPoint(4)!
            view.rightMouseDown(with: event(.rightMouseDown, p))
            view.rightMouseDragged(with: event(.rightMouseDragged, CGPoint(x: p.x + 90, y: p.y)))
            view.rightMouseDragged(with: event(.rightMouseDragged, CGPoint(x: p.x + 180, y: p.y)))
            view.rightMouseUp(with: event(.rightMouseUp, CGPoint(x: p.x + 180, y: p.y)))
            try await pause()
            let after = workspace.currentFrame!
            try require(view.viewingRotation == camera, "Fragment gesture rotated camera")
            try require(Array(after.atoms.prefix(2)) == Array(before.atoms.prefix(2)), "Fixed side moved")
            for i in 2...7 {
                let old = before.atoms[i].position, actual = after.atoms[i].position
                try require(abs(actual.x - old.x) < 1e-4 && abs(actual.y) < 1e-4 && abs(actual.z - old.y) < 1e-4, "Ring 90-degree bond-axis oracle mismatch")
            }
            try require(after.bonds == before.bonds && after.energyHartree == nil, "Topology/energy regression")
            workspace.undoGeometry()
            try require(workspace.currentFrame == before, "Rotation not one undo step")
            // Free motif rotation uses screen axes, preserving camera and pair distances.
            workspace.chooseDragScope(.fragment); try await pause()
            let freeBefore = workspace.currentFrame!
            let q = view.projectedAtomPoint(4)!
            view.rightMouseDown(with: event(.rightMouseDown, q))
            view.rightMouseDragged(with: event(.rightMouseDragged, CGPoint(x: q.x + 80, y: q.y + 50)))
            view.rightMouseUp(with: event(.rightMouseUp, CGPoint(x: q.x + 80, y: q.y + 50)))
            try await pause()
            try require(workspace.currentFrame!.atoms != freeBefore.atoms && view.viewingRotation == camera, "Free rotation failed or changed camera")
            for bond in freeBefore.bonds {
                let old = freeBefore.atoms[bond.first].position - freeBefore.atoms[bond.second].position
                let new = workspace.currentFrame!.atoms[bond.first].position - workspace.currentFrame!.atoms[bond.second].position
                try require(abs(old.length - new.length) < 1e-4, "Free motif rotation distorted bonds")
            }
            workspace.undoGeometry(); try require(workspace.currentFrame == freeBefore, "Free rotation undo failed")
            print("FRAGMENT_ROTATION_PASS: actual Option-right-drag, bonded ring isolation, independent 90-degree Cartesian oracle, fixed remainder, topology, unchanged camera, one-step undo and free rigid motif rotation")
            exit(0)
        } catch { fputs("FRAGMENT_ROTATION_FAIL: \(error)\n", stderr); exit(1) }
    }
}
