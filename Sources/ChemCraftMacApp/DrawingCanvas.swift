import AppKit
import ChemCraftCore
import SwiftUI

struct DrawingCanvas: NSViewRepresentable {
    @ObservedObject var drawing: MoleculeDrawingStore
    func makeNSView(context: Context) -> MolecularDrawingCanvas { MolecularDrawingCanvas(drawing: drawing) }
    func updateNSView(_ view: MolecularDrawingCanvas, context: Context) {
        view.drawing = drawing
        if view.fitSerial != drawing.fitRevision { view.fitSerial = drawing.fitRevision; view.fitDrawing() }
        view.needsDisplay = true
    }
}

@MainActor
final class MolecularDrawingCanvas: NSView {
    var drawing: MoleculeDrawingStore
    var fitSerial = 0
    var zoom: CGFloat = 1
    var pan = CGPoint.zero
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var snapshot = MolecularSketch()
    private var preview: MolecularSketch?
    private var rubberEnd: CGPoint?
    private var startAtom: Int?
    private var dragging = false
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    init(drawing: MoleculeDrawingStore) { self.drawing = drawing; super.init(frame: .zero); setAccessibilityLabel("2D molecular drawing canvas") }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func point(_ atom: MolecularSketch.Node) -> CGPoint { screen(CGPoint(x: atom.x, y: atom.y)) }
    func screen(_ point: CGPoint) -> CGPoint { CGPoint(x: bounds.midX + pan.x + point.x * zoom, y: bounds.midY + pan.y + point.y * zoom) }
    func world(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - bounds.midX - pan.x) / zoom, y: (point.y - bounds.midY - pan.y) / zoom) }
    private func hitAtom(_ position: CGPoint, graph: MolecularSketch) -> Int? {
        graph.atoms.min { hypot(point($0).x - position.x, point($0).y - position.y) < hypot(point($1).x - position.x, point($1).y - position.y) }.flatMap { hypot(point($0).x - position.x, point($0).y - position.y) < 13 ? $0.id : nil }
    }
    private func hitBond(_ position: CGPoint, graph: MolecularSketch) -> Int? {
        graph.bonds.indices.first { i in
            let edge = graph.bonds[i]
            guard let a = graph.atoms.first(where: { $0.id == edge.a }), let b = graph.atoms.first(where: { $0.id == edge.b }) else { return false }
            let p = point(a), q = point(b), dx = q.x - p.x, dy = q.y - p.y
            let t = min(1, max(0, ((position.x - p.x) * dx + (position.y - p.y) * dy) / max(dx * dx + dy * dy, 0.001)))
            return hypot(position.x - p.x - t * dx, position.y - p.y - t * dy) < 7
        }
    }
    func fitDrawing() {
        guard let first = drawing.graph.atoms.first else { zoom = 1; pan = .zero; needsDisplay = true; return }
        let minX = drawing.graph.atoms.map(\.x).min() ?? first.x, maxX = drawing.graph.atoms.map(\.x).max() ?? first.x
        let minY = drawing.graph.atoms.map(\.y).min() ?? first.y, maxY = drawing.graph.atoms.map(\.y).max() ?? first.y
        zoom = min(1.5, max(0.1, min((bounds.width - 90) / max(100, maxX - minX), (bounds.height - 90) / max(100, maxY - minY))))
        pan = CGPoint(x: -(minX + maxX) / 2 * zoom, y: -(minY + maxY) / 2 * zoom); needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil), before = world(anchor)
        zoom = min(4, max(0.15, zoom * exp(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.006 : 0.06))))
        let after = screen(before); pan.x += anchor.x - after.x; pan.y += anchor.y - after.y; needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); start = convert(event.locationInWindow, from: nil); last = start
        snapshot = drawing.graph; startAtom = hitAtom(start, graph: snapshot); drawing.selectedID = startAtom
        dragging = false; preview = nil; rubberEnd = nil
    }
    override func mouseDragged(with event: NSEvent) {
        let position = convert(event.locationInWindow, from: nil); dragging = hypot(position.x - start.x, position.y - start.y) > 4
        if drawing.tool == .move {
            if let id = startAtom, let index = snapshot.atoms.firstIndex(where: { $0.id == id }) {
                var graph = snapshot; graph.atoms[index].x += (position.x - start.x) / zoom; graph.atoms[index].y += (position.y - start.y) / zoom; preview = graph
            } else { pan.x += position.x - last.x; pan.y += position.y - last.y }
        } else if drawing.tool == .chain {
            preview = try? chainPreview(position)
        } else if drawing.tool == .bond {
            if let id = startAtom, let atom = snapshot.atoms.first(where: { $0.id == id }) {
                let angle = bondAngle(from: atom, toward: world(position), free: event.modifierFlags.contains(.option), graph: snapshot)
                rubberEnd = screen(CGPoint(x: atom.x + 48 * cos(angle), y: atom.y + 48 * sin(angle)))
            } else { rubberEnd = position }
        }
        last = position; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let position = convert(event.locationInWindow, from: nil), location = world(position)
        var graph = snapshot
        defer { preview = nil; rubberEnd = nil; needsDisplay = true }
        do {
            switch drawing.tool {
            case .move: if let preview { drawing.commit(preview) }; return
            case .erase:
                if let id = startAtom { graph.removeAtom(id) }
                else if let index = hitBond(position, graph: graph) { graph.bonds.remove(at: index) }
            case .positive, .negative:
                if let index = graph.atoms.firstIndex(where: { $0.id == startAtom }) { graph.atoms[index].charge = min(8, max(-8, graph.atoms[index].charge + (drawing.tool == .positive ? 1 : -1))) }
            case .atom:
                if let index = graph.atoms.firstIndex(where: { $0.id == startAtom }) { graph.atoms[index].element = drawing.element; graph.atoms[index].chiralTag = 0; graph.atoms[index].explicitHs = nil; graph.atoms[index].noImplicit = nil; graph.atoms[index].radicalElectrons = nil }
                else { drawing.selectedID = try graph.addAtom(drawing.element, x: location.x, y: location.y) }
            case .chain:
                if dragging { graph = try chainPreview(position); drawing.selectedID = graph.atoms.last?.id }
                else {
                    let a = try startAtom ?? graph.addAtom("C", x: location.x, y: location.y)
                    if startAtom != nil {
                        let atom = graph.atoms.first { $0.id == a }!, angle = try graph.suggestedBondAngle(from: a)
                        let b = try graph.addAtom("C", x: atom.x + 48 * cos(angle), y: atom.y + 48 * sin(angle))
                        try graph.connect(a, b, order: 1); drawing.selectedID = b
                    } else { drawing.selectedID = a }
                }
            case .ring:
                if let template = drawing.ringTemplate {
                    try graph.addRing(template: template, x: location.x, y: location.y, anchor: startAtom)
                } else { try graph.addRing(size: drawing.ringSize, aromatic: drawing.aromatic, x: location.x, y: location.y, anchor: startAtom) }
            case .bond:
                if !dragging, startAtom == nil, let index = hitBond(position, graph: graph) {
                    let edge = graph.bonds[index]
                    try graph.connect(edge.a, edge.b, order: drawing.order, stereo: drawing.order == 1 ? drawing.stereo : "none")
                } else {
                    let origin = world(start)
                    let a = try startAtom ?? graph.addAtom(drawing.element, x: origin.x, y: origin.y)
                    if !dragging && startAtom == nil { drawing.selectedID = a; break }
                    let existing = hitAtom(position, graph: graph)
                    let b: Int
                    if dragging, let existing, existing != a { b = existing }
                    else {
                        let atom = graph.atoms.first { $0.id == a }!
                        let angle: Double
                        if dragging { angle = bondAngle(from: atom, toward: location, free: event.modifierFlags.contains(.option), graph: graph) }
                        else {
                            angle = try graph.suggestedBondAngle(from: atom.id, order: drawing.order)
                        }
                        b = try graph.addAtom(drawing.element, x: atom.x + 48 * cos(angle), y: atom.y + 48 * sin(angle))
                    }
                    try graph.connect(a, b, order: drawing.order, stereo: drawing.order == 1 ? drawing.stereo : "none"); drawing.selectedID = b
                }
            }
            drawing.commit(graph)
        } catch { NSSound.beep() }
    }
    override func rightMouseDown(with event: NSEvent) { drawing.selectedID = nil; drawing.tool = .move; preview = nil; rubberEnd = nil; needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51, let id = drawing.selectedID { var graph = drawing.graph; graph.removeAtom(id); drawing.commit(graph); drawing.selectedID = nil }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let grid = NSBezierPath(), step = max(12, 24 * zoom)
        for x in stride(from: (bounds.midX + pan.x).truncatingRemainder(dividingBy: step), through: bounds.maxX, by: step) { grid.move(to: CGPoint(x: x, y: 0)); grid.line(to: CGPoint(x: x, y: bounds.height)) }
        for y in stride(from: (bounds.midY + pan.y).truncatingRemainder(dividingBy: step), through: bounds.maxY, by: step) { grid.move(to: CGPoint(x: 0, y: y)); grid.line(to: CGPoint(x: bounds.width, y: y)) }
        NSColor(white: 0.94, alpha: 1).setStroke(); grid.lineWidth = 0.5; grid.stroke()
        let graph = preview ?? drawing.graph
        for edge in graph.bonds {
            guard let a = graph.atoms.first(where: { $0.id == edge.a }), let b = graph.atoms.first(where: { $0.id == edge.b }) else { continue }
            drawBond(from: point(a), to: point(b), order: edge.order, stereo: edge.stereo)
        }
        if let end = rubberEnd { NSColor.systemTeal.setStroke(); let p = NSBezierPath(); p.move(to: start); p.line(to: end); p.lineWidth = 2; p.stroke() }
        for atom in graph.atoms {
            let position = point(atom)
            if atom.id == drawing.selectedID { NSColor.systemTeal.withAlphaComponent(0.15).setFill(); NSBezierPath(ovalIn: CGRect(x: position.x - 13, y: position.y - 13, width: 26, height: 26)).fill() }
            let connected = graph.bonds.contains { $0.a == atom.id || $0.b == atom.id }
            if atom.element == "C" && connected && atom.charge == 0 { continue }
            let charge = atom.charge == 0 ? "" : (abs(atom.charge) == 1 ? "" : String(abs(atom.charge))) + (atom.charge > 0 ? "+" : "−")
            let color = ElementTable.color(for: atom.element)
            let hydrogens = implicitHydrogens(atom, in: graph)
            let hydrogenText = hydrogens == 0 ? "" : "H" + (hydrogens == 1 ? "" : String(hydrogens))
            let text = NSAttributedString(string: atom.element + hydrogenText + charge, attributes: [.font: NSFont.systemFont(ofSize: 17 * min(1.5, max(0.8, zoom)), weight: .semibold), .foregroundColor: NSColor(red: CGFloat(color.0) * 0.7, green: CGFloat(color.1) * 0.7, blue: CGFloat(color.2) * 0.7, alpha: 1)])
            let size = text.size(), rect = CGRect(x: position.x - size.width / 2 - 3, y: position.y - size.height / 2 - 1, width: size.width + 6, height: size.height + 2)
            NSColor.white.setFill(); rect.fill(); text.draw(at: CGPoint(x: rect.minX + 3, y: rect.minY + 1))
        }
        if graph.atoms.isEmpty { NSAttributedString(string: "Draw bonds • place atoms • add rings", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: CGPoint(x: 25, y: bounds.midY)) }
    }
    private func implicitHydrogens(_ atom: MolecularSketch.Node, in graph: MolecularSketch) -> Int {
        let explicit = atom.explicitHs ?? 0
        if atom.noImplicit == true { return explicit }
        let valence = graph.bonds.filter { $0.a == atom.id || $0.b == atom.id }.reduce(0) { $0 + $1.order }
        let target: Int
        switch atom.element {
        case "C": target = 4
        case "N": target = atom.charge > 0 ? 4 : atom.charge < 0 ? 2 : 3
        case "O": target = 2 + atom.charge
        case "F", "Cl", "Br", "I": target = atom.charge == 0 ? 1 : 0
        case "S": target = valence <= 2 ? 2 : valence <= 4 ? 4 : 6
        case "P": target = valence <= 3 ? 3 : 5
        default: return explicit
        }
        return max(explicit, target - valence - (atom.radicalElectrons ?? 0))
    }
    private func chainPreview(_ position: CGPoint) throws -> MolecularSketch {
        var graph = snapshot
        let origin = world(start), target = world(position)
        let anchor = try startAtom ?? graph.addAtom("C", x: origin.x, y: origin.y)
        let length = hypot(target.x - origin.x, target.y - origin.y)
        let count = max(1, min(100, Int((length / (48 * cos(Double.pi / 6))).rounded())))
        let axis = (atan2(target.y - origin.y, target.x - origin.x) / (.pi / 6)).rounded() * (.pi / 6)
        _ = try graph.addZigzagChain(from: anchor, bonds: count, axis: axis)
        return graph
    }
    private func bondAngle(from atom: MolecularSketch.Node, toward position: CGPoint, free: Bool, graph: MolecularSketch) -> Double {
        let pointer = (atan2(position.y - atom.y, position.x - atom.x) / (.pi / 6)).rounded() * (.pi / 6)
        guard !free else { return pointer }
        let edges = graph.bonds.filter { $0.a == atom.id || $0.b == atom.id }
        guard edges.count == 1, let edge = edges.first,
              let neighbor = graph.atoms.first(where: { $0.id == (edge.a == atom.id ? edge.b : edge.a) }) else { return pointer }
        let incoming = atan2(atom.y - neighbor.y, atom.x - neighbor.x)
        if drawing.order == 3 || edge.order == 3 { return incoming }
        let candidates = [incoming + Double.pi / 3, incoming - Double.pi / 3]
        let preferred = (try? graph.suggestedBondAngle(from: atom.id, order: drawing.order)) ?? candidates[0]
        func gap(_ angle: Double) -> Double { abs(atan2(sin(angle - pointer), cos(angle - pointer))) }
        return abs(gap(candidates[0]) - gap(candidates[1])) < 1e-6 ? preferred : candidates.min(by: { gap($0) < gap($1) })!
    }
    private func drawBond(from a: CGPoint, to b: CGPoint, order: Int, stereo: String) {
        let dx = b.x - a.x, dy = b.y - a.y, length = max(hypot(dx, dy), 0.01), nx = -dy / length, ny = dx / length
        NSColor.labelColor.setStroke(); NSColor.labelColor.setFill()
        if stereo == "up" {
            let p = NSBezierPath(); p.move(to: a); p.line(to: CGPoint(x: b.x + nx * 5, y: b.y + ny * 5)); p.line(to: CGPoint(x: b.x - nx * 5, y: b.y - ny * 5)); p.close(); p.fill(); return
        }
        if stereo == "down" {
            for i in 1...7 { let t = CGFloat(i) / 8; let p = NSBezierPath(); p.move(to: CGPoint(x: a.x + dx * t - nx * t * 5, y: a.y + dy * t - ny * t * 5)); p.line(to: CGPoint(x: a.x + dx * t + nx * t * 5, y: a.y + dy * t + ny * t * 5)); p.lineWidth = 1.4; p.stroke() }; return
        }
        for i in 0..<order {
            let offset = (CGFloat(i) - CGFloat(order - 1) / 2) * 6 * zoom
            let p = NSBezierPath(); p.move(to: CGPoint(x: a.x + nx * offset, y: a.y + ny * offset)); p.line(to: CGPoint(x: b.x + nx * offset, y: b.y + ny * offset)); p.lineWidth = 1.8; p.stroke()
        }
    }
}
