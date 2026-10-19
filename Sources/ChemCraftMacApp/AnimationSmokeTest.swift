import AppKit
import ChemCraftCore
import ImageIO

@MainActor enum AnimationSmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            func require(_ ok: Bool, _ message: String) throws { if !ok { throw AnimationExportError.message(message) } }
            let args = CommandLine.arguments
            let folder = args.firstIndex(of: "--animation-evidence").map { URL(fileURLWithPath: args[$0 + 1]) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-animation-test")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("trajectory.xyz")
            try "3\nE=-1 Eh\nO 0 0 0\nH 0.9 0 0\nH 0 0.9 0\n3\nE=-2 Eh\nO 0 0 0\nH 1.4 0 0\nH 0 0.9 0\n3\nE=-3 Eh\nO 0 0 0\nH 1.8 0 0\nH 0 0.9 0\n".write(to: url, atomically: true, encoding: .utf8)
            try require(MolecularStyle.paton.shaderStyle == 2 && MolecularStyle.publication.shaderStyle == 1 && MolecularStyle.soft.shaderStyle == 0, "Incorrect appearance shader mode")
            try require(workspace.renderingStyle == .paton, "Default appearance must be Paton")
            workspace.open(url)
            for _ in 0..<200 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 25_000_000) }
            try await Task.sleep(nanoseconds: 400_000_000)
            guard let view = AnimationExporter.viewport(), let frames = workspace.document?.frames else { throw AnimationExportError.message("Viewport unavailable") }
            // Exercise a non-default camera through the actual mouse handler.
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 500, y: 300), modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 620, y: 340), modifierFlags: [], timestamp: 0.1, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            view.mouseDown(with: down); view.mouseDragged(with: drag); view.mouseUp(with: drag)
            let exportedCamera = view.animationRenderer(frames: frames)
            try require(view.viewingRotation == exportedCamera.viewingRotation, "GIF changed the user camera angle")
            let secondCamera = exportedCamera.animationRenderer(frames: frames)
            try require(secondCamera.viewingRotation == view.viewingRotation, "Final export renderer reset the camera")
            try require(PatonAppearance.colors["C"] == 0xD9D9D9 && PatonAppearance.colors["N"] == 0x7F7FBF && PatonAppearance.colors["H"] == 0xFAFAFA && PatonAppearance.colors["O"] == 0xFF0D0D, "Paton palette mismatch")
            let originalCamera = view.viewingRotation
            let original = view.scene.atoms
            try require(frames.count == 3, "Expected three loaded trajectory frames, got \(frames.count)")
            let originalFrameIndex = workspace.frameIndex
            let animation = MolecularAnimation(frames: frames, mode: nil, amplitude: 0, samples: 48, pingPong: true)
            try require(animation.count == 4 && animation.sample(3).0 == frames[1], "Ping-pong frame ordering")
            func validate(_ url: URL, count: Int, delay: Double = 0.1) throws {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw AnimationExportError.message("GIF cannot be reopened") }
                try require(CGImageSourceGetCount(source) == count, "Wrong GIF frame count")
                let first = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                try require(first.width == 256 && first.height == 256, "Wrong GIF dimensions")
                let dictionary = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
                let gif = dictionary[kCGImagePropertyGIFDictionary] as! NSDictionary
                try require(abs((gif[kCGImagePropertyGIFUnclampedDelayTime] as! NSNumber).doubleValue - delay) < 0.001, "GIF delay")
                let global = CGImageSourceCopyProperties(source, nil)! as NSDictionary
                try require(((global[kCGImagePropertyGIFDictionary] as? NSDictionary)?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0, "GIF must loop")
                let last = CGImageSourceCreateImageAtIndex(source, count / 4, nil)!
                try require(first.dataProvider!.data! as Data != last.dataProvider!.data! as Data, "GIF frames are static")
            }
            let trajectory = folder.appendingPathComponent("trajectory.gif")
            try await AnimationExporter.export(animation, from: view, style: .paton, size: 256, fps: 10, to: trajectory) { _ in }
            try validate(trajectory, count: 4)
            let mode = VibrationalMode(index: 1, frequencyCM1: -150, displacements: [Vector3(0, 0, 0), Vector3(0.7, 0, 0), Vector3(0, -0.5, 0)])
            let vibration = MolecularAnimation(frames: [frames[0]], mode: mode, amplitude: 0.6, samples: 12, pingPong: false)
            try require(abs(vibration.sample(3).1[1].x - 1.32) < 1e-5 && abs(vibration.sample(9).1[1].x - 0.48) < 1e-5, "Sinusoidal displacement amplitude")
            let frequency = folder.appendingPathComponent("frequency.gif")
            try await AnimationExporter.export(vibration, from: view, style: .paton, size: 256, fps: 10, to: frequency) { _ in }
            try validate(frequency, count: 12)
            let labeled = folder.appendingPathComponent("frequency-labeled-slow.gif")
            try await AnimationExporter.export(vibration, from: view, style: .paton, size: 256, fps: 10, to: labeled, playbackSpeed: 0.25, measurementIndices: [0, 1]) { _ in }
            try validate(labeled, count: 12, delay: 0.4)
            let labelRenderer = view.animationRenderer(frames: vibration.frames, amplitude: vibration.amplitude, displacements: mode.displacements)
            let atRest = vibration.sample(0), atPeak = vibration.sample(3)
            let restLabel = labelRenderer.animationAnnotation(positions: atRest.1, indices: [0, 1], size: 256)
            let peakLabel = labelRenderer.animationAnnotation(positions: atPeak.1, indices: [0, 1], size: 256)
            try require(abs((restLabel?.value ?? 0) - 0.9) < 1e-5 && abs((peakLabel?.value ?? 0) - 1.32) < 1e-5, "Animated length label did not track displaced coordinates")
            let labeledSource = CGImageSourceCreateWithURL(labeled as CFURL, nil)!
            let bitmap = NSBitmapImageRep(cgImage: CGImageSourceCreateImageAtIndex(labeledSource, 0, nil)!)
            var teal = 0
            for y in stride(from: 0, to: 256, by: 2) { for x in stride(from: 0, to: 256, by: 2) {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.greenComponent > c.redComponent + 0.15, c.blueComponent > c.redComponent + 0.1 { teal += 1 }
            } }
            try require(teal > 10, "Measurement guides missing from encoded GIF")
            let measurementFrame = MoleculeFrame(id: 99, atoms: [Atom(id: 0, element: "C", position: Vector3(0, 1, 0)), Atom(id: 1, element: "C", position: Vector3(0, 0, 0)), Atom(id: 2, element: "C", position: Vector3(1, 0, 0)), Atom(id: 3, element: "C", position: Vector3(1, 0, 1))])
            let positions = measurementFrame.atoms.map { SIMD3($0.position.x, $0.position.y, $0.position.z) }
            let measurementRenderer = view.animationRenderer(frames: [measurementFrame])
            for indices in [[0, 1], [0, 1, 2], [0, 1, 2, 3]] {
                let annotation = measurementRenderer.animationAnnotation(positions: positions, indices: indices, size: 256)
                let expected: Float = indices.count == 2 ? 1 : 90
                try require(abs(abs(annotation?.value ?? 0) - expected) < 1e-4, "Wrong exported measurement value")
                let image = try measurementRenderer.renderAnimationFrame(measurementFrame, positions: positions, size: 256, measurementIndices: indices)
                let target = folder.appendingPathComponent("measurement-\(indices.count).png")
                let png = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(png, image, nil); try require(CGImageDestinationFinalize(png), "Measurement PNG failed")
            }
            for style in MolecularStyle.allCases {
                let renderer = view.animationRenderer(frames: [frames[0]])
                renderer.scene.style = style
                let sample = vibration.sample(0)
                let image = try renderer.renderAnimationFrame(sample.0, positions: sample.1, size: 256)
                let target = folder.appendingPathComponent("style-\(style == .paton ? "paton" : style.rawValue).png")
                let png = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(png, image, nil); try require(CGImageDestinationFinalize(png), "Style PNG")
            }
            try require(view.viewingRotation == originalCamera && view.scene.atoms == original && workspace.frameIndex == originalFrameIndex, "GIF export changed the visible document")
            let cancelURL = folder.appendingPathComponent("cancelled.gif")
            try Data("existing".utf8).write(to: cancelURL)
            var renderedFirstFrame = false
            let task = Task { try await AnimationExporter.export(vibration, from: view, style: .paton, size: 256, fps: 10, to: cancelURL) { _ in renderedFirstFrame = true } }
            for _ in 0..<1000 { if renderedFirstFrame { break }; try await Task.sleep(nanoseconds: 1_000_000) }
            task.cancel()
            do { try await task.value; throw AnimationExportError.message("Cancellation ignored") } catch is CancellationError {}
            try require(try Data(contentsOf: cancelURL) == Data("existing".utf8), "Cancellation replaced existing file")
            workspace.isAnimationExportPresented = true
            try await Task.sleep(nanoseconds: 400_000_000)
            try require(NSApp.windows.contains { $0.sheetParent != nil }, "GIF export sheet did not present")
            if args.contains("--capture-window"), let window = view.window {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-l", String(window.windowNumber), folder.appendingPathComponent("gif-export-window.png").path]
                try process.run(); process.waitUntilExit()
            }
            workspace.isAnimationExportPresented = false
            print("ANIMATION_SMOKE_PASS: Paton default, all styles, trajectory/ping-pong, signed frequency sinusoid, GIF counts/size/delay/loop/nonstatic, document preservation, cancellation, animated length/angle/dihedral guides and quarter-speed timing")
            exit(0)
        } catch { fputs("ANIMATION_SMOKE_FAIL: \(error)\n", stderr); exit(1) }
    }
}
