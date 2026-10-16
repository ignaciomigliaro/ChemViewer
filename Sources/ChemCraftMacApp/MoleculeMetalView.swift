import ChemCraftCore
import MetalKit
import SwiftUI

struct MoleculeMetalView: NSViewRepresentable {
    let frame: MoleculeFrame
    let mode: VibrationalMode?
    let isAnimating: Bool
    let amplitude: Float
    let showDisplacementVectors: Bool
    @Binding var selectedAtomIndices: [Int]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MolecularMTKView {
        let view = MolecularMTKView()
        view.onAtomClick = { index, extendSelection in
            context.coordinator.selectAtom(index, extendSelection: extendSelection)
        }
        return view
    }

    func updateNSView(_ view: MolecularMTKView, context: Context) {
        context.coordinator.parent = self
        view.scene = RenderScene(
            atoms: frame.atoms,
            bonds: BondBuilder.inferBonds(atoms: frame.atoms),
            displacements: mode?.displacements ?? [],
            amplitude: amplitude,
            animate: isAnimating && mode != nil,
            showDisplacementVectors: showDisplacementVectors && mode != nil,
            selectedAtomIndices: selectedAtomIndices
        )
    }

    final class Coordinator {
        var parent: MoleculeMetalView

        init(parent: MoleculeMetalView) {
            self.parent = parent
        }

        func selectAtom(_ index: Int, extendSelection: Bool) {
            if extendSelection {
                if let position = parent.selectedAtomIndices.firstIndex(of: index) {
                    parent.selectedAtomIndices.remove(at: position)
                } else {
                    parent.selectedAtomIndices.append(index)
                    if parent.selectedAtomIndices.count > 4 {
                        parent.selectedAtomIndices.removeFirst()
                    }
                }
            } else {
                parent.selectedAtomIndices = [index]
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
}

private struct MetalVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var pointSize: Float
}

private struct MetalUniforms {
    var modelViewProjection: simd_float4x4
}

final class MolecularMTKView: MTKView, MTKViewDelegate {
    var scene = RenderScene(
        atoms: [], bonds: [], displacements: [], amplitude: 0.6,
        animate: false, showDisplacementVectors: false, selectedAtomIndices: []
    ) {
        didSet {
            recalculateBounds()
            enableSetNeedsDisplay = !scene.animate
            isPaused = !scene.animate
            setNeedsDisplay(bounds)
        }
    }

    private var commandQueue: MTLCommandQueue!
    private var atomPipeline: MTLRenderPipelineState!
    private var bondPipeline: MTLRenderPipelineState!
    private var center = SIMD3<Float>(repeating: 0)
    private var fitScale: Float = 1
    private var yaw: Float = 0.45
    private var pitch: Float = -0.30
    private var zoom: Float = 1
    private var pan = SIMD2<Float>(repeating: 0)
    private var previousMouse = CGPoint.zero
    private var mouseDownPoint = CGPoint.zero
    private var didDrag = false
    var onAtomClick: ((Int, Bool) -> Void)?

    init() {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)
        guard let device = metalDevice else { return }
        colorPixelFormat = .bgra8Unorm_srgb
        clearColor = MTLClearColor(red: 0.035, green: 0.045, blue: 0.06, alpha: 1)
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = true
        commandQueue = device.makeCommandQueue()
        buildPipelines(device: device)
        delegate = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    private func buildPipelines(device: MTLDevice) {
        let packagedBundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("ChemViewer_ChemViewerApp.bundle")
        let shaderBundle = packagedBundleURL.flatMap(Bundle.init(url:)) ?? .module
        guard let library = try? device.makeDefaultLibrary(bundle: shaderBundle) else { return }

        let atomDescriptor = MTLRenderPipelineDescriptor()
        atomDescriptor.label = "Atom impostors"
        atomDescriptor.vertexFunction = library.makeFunction(name: "atomVertex")
        atomDescriptor.fragmentFunction = library.makeFunction(name: "atomFragment")
        atomDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        atomPipeline = try? device.makeRenderPipelineState(descriptor: atomDescriptor)

        let bondDescriptor = MTLRenderPipelineDescriptor()
        bondDescriptor.label = "Bond lines"
        bondDescriptor.vertexFunction = library.makeFunction(name: "bondVertex")
        bondDescriptor.fragmentFunction = library.makeFunction(name: "bondFragment")
        bondDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        bondPipeline = try? device.makeRenderPipelineState(descriptor: bondDescriptor)
    }

    private func recalculateBounds() {
        guard !scene.atoms.isEmpty else { return }
        let sum = scene.atoms.reduce(SIMD3<Float>(repeating: 0)) {
            $0 + SIMD3($1.position.x, $1.position.y, $1.position.z)
        }
        center = sum / Float(scene.atoms.count)
        let maximum = scene.atoms.map {
            simd_length(SIMD3($0.position.x, $0.position.y, $0.position.z) - center)
        }.max() ?? 1
        fitScale = 0.72 / max(maximum, 0.5)
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
        let atomVertices = scene.atoms.enumerated().map { index, atom -> MetalVertex in
            let baseColor = ElementTable.color(for: atom.element)
            let selected = scene.selectedAtomIndices.contains(index)
            let color = selected ? (1.0, 0.82, 0.08, 1.0) : baseColor
            return MetalVertex(
                position: positions[index],
                color: SIMD4(color.0, color.1, color.2, color.3),
                pointSize: 18 + ElementTable.covalentRadius(for: atom.element) * 14 + (selected ? 8 : 0)
            )
        }
        var bondVertices: [MetalVertex] = []
        let bondColor = SIMD4<Float>(0.62, 0.66, 0.72, 1)
        for bond in scene.bonds where positions.indices.contains(bond.first) && positions.indices.contains(bond.second) {
            bondVertices.append(MetalVertex(position: positions[bond.first], color: bondColor, pointSize: 1))
            bondVertices.append(MetalVertex(position: positions[bond.second], color: bondColor, pointSize: 1))
        }
        if scene.showDisplacementVectors {
            let vectorColor = SIMD4<Float>(1.0, 0.62, 0.08, 1)
            for index in scene.atoms.indices where scene.displacements.indices.contains(index) {
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
                appendLine(from: origin, to: tip, color: vectorColor, into: &bondVertices)

                let direction = delta / magnitude
                let reference = abs(direction.z) < 0.9 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
                let side = simd_normalize(simd_cross(direction, reference))
                let headLength = min(magnitude * 0.28, 0.18 / max(fitScale, 0.01))
                let headWidth = headLength * 0.45
                let base = tip - direction * headLength
                appendLine(from: tip, to: base + side * headWidth, color: vectorColor, into: &bondVertices)
                appendLine(from: tip, to: base - side * headWidth, color: vectorColor, into: &bondVertices)
            }
        }

        var uniforms = MetalUniforms(modelViewProjection: makeMVP())
        if !bondVertices.isEmpty,
           let buffer = device?.makeBuffer(
                bytes: bondVertices,
                length: MemoryLayout<MetalVertex>.stride * bondVertices.count
           ) {
            encoder.setRenderPipelineState(bondPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: bondVertices.count)
        }
        if !atomVertices.isEmpty,
           let buffer = device?.makeBuffer(
                bytes: atomVertices,
                length: MemoryLayout<MetalVertex>.stride * atomVertices.count
           ) {
            encoder.setRenderPipelineState(atomPipeline)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MetalUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: atomVertices.count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func appendLine(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        color: SIMD4<Float>,
        into vertices: inout [MetalVertex]
    ) {
        vertices.append(MetalVertex(position: start, color: color, pointSize: 1))
        vertices.append(MetalVertex(position: end, color: color, pointSize: 1))
    }

    private func displacedPositions() -> [SIMD3<Float>] {
        let phase = scene.animate ? Float(sin(CACurrentMediaTime() * 3.0)) : 0
        return scene.atoms.enumerated().map { index, atom in
            var value = SIMD3(atom.position.x, atom.position.y, atom.position.z)
            if scene.displacements.indices.contains(index) {
                let displacement = scene.displacements[index]
                value += SIMD3(displacement.x, displacement.y, displacement.z) * scene.amplitude * phase
            }
            return value
        }
    }

    private func makeMVP() -> simd_float4x4 {
        let width = max(Float(drawableSize.width), 1)
        let height = max(Float(drawableSize.height), 1)
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
        let rotation = simd_float4x4.rotation(radians: pitch, axis: SIMD3(1, 0, 0)) *
            simd_float4x4.rotation(radians: yaw, axis: SIMD3(0, 1, 0))
        let scale = simd_float4x4.scale(fitScale * zoom)
        return projection * translation * rotation * scale * simd_float4x4.translation(-center)
    }

    override func mouseDown(with event: NSEvent) {
        previousMouse = convert(event.locationInWindow, from: nil)
        mouseDownPoint = previousMouse
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        didDrag = didDrag || hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 3
        if event.modifierFlags.contains(.option) {
            pan.x += Float(point.x - previousMouse.x) / max(Float(bounds.width), 1) * 2
            pan.y += Float(point.y - previousMouse.y) / max(Float(bounds.height), 1) * 2
        } else {
            yaw += Float(point.x - previousMouse.x) * 0.01
            pitch += Float(point.y - previousMouse.y) * 0.01
        }
        previousMouse = point
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = atomIndex(at: point) else { return }
        let extend = !event.modifierFlags.intersection([.shift, .command]).isEmpty
        onAtomClick?(index, extend)
    }

    override func rightMouseDown(with event: NSEvent) {
        previousMouse = convert(event.locationInWindow, from: nil)
        mouseDownPoint = previousMouse
        didDrag = false
    }

    override func rightMouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        didDrag = didDrag || hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 3
        yaw += Float(point.x - previousMouse.x) * 0.01
        pitch += Float(point.y - previousMouse.y) * 0.01
        previousMouse = point
        setNeedsDisplay(bounds)
    }

    override func scrollWheel(with event: NSEvent) {
        zoom = min(max(zoom * exp(Float(event.scrollingDeltaY) * 0.02), 0.1), 20)
        setNeedsDisplay(bounds)
    }

    private func atomIndex(at point: CGPoint) -> Int? {
        let mvp = makeMVP()
        let scale = window?.backingScaleFactor ?? 1
        var best: (index: Int, distanceSquared: CGFloat)?
        for (index, position) in displacedPositions().enumerated() {
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
            let pointSize = 18 + ElementTable.covalentRadius(for: scene.atoms[index].element) * 14
            let radius = max(CGFloat(pointSize) / scale * 0.65, 12)
            guard distanceSquared <= radius * radius else { continue }
            if best == nil || distanceSquared < best!.distanceSquared {
                best = (index, distanceSquared)
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
