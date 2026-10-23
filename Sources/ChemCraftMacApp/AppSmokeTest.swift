import AppKit
import ChemCraftCore

/// Opt-in integration check, invoked only with --smoke-test.
@MainActor
enum AppSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-smoke-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NSError(domain: "ChemViewerSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            }
            let xyz = directory.appendingPathComponent("water.xyz")
            try "3\nwater\nO 0 0 0\nH 0.9572 0 0\nH -0.239987208 0.926627207 0\n".write(to: xyz, atomically: true, encoding: .utf8)
            workspace.open(xyz)
            for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            try require(workspace.errorMessage == nil, workspace.errorMessage ?? "file load")
            try require(workspace.currentFrame?.atoms.count == 3, "XYZ opening did not produce three atoms")
            guard let original = workspace.currentFrame else { throw CocoaError(.fileReadCorruptFile) }
            let exported = XYZWriter.string(frame: original)
            let roundTrip = try XYZParser.parse(text: exported)
            try require(roundTrip.frames.first?.atoms.map(\.element) == ["O", "H", "H"], "XYZ export atom identities")
            var edited = original.atoms; edited[1].position.x += 0.25
            workspace.replaceCurrentAtoms(edited)
            try require(workspace.canUndoGeometry, "undo state")
            workspace.undoGeometry()
            try require(workspace.currentFrame?.atoms == original.atoms, "geometry undo")
            workspace.selectedAtomIndices = [0, 1]
            try await Task.sleep(nanoseconds: 300_000_000)
            func metalView(in root: NSView) -> MolecularMTKView? {
                if let view = root as? MolecularMTKView { return view }
                return root.subviews.lazy.compactMap { metalView(in: $0) }.first
            }
            guard let view = NSApp.windows.compactMap({ $0.contentView }).compactMap({ metalView(in: $0) }).first else {
                throw NSError(domain: "ChemViewerSmokeTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "No live Metal viewport"])
            }
            let appRoot = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
            let shaderRoot = view.shaderBundlePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
            try require(shaderRoot?.hasPrefix(appRoot + "/") == true, "Shader resources were not loaded from the app bundle")
            try require(view.renderingReady, view.renderingFailure ?? "Metal pipeline initialization failed")
            view.draw()
            try await Task.sleep(nanoseconds: 200_000_000)
            try require(view.completedFrameCount > 0, view.renderingFailure ?? "No completed Metal frame")
            try require(view.scene.selectedAtomIndices == [0, 1], "selection did not reach renderer")
            try require(view.depthStencilPixelFormat == .depth32Float, "missing depth attachment")
            try require(workspace.sourceText.contains("O 0 0 0"), "Source tab lost original input text")
            let arguments = CommandLine.arguments
            let evidence = arguments.firstIndex(of: "--render-evidence").flatMap { arguments.indices.contains($0 + 1) ? URL(fileURLWithPath: arguments[$0 + 1], isDirectory: true) : nil } ?? directory
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            func capture(_ view: MolecularMTKView, name: String) async throws -> NSBitmapImageRep {
                let url = evidence.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: url)
                view.capture(to: url)
                for _ in 0..<100 {
                    if let data = try? Data(contentsOf: url), let bitmap = NSBitmapImageRep(data: data) { return bitmap }
                    try await Task.sleep(nanoseconds: 30_000_000)
                }
                throw NSError(domain: "ChemViewerSmokeTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG capture did not complete"])
            }
            workspace.selectedAtomIndices = []
            try await Task.sleep(nanoseconds: 100_000_000)
            let water = try await capture(view, name: "water-render.png")
            try require(water.pixelsWide > 100 && water.pixelsHigh > 100, "PNG dimensions")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "front")
            let front = Atom(id: 0, element: "O", position: Vector3(0, 0, -0.4))
            let back = Atom(id: 1, element: "N", position: Vector3(0, 0, 0.4))
            view.scene = RenderScene(atoms: [front, back], bonds: [], displacements: [], amplitude: 0, animate: false, showDisplacementVectors: false, selectedAtomIndices: [])
            let overlapA = try await capture(view, name: "overlap-a.png")
            view.scene = RenderScene(atoms: [back, front], bonds: [], displacements: [], amplitude: 0, animate: false, showDisplacementVectors: false, selectedAtomIndices: [])
            let overlapB = try await capture(view, name: "overlap-b.png")
            let pixelA = overlapA.colorAt(x: overlapA.pixelsWide / 2, y: overlapA.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
            let pixelB = overlapB.colorAt(x: overlapB.pixelsWide / 2, y: overlapB.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
            try require(pixelA.redComponent > pixelA.blueComponent + 0.1, "Front oxygen was hidden behind rear nitrogen")
            try require(abs(pixelA.redComponent - pixelB.redComponent) < 0.01 && abs(pixelA.blueComponent - pixelB.blueComponent) < 0.01, "Atom occlusion depends on input ordering")
            if let index = arguments.firstIndex(of: "--preview-file"), arguments.indices.contains(index + 1) {
                workspace.open(URL(fileURLWithPath: arguments[index + 1]))
                for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 50_000_000) }
                try await Task.sleep(nanoseconds: 200_000_000)
                guard let preview = NSApp.windows.compactMap({ $0.contentView }).compactMap({ metalView(in: $0) }).first else { throw CocoaError(.coderReadCorrupt) }
                _ = try await capture(preview, name: "molecular-preview.png")
            }
            // Exercise each actual tab through SwiftUI; source and coordinates
            // must mount real AppKit controls, and Image/Abs must keep a live GPU view.
            for tab in ["Abstract", "Source", "Coord", "Image/Abs", "Image"] {
                workspace.activeTab = tab
                try await Task.sleep(nanoseconds: 150_000_000)
                if tab == "Source" {
                    func sourceView(in root: NSView) -> NSTextView? {
                        if let text = root as? NSTextView, text.string == workspace.sourceText { return text }
                        return root.subviews.lazy.compactMap { sourceView(in: $0) }.first
                    }
                    try require(NSApp.windows.compactMap(\.contentView).contains { sourceView(in: $0) != nil }, "Source tab did not mount original text")
                }
                if tab == "Image/Abs" || tab == "Image" {
                    try require(NSApp.windows.compactMap(\.contentView).contains { metalView(in: $0) != nil }, "\(tab) lost its molecule viewport")
                }
                if arguments.contains("--capture-window"), let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) {
                    let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent("tab-\(tab.replacingOccurrences(of: "/", with: "-" )).png").path]
                    try capture.run(); capture.waitUntilExit()
                }
            }
            if arguments.contains("--capture-window"), let window = NSApp.windows.first(where: { $0.contentView.flatMap { metalView(in: $0) } != nil }) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(nanoseconds: 300_000_000)
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent("workspace-window.png").path]
                try capture.run()
                capture.waitUntilExit()
                print("Window capture status: \(capture.terminationStatus)")
            }
            let normal = directory.appendingPathComponent("mode.out")
            let modeText = """
            CARTESIAN COORDINATES (ANGSTROEM)
            ---------------------------------
            O 0 0 0
            H 0.9572 0 0
            H -0.239987208 0.926627207 0

            FINAL SINGLE POINT ENERGY -76.123456
            VIBRATIONAL FREQUENCIES
            6: -42.50 cm**-1
            NORMAL MODES
                  6
            0 0.000
            1 0.010
            2 0.020
            3 0.000
            4 -0.300
            5 0.400
            6 0.000
            7 0.300
            8 0.400
            IR SPECTRUM
            6: -42.50 2.5
            THERMOCHEMISTRY
            """
            try modeText.write(to: normal, atomically: true, encoding: .utf8)
            workspace.open(normal)
            for _ in 0..<100 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            try require(workspace.selectedMode?.frequencyCM1 == -42.5, "imaginary frequency sign or selection")
            try await Task.sleep(nanoseconds: 250_000_000)
            guard let vibrationView = NSApp.windows.compactMap({ $0.contentView }).compactMap({ metalView(in: $0) }).first else { throw CocoaError(.coderReadCorrupt) }
            try require(vibrationView.renderingReady, vibrationView.renderingFailure ?? "ORCA viewport initialization")
            try require(vibrationView.scene.animate && vibrationView.scene.displacements.count == 3, "normal-mode animation setup")
            let frameCount = vibrationView.completedFrameCount
            try await Task.sleep(nanoseconds: 250_000_000)
            try require(vibrationView.completedFrameCount > frameCount, "animation stopped producing Metal frames")
            workspace.isVibrating = false
            try await Task.sleep(nanoseconds: 150_000_000)
            try require(!vibrationView.scene.animate, "pause did not reach renderer")
            try require(workspace.currentFrame?.atoms.count == 3, "animation modified source geometry")
            print("ChemViewer smoke test PASS: packaged shader pipelines, completed Metal frames, XYZ opening/export, coordinate undo, selection, exact source text, PNG capture, depth-order independence, five view tabs, ORCA negative mode, animation and pause.")
            fflush(stdout)
            exit(0)
        } catch {
            fputs("ChemViewer smoke test FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
