import AppKit
import ChemCraftCore

@MainActor enum VibrationSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-vibration-" + UUID().uuidString)
        func pause() async { try? await Task.sleep(nanoseconds: 180_000_000) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ParseError.malformed(message) }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        func button(_ id: String) throws -> NSButton {
            guard let result = NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap({ descendants($0) }).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == id }) else { throw ParseError.malformed("Missing native button: " + id) }
            return result
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let source = folder.appendingPathComponent("synthetic-modes.out")
            let text = """
            MoleculeView synthetic ORCA-style parser fixture; not a calculation result.
            JOB NUMBER 1
            ! synthetic-test
            Total Charge 0
            Multiplicity 1
            CARTESIAN COORDINATES (ANGSTROEM)
            ---------------------------------
            O 0.000000 0.000000 0.000000
            H 0.758000 0.000000 0.504000
            H -0.758000 0.000000 0.504000
            
            FINAL SINGLE POINT ENERGY -75.000000
            THE OPTIMIZATION HAS CONVERGED
            VIBRATIONAL FREQUENCIES
            -----------------------
            6: 1600.00 cm**-1
            7: 3600.00 cm**-1
            8: -250.00 cm**-1 ***imaginary mode***
            NORMAL MODES
            --------------
            6 7 8
            0 0.000000 0.000000 0.200000
            1 0.000000 0.000000 0.000000
            2 -0.100000 -0.050000 0.000000
            3 0.200000 0.300000 -0.100000
            4 0.000000 0.000000 0.000000
            5 0.300000 0.200000 0.000000
            6 -0.200000 -0.300000 -0.100000
            7 0.000000 0.000000 0.000000
            8 0.300000 0.200000 0.000000
            IR SPECTRUM
            Temperature 298.15 K
            Pressure 1.00 atm
            Zero point energy 0.021000 Eh
            Total Enthalpy -74.970000 Eh
            Final Gibbs free energy -74.990000 Eh
            ****ORCA TERMINATED NORMALLY****
            """
            try text.write(to: source, atomically: true, encoding: .utf8)
            workspace.open(source)
            for _ in 0..<100 { if !workspace.isLoading { break }; await pause() }
            workspace.selectMode(8); workspace.isVibrating = true; workspace.showExplorer = false
            workspace.vibrationAmplitude = 0.5
            await pause(); await pause()
            guard let view = NSApp.windows.compactMap(\.contentView).flatMap({ descendants($0) }).compactMap({ $0 as? MolecularMTKView }).first,
                  let original = workspace.currentFrame, let mode = workspace.selectedMode else { throw ParseError.malformed("No mode/Metal view") }
            try require(mode.frequencyCM1 == -250 && view.renderingReady, "Negative mode/pipeline")
            try button("vibration-vectors").performClick(nil); await pause()
            try require(workspace.showDisplacementVectors && view.scene.showDisplacementVectors, "Vectors button did not toggle renderer")
            try button("vibration-freeze").performClick(nil); await pause()
            let paused = try workspace.displacedVibrationFrame()
            await pause()
            try require(!view.scene.animate && paused == (try workspace.displacedVibrationFrame()), "Freeze drifted")
            try button("vibration-freeze").performClick(nil); await pause()
            try require(view.scene.animate && workspace.isVibrating, "Resume failed")
            try require(!(try button("vibration-save")).isEnabled, "Animated XYZ saving must be disabled")
            try button("vibration-max-positive").performClick(nil); await pause()
            let positive = try workspace.displacedVibrationFrame()
            // Independent printed-vector arithmetic: O x=0+.5*.2; H x=.758+.5*(-.1).
            try require(abs(positive.atoms[0].position.x - 0.1) < 1e-6 && abs(positive.atoms[1].position.x - 0.708) < 1e-6, "Positive maximum coordinates")
            try require(view.scene.vibrationPlayback?.factor(at: ProcessInfo.processInfo.systemUptime) == 1 && !view.scene.animate, "Renderer differs from positive seed")
            try require((try button("vibration-save")).isEnabled, "Frozen XYZ save unavailable")
            let exported = folder.appendingPathComponent("positive.xyz")
            try XYZWriter.string(frame: positive).write(to: exported, atomically: true, encoding: .utf8)
            let reparsed = try XYZParser.parse(text: String(contentsOf: exported, encoding: .utf8))
            try require(reparsed.frames[0].atoms.map(\.position) == positive.atoms.map(\.position) && reparsed.frames[0].energyHartree == nil, "Displaced XYZ round trip/energy")
            let evidence = URL(fileURLWithPath: "/private/tmp/chemviewer-vibration-evidence").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            print("VIBRATION_EVIDENCE: \(evidence.path)"); fflush(stdout)
            func capture(_ name: String) async throws -> NSBitmapImageRep {
                let file = evidence.appendingPathComponent(name)
                view.capture(to: file)
                for _ in 0..<30 { if FileManager.default.fileExists(atPath: file.path) { break }; await pause() }
                guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: file)) else { throw ParseError.malformed("Missing Metal image") }
                return bitmap
            }
            workspace.vibrationAmplitude = 1.5 // Make arrows extend beyond large space-filling spheres.
            for style in MolecularStyle.allCases {
                workspace.renderingStyle = style; await pause()
                let bitmap = try await capture("vectors-" + String(style.shaderStyle) + "-" + style.rawValue.replacingOccurrences(of: "/", with: "-") + ".png")
                var violet = 0
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.blueComponent > c.redComponent * 1.2 && c.redComponent > c.greenComponent * 1.5 && c.blueComponent > 0.15 { violet += 1 }
                    }
                }
                try require(violet > 20, "Displacement arrows disappeared/whitened in " + style.rawValue)
                print("VISIBLE_VECTORS: \(style.rawValue) violet_samples=\(violet)")
            }
            workspace.vibrationAmplitude = 0.5
            try button("vibration-max-negative").performClick(nil); await pause()
            let negative = try workspace.displacedVibrationFrame()
            try require(abs(negative.atoms[0].position.x + 0.1) < 1e-6 && abs(negative.atoms[1].position.x - 0.808) < 1e-6, "Negative maximum coordinates")
            try require(view.scene.vibrationPlayback?.factor(at: ProcessInfo.processInfo.systemUptime) == -1, "Negative maximum not rendered")
            try button("vibration-vectors").performClick(nil); await pause()
            try require(!view.scene.showDisplacementVectors, "Vectors did not hide")
            try require(workspace.currentFrame == original && workspace.selectedMode == mode && workspace.sourceText == text, "Source calculation changed")
            workspace.selectMode(6); await pause()
            try require(workspace.vibrationPlayback.factor(at: ProcessInfo.processInfo.systemUptime) == 0, "New mode inherited frozen displacement")
            workspace.selectFrame(0); await pause()
            try require(workspace.selectedMode == nil && !workspace.canDisplaceMode, "Frame switch retained mode controls")
            print("VIBRATION_PASS: native vectors/freeze/resume/both extrema; visible arrows in every style; independent signed XYZ coordinates; energy cleared; unchanged source and mode reset.")
            fflush(stdout); exit(0)
        } catch { print("VIBRATION_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
