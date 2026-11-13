import AppKit
import ChemCraftCore
import SwiftUI

struct ManipulationToolbar: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    private let axes: [(String, Vector3)] = [("X", Vector3(1, 0, 0)), ("Y", Vector3(0, 1, 0)), ("Z", Vector3(0, 0, 1))]
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                iconButton("Toggle geometry dragging", selected: workspace.isDraggingEnabled) {
                    workspace.isDraggingEnabled.toggle()
                } content: {
                    ZStack { Image(systemName: "arrow.left.and.right").foregroundStyle(.blue); Image(systemName: "hand.point.up.fill").offset(y: 4).foregroundStyle(.orange) }
                }
                ForEach(DragScope.allCases, id: \.self) { scope in
                    iconButton("Drag \(scope.rawValue.lowercased())", selected: workspace.isDraggingEnabled && workspace.dragScope == scope) {
                        workspace.chooseDragScope(scope)
                    } content: { scopeIcon(scope) }
                }
                Text(workspace.isDraggingEnabled ? "Control-right-drag \(workspace.dragScope.rawValue.lowercased())" : "Camera").font(.caption).frame(width: 125, alignment: .leading)
                if workspace.isDraggingEnabled {
                    Toggle("Add new bonds", isOn: $workspace.addBondsAfterDragging).toggleStyle(.checkbox)
                        .help("Add newly close contacts after releasing a coordinate drag")
                    Picker("Drag axis", selection: $workspace.dragAxis) { ForEach(DragAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 165)
                    Picker("Pivot", selection: $workspace.rotationPivot) { ForEach(RotationPivot.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 230)
                    if workspace.rotationPivot == .metal { CoordinatingMetalPicker() }
                    Spacer()
                    Text("\(workspace.manipulationIndices.count) atoms").font(.caption).foregroundStyle(.secondary)
                } else { Spacer(); Text("Right-click clears selection").font(.caption).foregroundStyle(.secondary) }
            }
            if workspace.isDraggingEnabled {
                HStack(spacing: 7) {
                    Text(workspace.dragScope == .fragment ? "Rotate motif" : "Rotate").font(.caption)
                    TextField("Degrees", value: $workspace.rotationStep, format: .number).frame(width: 43).textFieldStyle(.roundedBorder)
                    Text("°").font(.caption)
                    ForEach(axes, id: \.0) { name, axis in
                        MotifRotationButton(title: "\(name)−", id: "motif-rotate-" + name + "-minus") { workspace.rotateManipulation(axis: axis, sign: -1) }.frame(width: 35, height: 24)
                        MotifRotationButton(title: "\(name)+", id: "motif-rotate-" + name + "-plus") { workspace.rotateManipulation(axis: axis, sign: 1) }.frame(width: 35, height: 24)
                    }
                    Spacer(minLength: 8)
                    Text("Move").font(.caption)
                    TextField("Angstrom", value: $workspace.translationStep, format: .number).frame(width: 43).textFieldStyle(.roundedBorder)
                    Text("Å").font(.caption)
                    ForEach(axes, id: \.0) { name, axis in
                        Button("\(name)−") { workspace.translateManipulation(axis: axis, sign: -1) }
                        Button("\(name)+") { workspace.translateManipulation(axis: axis, sign: 1) }
                    }
                }.controlSize(.small)
                Text(workspace.dragScope == .fragment ? "Fragment: Control-right-drag moves coordinates; left-click selects. Ligand click selects a ligand; metal click selects its attached motif, stopping at other metals. Build → Select Bond Side isolates one side of a selected bond." : "Control-right-drag an atom in the screen plane; Control-Option-right-drag moves in depth. Rotation axes are molecular X/Y/Z.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 8).padding(.vertical, 4).background(Color(nsColor: .windowBackgroundColor))
    }
    private func iconButton<Content: View>(_ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content().frame(width: 35, height: 28)
                .background(LinearGradient(colors: [Color.white, Color(nsColor: .controlBackgroundColor)], startPoint: .top, endPoint: .bottom))
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color.gray.opacity(0.6), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func scopeIcon(_ scope: DragScope) -> some View {
        Canvas { context, size in
            drawScopeIcon(scope, context: &context, size: size)
        }
    }

    private func drawScopeIcon(_ scope: DragScope, context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count: Int
        let satelliteColor: Color
        switch scope {
        case .atom: count = 0; satelliteColor = .green
        case .fragment: count = 3; satelliteColor = .green
        case .molecule: count = 5; satelliteColor = .pink
        }
        for index in 0..<count {
            let fraction: Double = Double(index) / Double(count)
            let angle: Double = fraction * (2.0 * Double.pi) - Double.pi / 2.0
            let offsetX: CGFloat = CGFloat(cos(angle)) * 10
            let offsetY: CGFloat = CGFloat(sin(angle)) * 10
            let end = CGPoint(x: center.x + offsetX, y: center.y + offsetY)
            var bond = Path()
            bond.move(to: center)
            bond.addLine(to: end)
            context.stroke(bond, with: .color(.gray), lineWidth: 2)
            let satelliteBounds = CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: satelliteBounds), with: .color(satelliteColor))
        }
        let centerBounds = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: centerBounds), with: .color(.blue))
    }
}

struct CoordinatingMetalPicker: View {
    @EnvironmentObject var workspace: WorkspaceStore
    var body: some View {
        let metals = workspace.selectedCoordinatingMetals
        Picker("Metal", selection: Binding(get: {
            workspace.rotationMetalIndex.flatMap { metals.contains($0) ? $0 : nil } ?? metals.first ?? -1
        }, set: { workspace.rotationMetalIndex = $0 })) {
            if metals.isEmpty { Text("No metal").tag(-1) }
            ForEach(metals, id: \.self) { index in
                Text("\(workspace.currentFrame?.atoms[index].element ?? "Metal") \(index + 1)").tag(index)
            }
        }.frame(width: 120).disabled(metals.isEmpty)
    }
}

private struct MotifRotationButton: NSViewRepresentable {
    let title: String
    let id: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.click))
        button.bezelStyle = .rounded; button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(id)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action; button.title = title; button.isEnabled = enabled
        button.setAccessibilityLabel("Rotate motif " + title)
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func click() { action() }
    }
}
