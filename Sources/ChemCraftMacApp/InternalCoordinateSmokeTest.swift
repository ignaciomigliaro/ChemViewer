import AppKit
import ChemCraftCore

@MainActor enum InternalCoordinateSmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
            func pause() async { try? await Task.sleep(nanoseconds: 180_000_000) }
            let args = CommandLine.arguments
            guard let f = args.firstIndex(of: "--internal-coordinate-fixture"), args.indices.contains(f + 1) else { throw ParseError.malformed("Supply the original internal-coordinate fixture") }
            let url = URL(fileURLWithPath: args[f + 1]), source = try Data(contentsOf: url)
            workspace.open(url)
            for _ in 0..<200 { if !workspace.isLoading { break }; await pause() }
            await pause()
            guard let view = AnimationExporter.viewport(), let window = view.window, let root = window.contentView, let original = workspace.currentFrame else { throw ParseError.noGeometry }
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
            func button(_ id: String) throws -> NSButton {
                guard let button = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == id }) else { throw ParseError.malformed("Missing geometry control: " + id) }
                return button
            }
            func enter(_ placeholder: String, _ number: String) async throws {
                guard let field = descendants(root).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.placeholderString == placeholder }) else { throw ParseError.malformed("Missing numeric field: " + placeholder) }
                window.makeFirstResponder(field); field.selectText(nil)
                guard let editor = field.currentEditor() else { throw ParseError.malformed("Numeric editor unavailable") }
                editor.string = number
                NotificationCenter.default.post(name: NSText.didChangeNotification, object: editor)
                window.makeFirstResponder(nil)
                await pause()
            }
            let object = try JSONSerialization.jsonObject(with: source) as! [String: Any]
            let oracle = object["oracles"] as! [String: [[Double]]]
            func check(_ key: String) throws {
                guard let current = workspace.currentFrame else { throw ParseError.noGeometry }
                for (i, p) in oracle[key]!.enumerated() {
                    let q = current.atoms[i].position
                    try require(abs(Double(q.x)-p[0]) < 1e-5 && abs(Double(q.y)-p[1]) < 1e-5 && abs(Double(q.z)-p[2]) < 1e-5, "Numeric edit disagrees with tabulated Cartesian oracle at atom \(i)")
                }
                try require(current.bonds == original.bonds && current.energyHartree == nil, "Numeric edit changed connectivity or retained stale energy")
            }
            workspace.selectedAtomIndices = [1,2]; await pause()
            try await enter("Distance", "3")
            try button("geometry-apply-distance").performClick(nil); await pause()
            try check("distance3")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Distance Undo lost atoms/topology")
            workspace.redoGeometry(); try check("distance3")
            workspace.undoGeometry(); await pause()
            workspace.selectedAtomIndices = [0,1,2]; await pause()
            try await enter("Angle", "60")
            try button("geometry-apply-angle").performClick(nil); await pause()
            try check("angle60")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Angle Undo failed")
            try require(try Data(contentsOf: url) == source, "Numeric editing changed source bytes")

            // Two isolated carbons and an explicitly deleted close pair.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("internal-coordinates-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var project = try BuildingProject(atoms: [Atom(id: 0, element: "C", position: .zero), Atom(id: 1, element: "C", position: Vector3(4,0,0)), Atom(id: 2, element: "C", position: Vector3(0,1.4,0))])
            project.explicitBonds = []
            let separated = folder.appendingPathComponent("contacts.cvproject")
            try JSONEncoder().encode(project).write(to: separated)
            workspace.open(separated)
            for _ in 0..<200 { if !workspace.isLoading { break }; await pause() }
            await pause()
            guard let live = AnimationExporter.viewport(), let baseline = workspace.currentFrame else { throw ParseError.noGeometry }
            workspace.chooseDragScope(.atom); workspace.dragAxis = .x; workspace.addBondsAfterDragging = true
            await pause()
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "front")
            func dragToContact() throws {
                let start = live.projectedAtomPoint(1)!, fixed = live.projectedAtomPoint(0)!
                // 4 -> 1.4 Å: retain 35% of the initial screen separation.
                let finish = CGPoint(x: fixed.x + (start.x-fixed.x)*0.35, y: start.y)
                func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: live.convert(p, to: nil), modifierFlags: .control, timestamp: 0, windowNumber: live.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                }
                live.rightMouseDown(with: event(.rightMouseDown, start))
                live.rightMouseDragged(with: event(.rightMouseDragged, finish))
                try require(workspace.currentFrame == baseline, "Drag preview published coordinates or bonds")
                live.rightMouseUp(with: event(.rightMouseUp, finish))
            }
            try dragToContact(); await pause()
            try require(workspace.currentFrame!.bonds.count == 1 && Set([workspace.currentFrame!.bonds[0].first,workspace.currentFrame!.bonds[0].second]) == Set([0,1]), "Drag did not add its new contact or restored the deleted old pair")
            workspace.undoGeometry(); try require(workspace.currentFrame == baseline && !workspace.canUndoGeometry, "Drag/bond creation was not one exact Undo")
            workspace.addBondsAfterDragging = false; await pause()
            try dragToContact(); await pause()
            try require(workspace.currentFrame!.bonds.isEmpty, "Disabled automatic bonding added a bond")
            workspace.undoGeometry(); await pause()
            workspace.isDraggingEnabled = false; workspace.selectedAtomIndices = [0,1]; await pause()
            try button("geometry-toggle-bond").performClick(nil); await pause()
            try require(workspace.currentFrame!.bonds.count == 1, "Create bond button failed")
            workspace.undoGeometry(); await pause()
            try button("geometry-generate-bonds").performClick(nil); await pause()
            try require(workspace.currentFrame!.bonds.count == 1 && Set([workspace.currentFrame!.bonds[0].first,workspace.currentFrame!.bonds[0].second]) == Set([0,2]), "Generate bonds button did not detect the close pair")
            let saved = folder.appendingPathComponent("generated.cvproject")
            try JSONEncoder().encode(workspace.buildingProject()).write(to: saved)
            let roundTrip = try JSONDecoder().decode(BuildingProject.self, from: Data(contentsOf: saved))
            try require(roundTrip.explicitBonds == workspace.currentFrame!.bonds, "Generated bonds did not persist in project")
            workspace.undoGeometry(); try require(workspace.currentFrame == baseline, "Generate Undo failed")
            print("INTERNAL_COORDINATE_PASS: native number fields/default fragment buttons, independent Cartesian oracles, rigid length/angle branches, topology/source preservation, Undo/Redo; actual gated drag adds only new contacts; automatic-bonding toggle; native Create/Generate bond controls; one-step Undo and project persistence.")
            fflush(stdout); exit(0)
        } catch { fputs("INTERNAL_COORDINATE_FAIL: \(error)\n", stderr); exit(1) }
    }
}
