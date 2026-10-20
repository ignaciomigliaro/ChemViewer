import ChemCraftCore
import MetalKit
import SwiftUI

enum MolecularStyle: String, CaseIterable {
    case paton = "xyzrender · Paton"
    case publication = "Publication"
    case soft = "Soft spheres"
    case spaceFilling = "Large spheres"
    case sticks = "Sticks"

    var shaderStyle: Float { self == .paton ? 2 : (self == .publication ? 1 : 0) }
}

struct MoleculeMetalView: NSViewRepresentable {
    let frame: MoleculeFrame
    let mode: VibrationalMode?
    let isAnimating: Bool
    let amplitude: Float
    let showDisplacementVectors: Bool
    var style: MolecularStyle = .paton
    var showHydrogens = true
    var atomCaption: AtomCaption = .none
    var vibrationSpeed: Float = 0.48
    @Binding var selectedAtomIndices: [Int]
    var showMeasurementOverlay = false
    var measurementSelections: [[Int]] = []
    var draggingEnabled = false
    var dragAxis: DragAxis = .screen
    var onEmptyBuilderClick: (Vector3) -> Bool = { _ in false }
    var onBuilderClick: (Int) -> Bool = { _ in false }
    var onClearSelection: () -> Void = {}
    var onManipulationSelection: (Int) -> Void = { _ in }
    var onBeginAtomDrag: (Int) -> Bool = { _ in false }
    var onDragAtomIndices: () -> [Int] = { [] }
    var onPreviewAtomDrag: (Vector3) -> Void = { _ in }
    var onFinishAtomDrag: () -> Void = {}
    var onRenderingFailure: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MolecularMTKView {
        let view = MolecularMTKView()
        view.onAtomClick = { [weak view] index, extendSelection in
            view?.preservePlacementCamera = true
            if context.coordinator.parent.onBuilderClick(index) { return }
            view?.preservePlacementCamera = false
            if context.coordinator.parent.draggingEnabled { context.coordinator.parent.onManipulationSelection(index) }
            else { context.coordinator.selectAtom(index, extendSelection: extendSelection) }
        }
        view.onEmptyClick = { [weak view] location in
            view?.preservePlacementCamera = true
            if !context.coordinator.parent.onEmptyBuilderClick(location) { view?.preservePlacementCamera = false }
        }
        view.onClearSelection = { context.coordinator.parent.selectedAtomIndices = []; context.coordinator.parent.onClearSelection() }
        view.onBeginAtomDrag = { context.coordinator.parent.onBeginAtomDrag($0) }
        view.onDragAtomIndices = { context.coordinator.parent.onDragAtomIndices() }
        view.onPreviewAtomDrag = { context.coordinator.parent.onPreviewAtomDrag($0) }
        view.onFinishAtomDrag = { context.coordinator.parent.onFinishAtomDrag() }
        view.onRenderingFailure = { error in context.coordinator.parent.onRenderingFailure(error) }
        if let failure = view.renderingFailure { DispatchQueue.main.async { context.coordinator.parent.onRenderingFailure(failure) } }
        return view
    }

    func updateNSView(_ view: MolecularMTKView, context: Context) {
        context.coordinator.parent = self
        view.showMeasurementOverlay = showMeasurementOverlay
        view.measurementSelections = measurementSelections
        view.draggingEnabled = draggingEnabled
        view.dragAxis = dragAxis
        view.scene = RenderScene(
            atoms: frame.atoms,
            bonds: context.coordinator.bonds(for: frame.atoms),
            displacements: mode?.displacements ?? [],
            amplitude: amplitude,
            animate: isAnimating && mode != nil,
            showDisplacementVectors: showDisplacementVectors && mode != nil,
            selectedAtomIndices: selectedAtomIndices,
            style: style,
            showHydrogens: showHydrogens, atomCaption: atomCaption, vibrationSpeed: vibrationSpeed,
            geometryID: frame.id
        )
    }

    final class Coordinator {
        var parent: MoleculeMetalView
        private var bondedAtoms: [Atom] = []
        private var cachedBonds: [Bond] = []
        func bonds(for atoms: [Atom]) -> [Bond] {
            if atoms != bondedAtoms { bondedAtoms = atoms; cachedBonds = BondBuilder.inferBonds(atoms: atoms) }
            return cachedBonds
        }

        init(parent: MoleculeMetalView) {
            self.parent = parent
        }

        func selectAtom(_ index: Int, extendSelection: Bool) {
            if let position = parent.selectedAtomIndices.firstIndex(of: index) {
                parent.selectedAtomIndices.remove(at: position)
            } else {
                parent.selectedAtomIndices.append(index)
            }
        }
    }
}

struct RenderScene {
    var atoms: [Atom]
    var bonds: [Bond]
    var displacements: [Vector3]
    var amplitude: Float
    var animate: Bool
    var showDisplacementVectors: Bool
    var selectedAtomIndices: [Int]
    var style: MolecularStyle = .paton
    var showHydrogens = true
    var atomCaption: AtomCaption = .none
    var vibrationSpeed: Float = 0.48
    var geometryID: Int = 0
}

private struct MetalVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var normal: SIMD3<Float>
}

private struct MetalInstance {
    var origin: SIMD4<Float>
    var x: SIMD4<Float>
    var y: SIMD4<Float>
    var z: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct MetalUniforms {
    var modelViewProjection: simd_float4x4
    var normalMatrix: simd_float4x4
    var style: SIMD4<Float>
}

final class MolecularMTKView: MTKView, MTKViewDelegate {
    var scene = RenderScene(
        atoms: [], bonds: [], displacements: [], amplitude: 0.6,
        animate: false, showDisplacementVectors: false, selectedAtomIndices: []
    ) {
        didSet {
            if scene.atoms.count != oldValue.atoms.count { measurementOffsets.removeAll() }
            if !atomDragActive { dragPreviewPositions = nil }
            if atomDragActive && (scene.selectedAtomIndices.isEmpty || !draggingEnabled || scene.geometryID != oldValue.geometryID) {
                atomDragActive = false; dragPreviewPositions = nil
            }
            if scene.atoms != oldValue.atoms || scene.displacements != oldValue.displacements {
                animationElapsed = 0; animationStart = CACurrentMediaTime()
            } else if oldValue.animate && !scene.animate {
                animationElapsed = CACurrentMediaTime() - animationStart
            } else if !oldValue.animate && scene.animate {
                animationStart = CACurrentMediaTime() - animationElapsed
            }
            let preservingInsertion = preservePlacementCamera && scene.geometryID == oldValue.geometryID
            if preservingInsertion && scene.atoms != oldValue.atoms {
                rebaseOrbitCenter()
            } else if !preservingInsertion && (oldValue.atoms.isEmpty || scene.geometryID != oldValue.geometryID || scene.atoms.count != oldValue.atoms.count || scene.style != oldValue.style) {
                recalculateBounds()
            }
            if scene.atoms != oldValue.atoms || scene.geometryID != oldValue.geometryID { preservePlacementCamera = false }
            enableSetNeedsDisplay = !scene.animate && !atomDragActive
            isPaused = !scene.animate && !atomDragActive
            setNeedsDisplay(bounds)
        }
    }

    private(set) var shaderBundlePath: String?
    private(set) var renderingFailure: String?
    private(set) var completedFrameCount = 0
    var onRenderingFailure: ((String) -> Void)?
    var renderingReady: Bool { commandQueue != nil && atomPipeline != nil && bondPipeline != nil && sphereMesh != nil && cylinderMesh != nil }
    private var commandQueue: MTLCommandQueue!
    private var atomPipeline: MTLRenderPipelineState!
    private var bondPipeline: MTLRenderPipelineState!
    let measurementOverlay = MeasurementOverlayView()
    var showMeasurementOverlay = false
    var measurementSelections: [[Int]] = []
    private var measurementOffsets: [String: CGPoint] = [:]
    private func measurementKey(_ indices: [Int]) -> String { "\(scene.geometryID):" + measurementIdentity(indices) }
    private var sphereMesh: MTLBuffer?
    private var cylinderMesh: MTLBuffer?
    private var sphereVertexCount = 0
    private var cylinderVertexCount = 0
    private(set) var meshBuildCount = 0
    private var depthState: MTLDepthStencilState?
    private var captureURL: URL?
    private var cameraObserver: NSObjectProtocol?
    private var center = SIMD3<Float>(repeating: 0)
    private var animationStart = CACurrentMediaTime()
    private var animationElapsed: Double = 0
    private var fitScale: Float = 0.12
    var preservePlacementCamera = false
    private var roll: Float = 0
    private var yaw: Float = 0.45
    private var pitch: Float = -0.30
    private var zoom: Float = 1
    private var pan = SIMD2<Float>(repeating: 0)
    var draggingEnabled = false
    var dragAxis: DragAxis = .screen
    var onClearSelection: (() -> Void)?
    var onBeginAtomDrag: ((Int) -> Bool)?
    var onDragAtomIndices: (() -> [Int])?
    private var dragBasePositions: [SIMD3<Float>] = []
    private var dragPreviewPositions: [SIMD3<Float>]?
    private var activeDragIndices: [Int] = []
    private var pendingDragDelta = Vector3.zero
    var onPreviewAtomDrag: ((Vector3) -> Void)?
    var onFinishAtomDrag: (() -> Void)?
    private var pressedAtom: Int?
    private var atomDragActive = false
    private var dragAttempted = false
    private var dragUnitsPerPoint: Float = 1
    private var dragInverseRotation = matrix_identity_float4x4
    private var previousMouse = CGPoint.zero
    private var mouseDownPoint = CGPoint.zero
    private var didDrag = false
    var onAtomClick: ((Int, Bool) -> Void)?
    var onEmptyClick: ((Vector3) -> Void)?

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        guard let device = metalDevice else { renderingFailure = "Metal is unavailable on this Mac."; return }
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        depthStencilPixelFormat = .depth32Float
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)
        preferredFramesPerSecond = 120
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = false
        commandQueue = device.makeCommandQueue()
        buildPipelines(device: device)
        buildMeshes(device: device)
        delegate = self
        measurementOverlay.frame = bounds
        measurementOverlay.autoresizingMask = [.width, .height]
        addSubview(measurementOverlay)
        measurementOverlay.onMoveLabel = { [weak self] annotation in
            guard let self else { return }
            self.measurementOffsets[self.measurementKey(annotation.atomIndices)] = annotation.labelOffset
            self.setNeedsDisplay(self.bounds)
        }
        cameraObserver = NotificationCenter.default.addObserver(forName: .init("ChemViewerViewportAction"), object: nil, queue: .main) { [weak self] note in
            guard let self, self.window != nil, let action = note.object as? String else { return }
            switch action {
            case "reset": self.recalculateBounds(); self.yaw = 0.45; self.pitch = -0.30; self.roll = 0; self.zoom = 1; self.pan = .zero
            case "front": self.recalculateBounds(); self.yaw = 0; self.pitch = 0; self.roll = 0; self.zoom = 1; self.pan = .zero
            case "left": self.yaw += .pi / 12
            case "right": self.yaw -= .pi / 12
            case "up": self.pitch += .pi / 12
            case "down": self.pitch -= .pi / 12
            case "rollLeft": self.roll += .pi / 12
            case "rollRight": self.roll -= .pi / 12
            case "panUp": self.pan.y += 0.08
            case "panDown": self.pan.y -= 0.08
            case "in": self.zoomBy(factor: 1.2, at: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
            case "out": self.zoomBy(factor: 1 / 1.2, at: CGPoint(x: self.bounds.midX, y: self.bounds.midY))
            case "resetLabel":
                self.measurementOffsets.removeValue(forKey: self.measurementKey(self.scene.selectedAtomIndices))
            case "export":
                let panel = NSSavePanel(); panel.nameFieldStringValue = "molecule.png"
                panel.allowedContentTypes = [.png]
                if panel.runModal() == .OK, let url = panel.url { self.captureURL = url }
            default: break
            }
            self.setNeedsDisplay(self.bounds)
        }
    }

    deinit { if let cameraObserver { NotificationCenter.default.removeObserver(cameraObserver) } }

    func capture(to url: URL) { captureURL = url; draw() }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func buildPipelines(device: MTLDevice) {
        let packagedBundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("ChemViewer_ChemViewerApp.bundle")
        let shaderBundle = packagedBundleURL.flatMap(Bundle.init(url:)) ?? .module
        shaderBundlePath = shaderBundle.bundlePath
        let library: MTLLibrary?
        if let compiledLibrary = try? device.makeDefaultLibrary(bundle: shaderBundle) {
            library = compiledLibrary
        } else if let sourceURL = shaderBundle.url(forResource: "MoleculeShaders", withExtension: "metal"),
                  let source = try? String(contentsOf: sourceURL, encoding: .utf8) {
            library = try? device.makeLibrary(source: source, options: nil)
        } else {
            library = nil
        }
        guard let library else { renderingFailure = "Could not load or compile ChemViewer’s bundled Metal shaders."; return }

        let atomDescriptor = MTLRenderPipelineDescriptor()
        atomDescriptor.label = "Atom impostors"
        atomDescriptor.vertexFunction = library.makeFunction(name: "atomVertex")
        atomDescriptor.fragmentFunction = library.makeFunction(name: "atomFragment")
        atomDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        atomDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        atomDescriptor.rasterSampleCount = sampleCount
        atomPipeline = try? device.makeRenderPipelineState(descriptor: atomDescriptor)

        let bondDescriptor = MTLRenderPipelineDescriptor()
        bondDescriptor.label = "Bond lines"
        bondDescriptor.vertexFunction = library.makeFunction(name: "bondVertex")
        bondDescriptor.fragmentFunction = library.makeFunction(name: "bondFragment")
        bondDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        bondDescriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        bondDescriptor.rasterSampleCount = sampleCount
        bondPipeline = try? device.makeRenderPipelineState(descriptor: bondDescriptor)
        if atomPipeline == nil || bondPipeline == nil { renderingFailure = "Could not create ChemViewer’s Metal render pipelines." }
    }

    private func buildMeshes(device: MTLDevice) {
        var sphere: [MetalVertex] = [], cylinder: [MetalVertex] = []
        appendSphere(at: .zero, radius: 1, color: SIMD4(1, 1, 1, 1), into: &sphere)
        appendCylinder(from: .zero, to: SIMD3(0, 0, 1), radius: 1, color: SIMD4(1, 1, 1, 1), into: &cylinder)
        sphereMesh = device.makeBuffer(bytes: sphere, length: MemoryLayout<MetalVertex>.stride * sphere.count)
        cylinderMesh = device.makeBuffer(bytes: cylinder, length: MemoryLayout<MetalVertex>.stride * cylinder.count)
        sphereVertexCount = sphere.count; cylinderVertexCount = cylinder.count; meshBuildCount += 1
    }

    /// Move the orbit pivot to the structure without moving its rendered pixels.
    private func rebaseOrbitCenter() {
        guard !scene.atoms.isEmpty else { return }
        let next = scene.atoms.reduce(SIMD3<Float>(repeating: 0)) { $0 + SIMD3($1.position.x, $1.position.y, $1.position.z) } / Float(scene.atoms.count)
        let delta = next - center
        let rotated = cameraRotation() * SIMD4(delta.x, delta.y, delta.z, 0)
        let aspect = max(Float(bounds.width), 1) / max(Float(bounds.height), 1)
        let scale = fitScale * zoom * min(1, aspect)
        pan.x += rotated.x * scale / aspect
        pan.y += rotated.y * scale
        center = next
    }

    private func recalculateBounds() {
        guard !scene.atoms.isEmpty else { center = .zero; fitScale = 0.12; return }
        let sum = scene.atoms.reduce(SIMD3<Float>(repeating: 0)) {
            $0 + SIMD3($1.position.x, $1.position.y, $1.position.z)
        }
        center = sum / Float(scene.atoms.count)
        let maximum = scene.atoms.map {
            simd_length(SIMD3($0.position.x, $0.position.y, $0.position.z) - center)
        }.max() ?? 1
        let margin = scene.atoms.map(atomRadius).max() ?? 0.4
        fitScale = 0.88 / max(maximum + margin, 0.8)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass),
              atomPipeline != nil,
              bondPipeline != nil else { return }

        let positions = displacedPositions()
        measurementOverlay.captions = captionAnnotations(positions: positions, size: bounds.size)
        var selections = measurementSelections
        if showMeasurementOverlay && !selections.contains(where: { measurementIdentity($0) == measurementIdentity(scene.selectedAtomIndices) }) { selections.insert(scene.selectedAtomIndices, at: 0) }
        var annotations: [MeasurementAnnotation] = []
        for indices in selections {
            guard var annotation = MeasurementAnnotation.make(positions: positions, indices: indices, project: { self.projectPosition(positions[$0]) }) else { continue }
            let key = measurementKey(indices)
            annotation.labelOffset = measurementOffsets[key] ?? .zero
            if annotation.labelOffset == .zero && annotations.contains(where: { $0.labelRect(in: bounds).insetBy(dx: -3, dy: -3).intersects(annotation.labelRect(in: bounds)) }) {
                for row in 1...16 {
                    let direction: CGFloat = row % 2 == 1 ? 1 : -1
                    annotation.labelOffset.y = direction * CGFloat((row + 1) / 2) * (annotation.labelRect(in: bounds).height + 8) / max(bounds.height, 1)
                    if !annotations.contains(where: { $0.labelRect(in: bounds).insetBy(dx: -3, dy: -3).intersects(annotation.labelRect(in: bounds)) }) { break }
                }
                measurementOffsets[key] = annotation.labelOffset
            }
            annotations.append(annotation)
        }
        measurementOverlay.annotations = annotations
        encodeMolecule(encoder, positions: positions, size: drawableSize)
        if let url = captureURL {
            captureURL = nil
            let texture = drawable.texture
            let rowBytes = ((texture.width * 4 + 255) / 256) * 256
            if let pixels = device?.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared), let blit = commandBuffer.makeBlitCommandEncoder() {
                blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(), sourceSize: .init(width: texture.width, height: texture.height, depth: 1), to: pixels, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * texture.height)
                blit.endEncoding()
                let annotations = measurementOverlay.annotations
                let captions = measurementOverlay.captions
                let overlaySize = bounds.size
                commandBuffer.addCompletedHandler { [weak self] buffer in
                    guard buffer.status == .completed else { return }
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: texture.width, pixelsHigh: texture.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: rowBytes, bitsPerPixel: 32)!
                    let source = pixels.contents().assumingMemoryBound(to: UInt8.self)
                    let target = bitmap.bitmapData!
                    for y in 0..<texture.height { for x in 0..<texture.width {
                        let i = y * rowBytes + x * 4
                        target[i] = source[i + 2]; target[i + 1] = source[i + 1]; target[i + 2] = source[i]; target[i + 3] = 255
                    } }
                    if (!annotations.isEmpty || !captions.isEmpty), let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = context
                        context.cgContext.scaleBy(x: CGFloat(texture.width) / max(overlaySize.width, 1), y: CGFloat(texture.height) / max(overlaySize.height, 1))
                        for caption in captions { caption.draw() }
                        for annotation in annotations { annotation.draw(in: CGRect(origin: .zero, size: overlaySize)) }
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    do { try bitmap.representation(using: .png, properties: [:])?.write(to: url) }
                    catch { DispatchQueue.main.async { self?.onRenderingFailure?(error.localizedDescription) } }
                }
            }
        }
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let failure = buffer.error?.localizedDescription
            let completed = buffer.status == .completed
            DispatchQueue.main.async {
                if completed { self?.completedFrameCount += 1 }
                else if let failure { self?.renderingFailure = failure; self?.onRenderingFailure?(failure) }
            }
        }
        commandBuffer.commit()
    }

    private func encodeMolecule(_ encoder: MTLRenderCommandEncoder, positions: [SIMD3<Float>], size: CGSize) {
        // Distance-independent shading in the viewer and all exports.
        var atomInstances: [MetalInstance] = []
        atomInstances.reserveCapacity(scene.atoms.count)
        let selected = Set(scene.selectedAtomIndices)
        for (index, atom) in scene.atoms.enumerated() where scene.showHydrogens || atom.element != "H" {
            let base = ElementTable.color(for: atom.element)
            // xyzrender paton-inspired pale C/H/N palette; all source atoms stay visible.
            var color = SIMD4<Float>(base.0, base.1, base.2, 1)
            if atom.element == "C" { color = scene.style == .publication ? SIMD4(0.667, 0.667, 0.667, 1) : SIMD4(217.0/255, 217.0/255, 217.0/255, 1) }
            if atom.element == "H" { color = SIMD4(250.0/255, 250.0/255, 250.0/255, 1) }
            if atom.element == "N" && scene.style != .publication { color = SIMD4(127.0/255, 127.0/255, 191.0/255, 1) }
            if scene.style == .paton { color = PatonAppearance.color(for: atom.element) }
            if selected.contains(index) { color = SIMD4(1, 0.68, 0.12, 1) }
            for channel in 0..<3 {
                let c = color[channel]
                color[channel] = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            color.w = 0
            let radius = atomRadius(atom)
            atomInstances.append(MetalInstance(origin: SIMD4(positions[index], 1), x: SIMD4(radius, 0, 0, 0), y: SIMD4(0, radius, 0, 0), z: SIMD4(0, 0, radius, 0), color: color))
        }
        var bondInstances: [MetalInstance] = []
        let bondColor = (scene.style == .publication || scene.style == .paton) ? SIMD4<Float>(0.008, 0.008, 0.008, 1) : SIMD4<Float>(0.08, 0.08, 0.08, 1)
        for bond in scene.bonds where scene.style != .spaceFilling && positions.indices.contains(bond.first) && positions.indices.contains(bond.second) {
            if !scene.showHydrogens && (scene.atoms[bond.first].element == "H" || scene.atoms[bond.second].element == "H") { continue }
            var color = bondColor; color.w = 0
            appendCylinderInstance(from: positions[bond.first], to: positions[bond.second], radius: scene.style == .paton ? 0.07894737 : 0.085, color: color, into: &bondInstances)
        }
        if scene.showDisplacementVectors {
            let vectorColor = SIMD4<Float>(1.0, 0.62, 0.08, 1)
            for index in scene.atoms.indices where scene.displacements.indices.contains(index) && (scene.showHydrogens || scene.atoms[index].element != "H") {
                let origin = SIMD3(
                    scene.atoms[index].position.x,
                    scene.atoms[index].position.y,
                    scene.atoms[index].position.z
                )
                let displacement = scene.displacements[index]
                let delta = SIMD3(displacement.x, displacement.y, displacement.z) * scene.amplitude * 5
                let magnitude = simd_length(delta)
                guard magnitude > 1e-6 else { continue }
                let tip = origin + delta
                appendLine(from: origin, to: tip, color: vectorColor, into: &bondInstances)

                let direction = delta / magnitude
                let reference = abs(direction.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                let side = simd_normalize(simd_cross(direction, reference))
                let headLength = min(magnitude * 0.28, 0.18 / max(fitScale, 0.01))
                let headWidth = headLength * 0.45
                let base = tip - direction * headLength
                appendLine(from: tip, to: base + side * headWidth, color: vectorColor, into: &bondInstances)
                appendLine(from: tip, to: base - side * headWidth, color: vectorColor, into: &bondInstances)
            }
        }

        var uniforms = MetalUniforms(modelViewProjection: makeMVP(size: size), normalMatrix: cameraRotation(), style: SIMD4(scene.style.shaderStyle, 0, 0, 0))
        encoder.setDepthStencilState(depthState)
        if !bondInstances.isEmpty, let mesh = cylinderMesh,
           let buffer = device?.makeBuffer(bytes: bondInstances, length: MemoryLayout<MetalInstance>.stride * bondInstances.count) {
            encoder.setRenderPipelineState(bondPipeline)
            encoder.setVertexBuffer(mesh, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
            encoder.setVertexBuffer(buffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cylinderVertexCount, instanceCount: bondInstances.count)
        }
        if !atomInstances.isEmpty, let mesh = sphereMesh,
           let buffer = device?.makeBuffer(bytes: atomInstances, length: MemoryLayout<MetalInstance>.stride * atomInstances.count) {
            encoder.setRenderPipelineState(atomPipeline)
            encoder.setVertexBuffer(mesh, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
            encoder.setVertexBuffer(buffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: sphereVertexCount, instanceCount: atomInstances.count)
        }
        encoder.endEncoding()
    }

    /// Separate render targets: GIF creation never changes the visible scene or playback.
    func animationRenderer(frames: [MoleculeFrame], amplitude: Float = 0, displacements: [Vector3] = []) -> MolecularMTKView {
        let renderer = MolecularMTKView()
        renderer.scene = scene
        renderer.measurementOffsets = measurementOffsets
        renderer.scene.animate = false
        renderer.scene.selectedAtomIndices = []
        renderer.scene.showDisplacementVectors = false
        renderer.yaw = yaw; renderer.pitch = pitch; renderer.roll = roll
        let points = frames.flatMap { frame in frame.atoms.enumerated().flatMap { i, atom -> [SIMD3<Float>] in
            let p = SIMD3(atom.position.x, atom.position.y, atom.position.z)
            guard displacements.indices.contains(i) else { return [p] }
            let d = displacements[i]; let delta = SIMD3(d.x, d.y, d.z) * amplitude
            return [p - delta, p + delta]
        } }
        if let first = points.first {
            var low = first, high = first
            for p in points { low = simd_min(low, p); high = simd_max(high, p) }
            renderer.center = (low + high) / 2
            let radius = points.map { simd_length($0 - renderer.center) }.max() ?? 1
            let margin = frames.flatMap(\.atoms).map(renderer.atomRadius).max() ?? 0.5
            renderer.fitScale = 0.88 / max(radius + margin, 0.8)
        }
        return renderer
    }

    func renderAnimationFrame(_ frame: MoleculeFrame, positions: [SIMD3<Float>], size: Int, measurementIndices: [Int] = [], measurementSelections: [[Int]] = [], transparentBackground: Bool = false) throws -> CGImage {
        guard size >= 128, size <= 2048, positions.count == frame.atoms.count, renderingReady,
              let device, let command = commandQueue.makeCommandBuffer() else {
            throw AnimationExportError.message("The Metal renderer is unavailable or the frame is invalid.")
        }
        // Assign fields directly to retain the fixed camera fitted across the entire animation.
        // scene didSet may refit for a changed atom count, so restore framing afterward.
        let fixedCenter = center, fixedScale = fitScale
        scene.atoms = frame.atoms; scene.bonds = BondBuilder.inferBonds(atoms: frame.atoms)
        center = fixedCenter; fitScale = fixedScale
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorPixelFormat, width: size, height: size, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: descriptor) else { throw AnimationExportError.message("Cannot allocate GIF render texture.") }
        descriptor.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
        descriptor.sampleCount = sampleCount
        let multisample = sampleCount > 1 ? device.makeTexture(descriptor: descriptor) : nil
        descriptor.pixelFormat = depthStencilPixelFormat; descriptor.usage = .renderTarget
        guard let depth = device.makeTexture(descriptor: descriptor) else { throw AnimationExportError.message("Cannot allocate GIF depth texture.") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample ?? color
        pass.colorAttachments[0].resolveTexture = multisample == nil ? nil : color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = multisample == nil ? .store : .multisampleResolve
        pass.colorAttachments[0].clearColor = transparentBackground ? MTLClearColorMake(0, 0, 0, 0) : MTLClearColorMake(1, 1, 1, 1)
        pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.clearDepth = 1
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw AnimationExportError.message("Cannot encode GIF frame.") }
        encodeMolecule(encoder, positions: positions, size: CGSize(width: size, height: size))
        let rowBytes = ((size * 4 + 255) / 256) * 256
        guard let buffer = device.makeBuffer(length: rowBytes * size, options: .storageModeShared),
              let blit = command.makeBlitCommandEncoder() else { throw AnimationExportError.message("Cannot read GIF frame.") }
        blit.copy(from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(), sourceSize: .init(width: size, height: size, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * size)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        let source = buffer.contents().assumingMemoryBound(to: UInt8.self)
        var rgba = Data(count: rowBytes * size)
        rgba.withUnsafeMutableBytes { raw in
            let target = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: rowBytes * size, by: 4) {
                let alpha = transparentBackground ? source[i + 3] : 255
                target[i + 3] = alpha
                for channel in 0..<3 {
                    let component = source[i + 2 - channel]
                    if alpha == 0 { target[i + channel] = 0 }
                    else if alpha == 255 { target[i + channel] = component }
                    else {
                        // MSAA coverage is premultiplied in linear space before sRGB encoding.
                        let encoded = Float(component) / 255
                        let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                        let straight = min(1, linear / (Float(alpha) / 255))
                        let color = straight <= 0.0031308 ? straight * 12.92 : 1.055 * pow(straight, 1 / 2.4) - 0.055
                        target[i + channel] = UInt8(clamping: Int((color * 255).rounded()))
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw AnimationExportError.message("Cannot create GIF image.") }
        let captions = captionAnnotations(positions: positions, size: CGSize(width: size, height: size))
        let selections = measurementSelections + (measurementIndices.isEmpty ? [] : [measurementIndices])
        guard !selections.isEmpty || !captions.isEmpty else { return image }
        let annotations = selections.compactMap { animationAnnotation(positions: positions, indices: $0, size: size) }
        if annotations.count != selections.count {
            throw AnimationExportError.message("The selected measurement is undefined in a frame (coincident atoms or a collinear dihedral). Export without the label or choose different atoms.")
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw AnimationExportError.message("Cannot draw the GIF measurement label.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        for caption in captions { caption.draw() }
        for annotation in annotations { annotation.draw(in: CGRect(x: 0, y: 0, width: size, height: size), background: !transparentBackground) }
        NSGraphicsContext.restoreGraphicsState()
        guard let annotated = bitmap.cgImage else { throw AnimationExportError.message("Cannot finish the GIF measurement label.") }
        return annotated
    }

    private func captionAnnotations(positions: [SIMD3<Float>], size: CGSize) -> [AtomCaptionAnnotation] {
        guard scene.atomCaption != .none else { return [] }
        let mvp = makeMVP(size: size)
        return scene.atoms.enumerated().compactMap { index, atom in
            guard positions.indices.contains(index), scene.showHydrogens || atom.element != "H" else { return nil }
            let clip = mvp * SIMD4(positions[index], 1)
            guard abs(clip.w) > 0.000001 else { return nil }
            return AtomCaptionAnnotation(point: CGPoint(x: CGFloat(clip.x / clip.w + 1) * size.width / 2, y: CGFloat(clip.y / clip.w + 1) * size.height / 2), label: scene.atomCaption.label(element: atom.element, index: index))
        }
    }

    func animationAnnotation(positions: [SIMD3<Float>], indices: [Int], size: Int) -> MeasurementAnnotation? {
        let mvp = makeMVP(size: CGSize(width: size, height: size))
        var annotation = MeasurementAnnotation.make(positions: positions, indices: indices) { index in
            let clip = mvp * SIMD4(positions[index], 1)
            guard abs(clip.w) > 0.000001 else { return nil }
            return CGPoint(x: CGFloat(clip.x / clip.w + 1) * CGFloat(size) / 2,
                           y: CGFloat(clip.y / clip.w + 1) * CGFloat(size) / 2)
        }
        annotation?.labelOffset = measurementOffsets[measurementKey(indices)] ?? .zero
        return annotation
    }

    private func atomRadius(_ atom: Atom) -> Float {
        switch scene.style {
        case .spaceFilling: return (ElementTable.covalentRadius(for: atom.element) + 0.7) * 0.8
        case .sticks: return 0.10
        case .paton:
            // xyzrender atom_scale 2.5 × radius_scale .075; hydrogen h_scale .6.
            let radii: [String: Float] = ["H": 1.2, "C": 1.7, "N": 1.55, "O": 1.52, "F": 1.47, "P": 1.8, "S": 1.8, "Cl": 1.75, "Br": 1.85, "I": 1.98]
            return (radii[atom.element] ?? 1.5) * 0.1875 * (atom.element == "H" ? 0.6 : 1)
        default: return atom.element == "H" ? 0.22 : min(0.50, 0.20 + ElementTable.covalentRadius(for: atom.element) * 0.22)
        }
    }

    private func appendSphere(at center: SIMD3<Float>, radius: Float, color: SIMD4<Float>, into vertices: inout [MetalVertex]) {
        let rings = 16, segments = 24
        func vertex(_ ring: Int, _ segment: Int) -> MetalVertex {
            let theta = Float(ring) * .pi / Float(rings)
            let phi = Float(segment) * 2 * .pi / Float(segments)
            let n = SIMD3<Float>(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
            return MetalVertex(position: center + n * radius, color: color, normal: n)
        }
        for r in 0..<rings { for j in 0..<segments {
            let a = vertex(r, j), b = vertex(r + 1, j), c = vertex(r + 1, j + 1), d = vertex(r, j + 1)
            vertices.append(contentsOf: [a, b, c, a, c, d])
        } }
    }

    private func appendCylinder(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, color: SIMD4<Float>, into vertices: inout [MetalVertex]) {
        let delta = end - start
        guard simd_length(delta) > 1e-6 else { return }
        let axis = simd_normalize(delta)
        let ref = abs(axis.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(axis, ref)), v = simd_cross(axis, u)
        for j in 0..<16 {
            func n(_ i: Int) -> SIMD3<Float> {
                let angle = Float(i) * 2 * .pi / 16
                return u * cos(angle) + v * sin(angle)
            }
            let n1 = n(j), n2 = n(j + 1)
            let a = MetalVertex(position: start + radius * n1, color: color, normal: n1)
            let b = MetalVertex(position: end + radius * n1, color: color, normal: n1)
            let c = MetalVertex(position: end + radius * n2, color: color, normal: n2)
            let d = MetalVertex(position: start + radius * n2, color: color, normal: n2)
            vertices.append(contentsOf: [a, b, c, a, c, d])
        }
    }

    private func appendCylinderInstance(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, color: SIMD4<Float>, into instances: inout [MetalInstance]) {
        let delta = end - start, length = simd_length(end - start)
        guard length > 1e-6 else { return }
        let axis = delta / length
        let ref = abs(axis.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let u = simd_normalize(simd_cross(axis, ref)), v = simd_cross(axis, u)
        instances.append(MetalInstance(origin: SIMD4(start, 1), x: SIMD4(u * radius, 0), y: SIMD4(v * radius, 0), z: SIMD4(delta, 0), color: color))
    }

    private func appendLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: SIMD4<Float>, into instances: inout [MetalInstance]) {
        appendCylinderInstance(from: start, to: end, radius: 0.025, color: color, into: &instances)
    }

    var viewingRotation: simd_float4x4 { cameraRotation() }

    private func cameraRotation() -> simd_float4x4 {
        simd_float4x4.rotation(radians: roll, axis: SIMD3(0, 0, 1)) *
        simd_float4x4.rotation(radians: pitch, axis: SIMD3(1, 0, 0)) *
            simd_float4x4.rotation(radians: yaw, axis: SIMD3(0, 1, 0))
    }

    private func displacedPositions() -> [SIMD3<Float>] {
        if let dragPreviewPositions { return dragPreviewPositions }
        let elapsed = scene.animate ? CACurrentMediaTime() - animationStart : animationElapsed
        let phase = Float(sin(elapsed * Double(scene.vibrationSpeed) * 2 * .pi))
        return scene.atoms.enumerated().map { index, atom in
            var value = SIMD3(atom.position.x, atom.position.y, atom.position.z)
            if scene.displacements.indices.contains(index) {
                let displacement = scene.displacements[index]
                value += SIMD3(displacement.x, displacement.y, displacement.z) * scene.amplitude * phase
            }
            return value
        }
    }

    private func makeMVP(size: CGSize? = nil) -> simd_float4x4 {
        let width = max(Float((size ?? drawableSize).width), 1)
        let height = max(Float((size ?? drawableSize).height), 1)
        let aspect = width / height
        let projection = simd_float4x4.orthographic(
            left: -aspect,
            right: aspect,
            bottom: -1,
            top: 1,
            near: -100,
            far: 100
        )
        let translation = simd_float4x4.translation(SIMD3(pan.x * aspect, pan.y, 0))
        let rotation = cameraRotation()
        let scale = simd_float4x4.scale(fitScale * zoom * min(1, aspect))
        return projection * translation * rotation * scale * simd_float4x4.translation(-center)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        previousMouse = convert(event.locationInWindow, from: nil)
        mouseDownPoint = previousMouse
        didDrag = false; atomDragActive = false; dragAttempted = false
        pressedAtom = atomIndex(at: previousMouse)
        let aspect = max(Float(bounds.width), 1) / max(Float(bounds.height), 1)
        dragUnitsPerPoint = 2 / max(Float(bounds.height) * fitScale * zoom * min(1, aspect), 1e-6)
        dragInverseRotation = cameraRotation().transpose
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let threshold: CGFloat = draggingEnabled && pressedAtom != nil ? 1 : 3
        didDrag = didDrag || hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > threshold
        if draggingEnabled, let seed = pressedAtom {
            if didDrag && !dragAttempted {
                dragAttempted = true
                atomDragActive = onBeginAtomDrag?(seed) ?? false
                if atomDragActive {
                    dragBasePositions = displacedPositions()
                    activeDragIndices = onDragAtomIndices?() ?? [seed]
                    pendingDragDelta = .zero
                    enableSetNeedsDisplay = false; isPaused = false
                }
            }
            if atomDragActive {
                let x = Float(point.x - mouseDownPoint.x) * dragUnitsPerPoint
                let y = Float(point.y - mouseDownPoint.y) * dragUnitsPerPoint
                var delta = dragInverseRotation * (event.modifierFlags.contains(.option) ? SIMD4<Float>(0, 0, -y, 0) : SIMD4<Float>(x, y, 0, 0))
                switch dragAxis {
                case .screen: break
                case .x: delta = SIMD4(x + y, 0, 0, 0)
                case .y: delta = SIMD4(0, x + y, 0, 0)
                case .z: delta = SIMD4(0, 0, x + y, 0)
                }
                pendingDragDelta = Vector3(delta.x, delta.y, delta.z)
                var preview = dragBasePositions
                for index in activeDragIndices where preview.indices.contains(index) { preview[index] += SIMD3(delta.x, delta.y, delta.z) }
                dragPreviewPositions = preview
                setNeedsDisplay(bounds)
            }
            return
        }
        // Small pointer jitter while clicking must not rotate or pan the camera.
        guard didDrag else { return }
        if event.modifierFlags.contains(.option) {
            pan.x += Float(point.x - previousMouse.x) / max(Float(bounds.width), 1) * 2
            pan.y += Float(point.y - previousMouse.y) / max(Float(bounds.height), 1) * 2
        } else {
            yaw -= Float(point.x - previousMouse.x) * 0.01
            pitch += Float(point.y - previousMouse.y) * 0.01
        }
        previousMouse = point
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        if atomDragActive { commitAtomDrag(); return }
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = atomIndex(at: point) else { onEmptyClick?(placementPosition(at: point)); return }
        let extend = !event.modifierFlags.intersection([.shift, .command]).isEmpty
        onAtomClick?(index, extend)
    }

    private func commitAtomDrag() {
        atomDragActive = false
        onPreviewAtomDrag?(pendingDragDelta)
        onFinishAtomDrag?()
        enableSetNeedsDisplay = !scene.animate; isPaused = !scene.animate
        setNeedsDisplay(bounds)
    }

    override func rightMouseDown(with event: NSEvent) {
        if atomDragActive { commitAtomDrag() }
        onClearSelection?()
        setNeedsDisplay(bounds)
    }

    override func rightMouseDragged(with event: NSEvent) {}

    func placementPosition(at point: CGPoint) -> Vector3 {
        let width = max(Float(bounds.width), 1), height = max(Float(bounds.height), 1)
        let aspect = width / height
        let scale = max(fitScale * zoom * min(1, aspect), 1e-8)
        let x = (Float(point.x) / width * 2 - 1 - pan.x) * aspect / scale
        let y = (Float(point.y) / height * 2 - 1 - pan.y) / scale
        // Intersect the orthographic ray with camera-space Z=0 analytically.
        // NDC Z=0 is Metal's near clip plane, and inverse-projection cancellation
        // also loses precision when zoomed out. Neither belongs in placement.
        let worldDelta = cameraRotation().transpose * SIMD4<Float>(x, y, 0, 0)
        return Vector3(center.x + worldDelta.x, center.y + worldDelta.y, center.z + worldDelta.z)
    }

    func projectedAtomPoint(_ index: Int) -> CGPoint? {
        guard scene.atoms.indices.contains(index) else { return nil }
        return projectPosition(displacedPositions()[index])
    }

    private func projectPosition(_ p: SIMD3<Float>) -> CGPoint? {
        let clip = makeMVP() * SIMD4(p.x, p.y, p.z, 1)
        guard abs(clip.w) > 1e-7 else { return nil }
        return CGPoint(x: CGFloat((clip.x / clip.w + 1) / 2) * bounds.width, y: CGFloat((clip.y / clip.w + 1) / 2) * bounds.height)
    }

    override func scrollWheel(with event: NSEvent) {
        // A trackpad fling must not continue shrinking the molecule after release.
        guard event.momentumPhase.isEmpty else { return }
        applyScrollZoom(delta: Float(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                        at: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        zoomBy(factor: exp(max(-0.18, min(0.18, Float(event.magnification)))),
               at: convert(event.locationInWindow, from: nil))
    }

    func applyScrollZoom(delta: Float, precise: Bool, at point: CGPoint) {
        guard delta.isFinite else { return }
        let exponent = max(-0.18, min(0.18, delta * (precise ? 0.006 : 0.06)))
        zoomBy(factor: exp(exponent), at: point)
    }

    func zoomBy(factor: Float, at point: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let anchor = CGPoint(x: max(0, min(bounds.width, point.x)), y: max(0, min(bounds.height, point.y)))
        let before = placementPosition(at: anchor)
        let next = min(max(zoom * factor, 0.1), 20)
        guard next != zoom else { return }
        zoom = next
        // Keep the point beneath the pointer fixed instead of zooming around an
        // unrelated canvas origin and throwing an off-center fragment out of view.
        let clip = makeMVP(size: bounds.size) * SIMD4(before.x, before.y, before.z, 1)
        pan.x += Float(anchor.x / max(bounds.width, 1)) * 2 - 1 - clip.x / clip.w
        pan.y += Float(anchor.y / max(bounds.height, 1)) * 2 - 1 - clip.y / clip.w
        setNeedsDisplay(bounds)
    }

    private func atomIndex(at point: CGPoint) -> Int? {
        let mvp = makeMVP()
        var best: (index: Int, depth: Float)?
        for (index, position) in displacedPositions().enumerated() {
            if !scene.showHydrogens && scene.atoms[index].element == "H" { continue }
            let clip = mvp * SIMD4(position.x, position.y, position.z, 1)
            guard abs(clip.w) > 1e-7 else { continue }
            let ndc = clip / clip.w
            let projected = CGPoint(
                x: CGFloat((ndc.x + 1) * 0.5) * bounds.width,
                y: CGFloat((ndc.y + 1) * 0.5) * bounds.height
            )
            let dx = projected.x - point.x
            let dy = projected.y - point.y
            let distanceSquared = dx * dx + dy * dy
            let radius = max(CGFloat(atomRadius(scene.atoms[index]) * fitScale * zoom) * min(bounds.width, bounds.height) / 2, 6)
            guard distanceSquared <= radius * radius else { continue }
            if best == nil || ndc.z < best!.depth {
                best = (index, ndc.z)
            }
        }
        return best?.index
    }
}

private extension simd_float4x4 {
    static func translation(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(value.x, value.y, value.z, 1)
        )
    }

    static func scale(_ value: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(value, 0, 0, 0),
            SIMD4(0, value, 0, 0),
            SIMD4(0, 0, value, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let a = simd_normalize(axis)
        let c = cos(radians)
        let s = sin(radians)
        let t = 1 - c
        return simd_float4x4(
            SIMD4(t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y, 0),
            SIMD4(t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x, 0),
            SIMD4(t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func orthographic(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        near: Float,
        far: Float
    ) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(2 / (right - left), 0, 0, 0),
            SIMD4(0, 2 / (top - bottom), 0, 0),
            SIMD4(0, 0, 1 / (far - near), 0),
            SIMD4(
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom),
                -near / (far - near),
                1
            )
        )
    }
}
