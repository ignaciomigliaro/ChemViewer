import AppKit
import ChemCraftCore

struct MeasurementAnnotation {
    let points: [CGPoint]
    let label: String
    let value: Float
    // Fraction of viewport dimensions; preserved when exporting at a different resolution.
    var labelOffset: CGPoint = .zero

    static func make(positions: [SIMD3<Float>], indices: [Int], project: (Int) -> CGPoint?) -> MeasurementAnnotation? {
        guard (2...4).contains(indices.count), Set(indices).count == indices.count,
              indices.allSatisfy(positions.indices.contains) else { return nil }
        let points = indices.compactMap(project)
        guard points.count == indices.count else { return nil }
        let atoms = indices.enumerated().map { offset, index -> Atom in
            let p = positions[index]
            return Atom(id: offset, element: "X", position: Vector3(p.x, p.y, p.z))
        }
        let frame = MoleculeFrame(id: 0, atoms: atoms)
        do {
            let value: Float, label: String
            switch indices.count {
            case 2:
                value = try GeometryEditor.distance(in: frame, firstAtomIndex: 0, secondAtomIndex: 1)
                label = String(format: "%.5f Å", locale: Locale(identifier: "en_US_POSIX"), Double(value))
            case 3:
                value = try GeometryEditor.angleDegrees(in: frame, firstAtomIndex: 0, vertexAtomIndex: 1, thirdAtomIndex: 2)
                label = String(format: "%.3f°", locale: Locale(identifier: "en_US_POSIX"), Double(value))
            default:
                value = try GeometryEditor.dihedralDegrees(in: frame, firstAtomIndex: 0, secondAtomIndex: 1, thirdAtomIndex: 2, fourthAtomIndex: 3)
                label = String(format: "%.3f°", locale: Locale(identifier: "en_US_POSIX"), Double(value))
            }
            return MeasurementAnnotation(points: points, label: label, value: value)
        } catch { return nil }
    }

    func draw(in bounds: CGRect) {
        if points.count == 4 {
            for triangle in [[0, 1, 2], [1, 2, 3]] {
                let plane = NSBezierPath(); plane.move(to: points[triangle[0]])
                plane.line(to: points[triangle[1]]); plane.line(to: points[triangle[2]]); plane.close()
                NSColor.systemTeal.withAlphaComponent(0.16).setFill(); plane.fill()
            }
        }
        let path = NSBezierPath(); path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.lineWidth = 1.7; path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.systemTeal.setStroke(); path.stroke()
        for point in points {
            NSColor.systemTeal.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
        }
        let rectangle = labelRect(in: bounds)
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: rectangle, xRadius: 4, yRadius: 4).fill()
        labelText.draw(at: CGPoint(x: rectangle.minX + 5, y: rectangle.minY + 3))
    }

    private var labelText: NSAttributedString {
        NSAttributedString(string: label, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.black])
    }
    private var anchor: CGPoint {
        if points.count == 3 {
            return CGPoint(x: points.map(\.x).reduce(0, +) / 3, y: points.map(\.y).reduce(0, +) / 3)
        } else {
            let a = points.count == 2 ? points[0] : points[1]
            let b = points.count == 2 ? points[1] : points[2]
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }
    func offset(forLabelOrigin origin: CGPoint, in bounds: CGRect) -> CGPoint {
        let size = labelText.size()
        return CGPoint(x: (origin.x - (anchor.x - size.width / 2 - 5)) / max(bounds.width, 1),
                       y: (origin.y - (anchor.y + 7)) / max(bounds.height, 1))
    }
    func labelRect(in bounds: CGRect) -> CGRect {
        let size = labelText.size()
        let x = min(max(anchor.x - size.width / 2 + labelOffset.x * bounds.width, 8), max(8, bounds.width - size.width - 8))
        let y = min(max(anchor.y + 10 + labelOffset.y * bounds.height, 8), max(8, bounds.height - size.height - 8))
        return CGRect(x: x - 5, y: y - 3, width: size.width + 10, height: size.height + 6)
    }
}

enum AtomCaption: String, CaseIterable {
    case none = "No captions", numbers = "Atom numbers", elements = "Element labels", elementNumbers = "Elements and numbers"
    func label(element: String, index: Int) -> String {
        switch self { case .none: return ""; case .numbers: return String(index + 1); case .elements: return element; case .elementNumbers: return "\(element)\(index + 1)" }
    }
}
struct AtomCaptionAnnotation {
    let point: CGPoint
    let label: String
    func draw() {
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.black, .backgroundColor: NSColor.white.withAlphaComponent(0.85)])
        text.draw(at: CGPoint(x: point.x + 5, y: point.y + 5))
    }
}

final class MeasurementOverlayView: NSView {
    var captions: [AtomCaptionAnnotation] = [] { didSet { needsDisplay = true } }
    var annotation: MeasurementAnnotation? { didSet { needsDisplay = true; if lastDragPoint == nil && oldValue?.labelRect(in: bounds) != annotation?.labelRect(in: bounds) { window?.invalidateCursorRects(for: self) } } }
    override var isOpaque: Bool { false }
    var onMoveLabel: ((CGPoint) -> Void)?
    private var lastDragPoint: CGPoint?
    override func hitTest(_ point: NSPoint) -> NSView? {
        if NSApp.currentEvent?.type == .rightMouseDown || NSApp.currentEvent?.type == .rightMouseDragged { return nil }
        let local = convert(point, from: superview)
        return annotation?.labelRect(in: bounds).contains(local) == true ? self : nil
    }
    override func resetCursorRects() {
        if let annotation { addCursorRect(annotation.labelRect(in: bounds), cursor: .openHand) }
    }
    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previous = lastDragPoint, var annotation else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = annotation.labelRect(in: bounds)
        // Clamp to visible label bounds so dragging against an edge accumulates no hidden offset.
        let x = min(max(rect.minX + point.x - previous.x, 3), max(3, bounds.width - rect.width - 3))
        let y = min(max(rect.minY + point.y - previous.y, 5), max(5, bounds.height - rect.height - 5))
        annotation.labelOffset = annotation.offset(forLabelOrigin: CGPoint(x: x, y: y), in: bounds)
        self.annotation = annotation
        lastDragPoint = point
        onMoveLabel?(annotation.labelOffset)
    }
    override func mouseUp(with event: NSEvent) {
        if lastDragPoint != nil { NSCursor.pop() }
        lastDragPoint = nil
        window?.invalidateCursorRects(for: self)
    }
    override func draw(_ dirtyRect: NSRect) { for caption in captions { caption.draw() }; annotation?.draw(in: bounds) }
}
