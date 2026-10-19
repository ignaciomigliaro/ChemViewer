import AppKit
import ChemCraftCore

@MainActor
enum ManipulationSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        var exitCode: Int32 = 0
        do {
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NSError(domain: "ManipulationSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            }
            func wait() async throws { try await Task.sleep(nanoseconds: 150_000_000) }
            func find<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
                if let view = root as? T { return view }
                return root.subviews.lazy.compactMap { find(type, in: $0) }.first
            }
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("ChemViewer-manipulation-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temp) }
            let args = CommandLine.arguments
            let evidence = args.firstIndex(of: "--manipulation-evidence").flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil } ?? temp
            try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
            let xyz = temp.appendingPathComponent("fragment-test.xyz")
            try "4\nenergy=-10 Eh; synthetic manipulation fixture\nC 0 0 0\nC 1.4 0 0\nC 2.8 0 0\nO 0 3 0\n".write(to: xyz, atomically: true, encoding: .utf8)
            workspace.open(xyz)
            for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
            try await wait()
            try require(workspace.errorMessage == nil, workspace.errorMessage ?? "Load failed")
            guard let window = NSApp.windows.first(where: { $0.contentView.flatMap { find(MolecularMTKView.self, in: $0) } != nil }),
                  let root = window.contentView, let view = find(MolecularMTKView.self, in: root), let original = workspace.currentFrame else { throw CocoaError(.coderReadCorrupt) }
            window.setContentSize(NSSize(width: 1100, height: 760))
            try await wait()
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            func drag(_ seed: Int, _ dx: CGFloat, _ dy: CGFloat) async throws {
                guard let p = view.projectedAtomPoint(seed) else { throw CocoaError(.coderReadCorrupt) }
                let q = CGPoint(x: p.x + dx, y: p.y + dy)
                view.mouseDown(with: event(.leftMouseDown, p))
                view.mouseDragged(with: event(.leftMouseDragged, q))
                view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: q.x + dx, y: q.y + dy)))
                view.mouseUp(with: event(.leftMouseUp, CGPoint(x: q.x + dx, y: q.y + dy)))
                try await wait()
            }
            func screenshot(_ name: String) async throws {
                guard args.contains("--capture-window") else { return }
                window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); try await wait()
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent(name).path]
                try p.run(); p.waitUntilExit(); try require(p.terminationStatus == 0, "Capture failed")
            }
            workspace.selectedAtomIndices = [0, 1, 2]
            try await wait()
            view.rightMouseDown(with: event(.rightMouseDown, .zero))
            try require(workspace.selectedAtomIndices.isEmpty, "Right-click did not clear all atoms")
            workspace.chooseDragScope(.atom); try await wait()
            try await drag(0, 20, 10)
            try require(workspace.currentFrame?.atoms[0] != original.atoms[0], "Atom drag did not move its target")
            try require(Array(workspace.currentFrame!.atoms.dropFirst()) == Array(original.atoms.dropFirst()), "Atom drag moved unselected atoms")
            try require(workspace.currentFrame?.energyHartree == nil, "Drag kept stale energy")
            workspace.undoGeometry()
            try require(workspace.currentFrame == original && !workspace.canUndoGeometry, "One drag did not create exactly one undo step")
            workspace.isDraggingEnabled = false
            workspace.selectedAtomIndices = [0, 1]
            workspace.chooseDragScope(.fragment)
            try require(workspace.selectedAtomIndices == [1, 2], "Fragment boundary did not identify second side")
            try await wait()
            try await drag(2, 20, 15)
            let moved = workspace.currentFrame!
            try require(moved.atoms[0] == original.atoms[0] && moved.atoms[3] == original.atoms[3], "Fragment drag moved outside atoms")
            let delta1 = moved.atoms[1].position - original.atoms[1].position
            let delta2 = moved.atoms[2].position - original.atoms[2].position
            try require((delta1 - delta2).length < 1e-5 && delta1.length > 0.01, "Fragment drag was not rigid")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Fragment drag undo")
            workspace.rotationPivot = .anchor; workspace.rotationStep = 90
            workspace.rotateManipulation(axis: Vector3(0, 0, 1), sign: 1)
            let rotated = workspace.currentFrame!
            try require(abs(rotated.atoms[1].position.x) < 1e-5 && abs(rotated.atoms[1].position.y - 1.4) < 1e-5, "Fragment rotation pivot/axis")
            try require(rotated.atoms[0] == original.atoms[0] && rotated.atoms[3] == original.atoms[3], "Rotation moved outside atoms")
            try await screenshot("fragment-toolbar.png")
            workspace.undoGeometry()
            workspace.chooseDragScope(.molecule); try await wait()
            try await drag(1, 12, -8)
            let whole = workspace.currentFrame!
            let firstDelta = whole.atoms[0].position - original.atoms[0].position
            for index in whole.atoms.indices { try require(((whole.atoms[index].position - original.atoms[index].position) - firstDelta).length < 1e-5, "Whole molecule did not translate rigidly") }
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Whole molecule undo")
            workspace.isDraggingEnabled = false
            workspace.selectedAtomIndices = [0, 1, 3]
            workspace.applyAngle(90, movement: .bothEnds)
            try require(abs(try GeometryEditor.angleDegrees(in: workspace.currentFrame!, firstAtomIndex: 0, vertexAtomIndex: 1, thirdAtomIndex: 3) - 90) < 1e-4, "Both-end angle edit")
            workspace.undoGeometry()
            // Use a private named pasteboard: never replace the user's clipboard.
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let coordinates = ClipboardSupport.coordinates(original.atoms)
            try require(ClipboardSupport.copy(coordinates, pasteboard: pasteboard) && pasteboard.string(forType: .string) == coordinates, "Coordinate clipboard copy")
            try require(coordinates.split(separator: "\n").count == 4, "Copied coordinate rows")
            let orca = temp.appendingPathComponent("thermochemistry.out")
            let text = "CARTESIAN COORDINATES (ANGSTROEM)\n----\nO 0 0 0\nH 1 0 0\nH 0 1 0\n\nTOTAL SCF ENERGY\nTotal Energy : -10.05 Eh\nFINAL SINGLE POINT ENERGY -10.05\nTHERMOCHEMISTRY AT 298.15K\nTemperature ... 298.15 K\nPressure ... 1.00 atm\nElectronic energy ... -10.0 Eh\nZero point energy ... 0.15 Eh\nThermal Enthalpy correction ... 0.00094421 Eh\nTotal Enthalpy ... -9.8 Eh\nFinal Gibbs free energy ... -9.9 Eh\nG-E(el) ... 0.1 Eh\n"
            try text.write(to: orca, atomically: true, encoding: .utf8)
            workspace.open(orca)
            for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
            workspace.activeTab = "Abstract"; try await wait()
            guard let thermo = workspace.document?.thermochemistry.last else { throw CocoaError(.coderReadCorrupt) }
            try require(abs(thermo.summedEnthalpy(electronicEnergy: -10.05)! + 9.85) < 1e-10, "Enthalpy sum")
            try require(abs(thermo.summedGibbs(electronicEnergy: -10.05)! + 9.95) < 1e-10, "Gibbs sum")
            let number = ClipboardSupport.number(thermo.summedGibbs(electronicEnergy: -10.05)!)
            try require(ClipboardSupport.copy(number, pasteboard: pasteboard) && pasteboard.string(forType: .string) == "-9.950000000000", "Numeric-only energy copy")
            try await screenshot("clean-abstract.png")
            workspace.activeTab = "Coord"; try await wait(); try await screenshot("copy-coordinates.png")
            print("Manipulation workflow PASS: right-click clear, actual mouse-handler atom/fragment/molecule drags, rigid group transforms, attachment-axis rotation, one-step gesture undo, both-end angle edit, isolated clipboard roundtrips, thermochemistry sums and clean Abstract/Coord views.")
            fflush(stdout)
        } catch {
            fputs("Manipulation workflow FAIL: \(error.localizedDescription)\n", stderr); exitCode = 1
        }
        exit(exitCode)
    }
}
