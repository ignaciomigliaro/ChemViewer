import AppKit
import ChemCraftCore
import SwiftUI

struct CoordinateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var atoms: [Atom]
    private let embedded: Bool
    private let frameComment: String
    private let onApply: ([Atom]) -> Void

    init(frame: MoleculeFrame, embedded: Bool = false, onApply: @escaping ([Atom]) -> Void) {
        self.embedded = embedded
        _atoms = State(initialValue: frame.atoms)
        frameComment = frame.comment
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cartesian coordinates")
                .font(.title2.bold())
            if !frameComment.isEmpty {
                Text(frameComment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text("#")
                        Text("Element")
                        Text("X (Angstrom)")
                        Text("Y (Angstrom)")
                        Text("Z (Angstrom)")
                    }
                    .font(.caption.bold())
                    GridRow {
                        Divider().gridCellColumns(5)
                    }
                    ForEach($atoms) { $atom in
                        GridRow {
                            Text("\(atom.id + 1)")
                                .monospacedDigit()
                            Text(atom.element)
                                .frame(width: 58, alignment: .leading)
                            coordinateField($atom.position.x)
                            coordinateField($atom.position.y)
                            coordinateField($atom.position.z)
                        }
                    }
                }
                .padding(4)
            }
            HStack {
                Button("Copy coordinates") { _ = ClipboardSupport.copy(ClipboardSupport.coordinates(atoms)) }
                Button("Copy XYZ") { _ = ClipboardSupport.copy(XYZWriter.string(frame: MoleculeFrame(id: 0, atoms: atoms, comment: "Cartesian coordinates"))) }
                Spacer()
                if !embedded { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                Button("Apply") {
                    onApply(atoms)
                    if !embedded { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 650, minHeight: 420)
    }

    private func coordinateField(_ value: Binding<Float>) -> some View {
        TextField("0.0", value: value, format: .number.precision(.fractionLength(8)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 145)
    }
}
