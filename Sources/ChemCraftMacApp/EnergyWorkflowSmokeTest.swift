import AppKit
import ChemCraftCore

@MainActor
enum EnergyWorkflowSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NSError(domain: "EnergyWorkflowSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            }
            func waitForLoad() async throws {
                for _ in 0..<200 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
                try require(!workspace.isLoading && workspace.errorMessage == nil, workspace.errorMessage ?? "Loading timed out")
                try await Task.sleep(nanoseconds: 160_000_000)
            }
            func find<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
                if let view = root as? T { return view }
                return root.subviews.lazy.compactMap { find(type, in: $0) }.first
            }
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("ChemViewer-workflow-\(UUID().uuidString)")
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temp) }
            let args = CommandLine.arguments
            let evidence = args.firstIndex(of: "--energy-evidence").flatMap { args.indices.contains($0 + 1) ? URL(fileURLWithPath: args[$0 + 1]) : nil } ?? temp
            try fm.createDirectory(at: evidence, withIntermediateDirectories: true)
            func screenshot(_ window: NSWindow, _ name: String) async throws {
                guard args.contains("--capture-window") else { return }
                window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(nanoseconds: 150_000_000)
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent(name).path]
                try process.run(); process.waitUntilExit()
                try require(process.terminationStatus == 0, "Window capture failed")
            }
            let trajectory = temp.appendingPathComponent("synthetic-energy-path.xyz")
            let energies = [-76.0, -76.005, -76.002, -75.990, -75.998]
            let text = energies.enumerated().map { index, energy in
                "6\nenergy=\(energy) Eh; synthetic validation geometry \(index + 1)\nO 0 0 0\nH 0.9572 0 0\nH -0.239987208 0.926627207 0\nC 5 0 0\nC 7 0 0\nC 9 0 0\n"
            }.joined()
            try text.write(to: trajectory, atomically: true, encoding: .utf8)
            workspace.open(trajectory); try await waitForLoad()
            try require(workspace.document?.frames.count == 5 && workspace.currentFrame?.energyHartree == energies[4], "Multi-XYZ energies")
            workspace.selectFrame(0); workspace.activeTab = "Image"
            try await Task.sleep(nanoseconds: 150_000_000)
            guard let window = NSApp.windows.first(where: { $0.contentView.flatMap { find(MolecularMTKView.self, in: $0) } != nil }),
                  let root = window.contentView, let viewport = find(MolecularMTKView.self, in: root),
                  let keys = find(GeometryNavigationKeys.KeyView.self, in: root) else { throw CocoaError(.coderReadCorrupt) }
            for index in 0..<6 { viewport.onAtomClick?(index, false) }
            try await Task.sleep(nanoseconds: 100_000_000)
            try require(workspace.selectedAtomIndices == Array(0..<6) && viewport.scene.selectedAtomIndices.count == 6, "Unmodified left-click selection is capped or replaces prior atoms")
            viewport.onAtomClick?(5, false)
            try require(workspace.selectedAtomIndices == Array(0..<5), "Click selected atom did not toggle it off")
            window.makeFirstResponder(viewport)
            let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125)!
            try require(keys.handle(down) == nil && workspace.frameIndex == 1, "Directional arrow routing failed")
            let fieldEditor = NSTextView(frame: .zero); root.addSubview(fieldEditor); window.makeFirstResponder(fieldEditor)
            _ = keys.handle(down)
            try require(workspace.frameIndex == 1, "Arrow navigation intercepted text editing")
            window.makeFirstResponder(viewport); fieldEditor.removeFromSuperview()
            workspace.selectFrame(0)
            guard let original = workspace.currentFrame else { throw CocoaError(.coderReadCorrupt) }
            workspace.selectedAtomIndices = [0, 1]
            workspace.applyDistance(1.5, movement: .secondAtom)
            try require(workspace.currentFrame?.atoms[0] == original.atoms[0], "Distance edit moved fixed atom")
            try require(abs(workspace.currentFrame!.atoms[1].position.x - 1.5) < 1e-6, "Distance target")
            try require(workspace.currentFrame?.energyHartree == nil, "Edited geometry kept a stale energy")
            let editedExport = try XYZParser.parse(text: workspace.exportDocument.text)
            try require(editedExport.frames[0].energyHartree == nil && editedExport.energyRecords.isEmpty, "Edited XYZ export resurrected stale energy")
            workspace.undoGeometry()
            try require(workspace.currentFrame == original, "Undo did not restore energy and geometry")
            workspace.applyDistance(1.2, movement: .bothAtoms)
            let midpoint = (workspace.currentFrame!.atoms[0].position + workspace.currentFrame!.atoms[1].position) * 0.5
            try require(abs(midpoint.x - 0.4786) < 1e-6, "Symmetric distance midpoint moved")
            workspace.undoGeometry()
            workspace.selectedAtomIndices = [1, 0, 2]
            workspace.applyAngle(120)
            let angle = try GeometryEditor.angleDegrees(in: workspace.currentFrame!, firstAtomIndex: 1, vertexAtomIndex: 0, thirdAtomIndex: 2)
            try require(abs(angle - 120) < 1e-4, "Angle target failed")
            try await screenshot(window, "angle-editor.png")
            workspace.stepFrame(1); workspace.stepFrame(-1)
            try require(workspace.canUndoGeometry, "Navigation lost per-geometry undo")
            workspace.undoGeometry(); try require(workspace.currentFrame == original, "Cross-navigation undo")
            workspace.selectedAtomIndices = [0, 1]
            var options = EnergyPlotOptions(); options.title = "Synthetic validation trajectory"
            let request = try options.request(workspace: workspace)
            let plot = try await MatplotlibRunner.render(request)
            defer { try? fm.removeItem(at: plot) }
            for name in ["energy-profile.pdf", "energy-profile.svg", "energy-profile.png", "energy-profile.csv", "plot-input.json", "plot-metadata.json", "energy_landscape.py"] {
                try require(fm.fileExists(atPath: plot.appendingPathComponent(name).path), "Missing Matplotlib export: \(name)")
                let destination = evidence.appendingPathComponent(name)
                if destination != plot.appendingPathComponent(name) { try? fm.removeItem(at: destination); try fm.copyItem(at: plot.appendingPathComponent(name), to: destination) }
            }
            options.coordinate = "distance"
            let distances = try options.request(workspace: workspace)
            try require(abs(distances.points[0].x - 0.9572) < 1e-6, "Plot distance axis")
            workspace.activeTab = "Abstract"; try await Task.sleep(nanoseconds: 150_000_000)
            try await screenshot(window, "abstract-energies.png")
            workspace.isEnergyLandscapePresented = true
            try await Task.sleep(nanoseconds: 2_500_000_000)
            guard let sheet = window.attachedSheet else { throw CocoaError(.coderReadCorrupt) }
            try await screenshot(sheet, "matplotlib-sheet.png")
            workspace.isEnergyLandscapePresented = false
            try await Task.sleep(nanoseconds: 180_000_000)
            let orca = temp.appendingPathComponent("scf.out")
            let output = "CARTESIAN COORDINATES (ANGSTROEM)\n----\nH 0 0 0\n\nTOTAL SCF ENERGY\nTotal Energy : -1.123456789012 Eh\nFINAL SINGLE POINT ENERGY -1.223456789012\n"
            try output.write(to: orca, atomically: true, encoding: .utf8)
            workspace.open(orca); try await waitForLoad()
            try require(workspace.document?.energyRecords.count == 2, "SCF provenance missing")
            workspace.activeTab = "Abstract"; try await Task.sleep(nanoseconds: 160_000_000)
            try await screenshot(window, "abstract-scf.png")
            workspace.showSource(line: workspace.document!.energyRecords[0].sourceLine)
            try await Task.sleep(nanoseconds: 180_000_000)
            guard let source = find(NSTextView.self, in: root) else { throw CocoaError(.coderReadCorrupt) }
            let highlighted = (source.string as NSString).substring(with: source.selectedRange())
            try require(highlighted.contains("-1.123456789012"), "SCF source link did not select its exact line")
            print("Energy workflow PASS: multi-XYZ energies, six-atom click selection, deselection, arrow routing and text-focus protection, distance modes, angle edits, energy invalidation, XYZ export, per-frame undo, SCF/source links, packaged Matplotlib and plot sheet.")
            fflush(stdout); exit(0)
        } catch {
            fputs("Energy workflow FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
