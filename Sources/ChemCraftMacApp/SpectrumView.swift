import ChemCraftCore
import Foundation
import SwiftUI

struct SpectrumView: View {
    let modes: [VibrationalMode]

    @State private var shape = SpectralLineShape.gaussian
    @State private var halfWidth = 12.0
    @State private var broadenLines = true
    @State private var reverseAxis = true

    private var lines: [SpectralLine] {
        modes.compactMap { mode in
            guard mode.frequencyCM1 >= 0, let intensity = mode.infraredIntensity else { return nil }
            return SpectralLine(position: mode.frequencyCM1, intensity: intensity)
        }
    }

    private var upperBound: Double {
        max(4000, (lines.map(\.position).max() ?? 3900) + 100)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("IR spectrum")
                    .font(.title2.bold())
                Spacer()
                Toggle("Broaden", isOn: $broadenLines)
                Picker("Shape", selection: $shape) {
                    ForEach(SpectralLineShape.allCases) { lineShape in
                        Text(lineShape.rawValue).tag(lineShape)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                Text("HWHM")
                Slider(value: $halfWidth, in: 1...80)
                    .frame(width: 120)
                Text("\(halfWidth, specifier: "%.0f") cm⁻¹")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                Toggle("IR axis", isOn: $reverseAxis)
            }
            spectrumCanvas
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            Text("Wavenumber (cm⁻¹)")
                .font(.caption)
        }
        .padding()
    }

    private var spectrumCanvas: some View {
        Canvas { context, size in
            let left: CGFloat = 56
            let right: CGFloat = 18
            let top: CGFloat = 18
            let bottom: CGFloat = 38
            let plot = CGRect(
                x: left,
                y: top,
                width: max(1, size.width - left - right),
                height: max(1, size.height - top - bottom)
            )
            guard !lines.isEmpty else {
                context.draw(Text("No IR intensities in this file").foregroundStyle(.secondary), at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }

            let broadened = SpectrumBroadening.sample(
                lines: lines,
                from: 0,
                to: upperBound,
                pointCount: max(512, Int(plot.width * 2)),
                halfWidthAtHalfMaximum: halfWidth,
                shape: shape
            )
            let maximum = max(
                broadenLines ? (broadened.map(\.y).max() ?? 1) : (lines.map(\.intensity).max() ?? 1),
                1e-12
            )

            func xCoordinate(_ value: Double) -> CGFloat {
                let fraction = CGFloat(value / upperBound)
                return reverseAxis ? plot.maxX - fraction * plot.width : plot.minX + fraction * plot.width
            }
            func yCoordinate(_ value: Double) -> CGFloat {
                plot.maxY - CGFloat(value / maximum) * plot.height * 0.94
            }

            var axes = Path()
            axes.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axes.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            axes.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            context.stroke(axes, with: .color(.secondary), lineWidth: 1)

            for tick in stride(from: 0.0, through: upperBound, by: 500) {
                let x = xCoordinate(tick)
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: plot.maxY))
                mark.addLine(to: CGPoint(x: x, y: plot.maxY + 5))
                context.stroke(mark, with: .color(.secondary), lineWidth: 1)
                context.draw(
                    Text(String(format: "%.0f", tick)).font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: x, y: plot.maxY + 17),
                    anchor: .center
                )
            }

            if broadenLines {
                var curve = Path()
                for (index, point) in broadened.enumerated() {
                    let value = CGPoint(x: xCoordinate(point.x), y: yCoordinate(point.y))
                    if index == 0 { curve.move(to: value) } else { curve.addLine(to: value) }
                }
                context.stroke(curve, with: .color(.blue), lineWidth: 2)
            } else {
                for line in lines {
                    var stick = Path()
                    let x = xCoordinate(line.position)
                    stick.move(to: CGPoint(x: x, y: plot.maxY))
                    stick.addLine(to: CGPoint(x: x, y: yCoordinate(line.intensity)))
                    context.stroke(stick, with: .color(.blue), lineWidth: 2)
                }
            }
        }
    }
}
