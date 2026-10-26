import AppKit
import ChemCraftCore
import SwiftUI

/// All 118 elements, with f-block rows kept separate from the main groups.
struct PeriodicTableView: View {
    var onSelect: ((String) -> Void)? = nil
    var selection: Binding<[String]>? = nil
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 4), count: 18)
    private var rows: [[Int]] {
        [
            [1] + Array(repeating: 0, count: 16) + [2],
            [3, 4] + Array(repeating: 0, count: 10) + Array(5...10),
            [11, 12] + Array(repeating: 0, count: 10) + Array(13...18),
            Array(19...36), Array(37...54),
            [55, 56, -1] + Array(72...86),
            [87, 88, -2] + Array(104...118),
            Array(repeating: 0, count: 18),
            [0, 0] + Array(57...71) + [0],
            [0, 0] + Array(89...103) + [0]
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selection != nil ? "Coordinating atoms" : onSelect == nil ? "Add atom / replace element" : "Choose an element").font(.title2.bold())
                Spacer()
                Button(selection == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if onSelect == nil && selection == nil {
            Picker("Clicking an existing atom", selection: $workspace.atomPlacementMode) {
                ForEach(AtomPlacementMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 400)
            Text("Choose an element, then left-click in the molecule view. Empty space places a new atom; right-click finishes.")
                .font(.callout).foregroundStyle(.secondary)
            }
            if let selection {
                Text("Select every element required in the coordinating-atom list. Other coordinating elements are allowed.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Text(selection.wrappedValue.isEmpty ? "No elements selected" : selection.wrappedValue.joined(separator:", "))
                    Spacer()
                    Button("Clear selection") { selection.wrappedValue = [] }
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...18, id: \.self) { Text("\($0)").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(rows.flatMap { $0 }.enumerated()), id: \.offset) { _, number in
                    if number > 0 {
                        PeriodicElementButton(number: number, symbol: BuildingProject.elements[number], selected:selection?.wrappedValue.contains(BuildingProject.elements[number]) ?? false) {
                            choose(BuildingProject.elements[number])
                        }.frame(width: 42, height: 42)
                    } else if number < 0 {
                        Text(number == -1 ? "57–71" : "89–103").font(.system(size: 9)).frame(height: 42)
                    } else { Color.clear.frame(height: 42) }
                }
            }
            if onSelect == nil && selection == nil {
            HStack {
                Button("X · dummy attachment site") { workspace.armAtom("X"); dismiss() }
                Spacer()
                Text(workspace.atomPlacementMode == .replace
                     ? "Replace changes only the element; coordinates stay fixed."
                     : "Bond mode uses an available H/X site, otherwise adds a new bond.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
        }.padding(20).frame(width: 866).background(Color(nsColor:.windowBackgroundColor))
    }
    private func choose(_ symbol: String) {
        if let selection {
            var values = selection.wrappedValue
            if values.contains(symbol) { values.removeAll { $0 == symbol } } else { values.append(symbol) }
            selection.wrappedValue = BuildingProject.elements.filter { values.contains($0) }
        } else {
            if let onSelect { onSelect(symbol) } else { workspace.armAtom(symbol) }
            dismiss()
        }
    }
}

/// Native buttons provide reliable keyboard/accessibility activation as well as clicks.
private struct PeriodicElementButton: NSViewRepresentable {
    let number: Int
    let symbol: String
    var selected = false
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "\(number)\n\(symbol)", target: context.coordinator, action: #selector(Coordinator.choose))
        button.bezelStyle = .regularSquare
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.toolTip = "\(symbol) · atomic number \(number)"
        button.identifier = NSUserInterfaceItemIdentifier("periodic-element-" + symbol)
        button.setAccessibilityLabel(button.toolTip)
        let color = ElementTable.color(for: symbol)
        button.bezelColor = selected ? .controlAccentColor : NSColor(red: CGFloat(color.0) * 0.3 + 0.7, green: CGFloat(color.1) * 0.3 + 0.7, blue: CGFloat(color.2) * 0.3 + 0.7, alpha: 1)
        return button
    }
    func updateNSView(_ view: NSButton, context: Context) {
        context.coordinator.action = action
        let color = ElementTable.color(for:symbol)
        view.bezelColor = selected ? .controlAccentColor : NSColor(red:CGFloat(color.0)*0.3+0.7,green:CGFloat(color.1)*0.3+0.7,blue:CGFloat(color.2)*0.3+0.7,alpha:1)
        view.setAccessibilityValue(selected ? "Selected" : "Not selected")
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func choose() { action() }
    }
}
