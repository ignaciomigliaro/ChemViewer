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
                Text(workspace.isDraggingEnabled ? "Drag \(workspace.dragScope.rawValue.lowercased())" : "Camera").font(.caption).frame(width: 95, alignment: .leading)
                if workspace.isDraggingEnabled {
                    Picker("Drag axis", selection: $workspace.dragAxis) { ForEach(DragAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 165)
                    Picker("Pivot", selection: $workspace.rotationPivot) { ForEach(RotationPivot.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 230)
                    Spacer()
                    Text("\(workspace.manipulationIndices.count) atoms").font(.caption).foregroundStyle(.secondary)
                } else { Spacer(); Text("Right-click clears selection").font(.caption).foregroundStyle(.secondary) }
            }
            if workspace.isDraggingEnabled {
                HStack(spacing: 7) {
                    Text("Rotate").font(.caption)
                    TextField("Degrees", value: $workspace.rotationStep, format: .number).frame(width: 43).textFieldStyle(.roundedBorder)
                    Text("°").font(.caption)
                    ForEach(axes, id: \.0) { name, axis in
                        Button("\(name)−") { workspace.rotateManipulation(axis: axis, sign: -1) }
                        Button("\(name)+") { workspace.rotateManipulation(axis: axis, sign: 1) }
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
                Text(workspace.dragScope == .fragment ? "Fragment: select a bonded pair first to isolate the second side, or click an atom for its connected group." : "Drag an atom in the screen plane; Option-drag moves in depth. Rotation axes are molecular X/Y/Z.")
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
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = scope == .atom ? 0 : scope == .fragment ? 3 : 5
            for index in 0..<count {
                let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2
                let end = CGPoint(x: center.x + cos(angle) * 10, y: center.y + sin(angle) * 10)
                var path = Path(); path.move(to: center); path.addLine(to: end)
                context.stroke(path, with: .color(.gray), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(scope == .fragment ? .green : .pink))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.blue))
        }
    }
}
