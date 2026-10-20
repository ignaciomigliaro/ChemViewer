import SwiftUI
import ChemCraftCore

struct RingTemplateGlyph: View {
    let template: SketchRingTemplate
    var body: some View {
        Canvas { context, size in
            let n = template.elements.count, radius = min(size.width, size.height) * 0.40
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let points = (0..<n).map { i in
                let a = Double.pi + Double(i) * 2 * Double.pi / Double(n)
                return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            }
            for i in 0..<n {
                let a = points[i], b = points[(i + 1) % n]
                var path = Path(); path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(.primary), lineWidth: 1.5)
                if template.bondOrders[i] == 2 {
                    let p = CGPoint(x: center.x + (a.x - center.x) * 0.70, y: center.y + (a.y - center.y) * 0.70)
                    let q = CGPoint(x: center.x + (b.x - center.x) * 0.70, y: center.y + (b.y - center.y) * 0.70)
                    var inner = Path(); inner.move(to: p); inner.addLine(to: q)
                    context.stroke(inner, with: .color(.primary), lineWidth: 1.2)
                }
            }
            for i in 0..<n where template.elements[i] != "C" {
                let point = points[i]
                context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)), with: .color(Color(nsColor: .windowBackgroundColor)))
                context.draw(Text(template.elements[i]).font(.system(size: 10, weight: .bold)).foregroundColor(.blue), at: point)
            }
        }
    }
}

struct ChainToolGlyph: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 16)); p.addLine(to: CGPoint(x: 9, y: 6))
            p.addLine(to: CGPoint(x: 17, y: 16)); p.addLine(to: CGPoint(x: 25, y: 6))
        }.stroke(lineWidth: 1.7).frame(width: 27, height: 22)
    }
}
