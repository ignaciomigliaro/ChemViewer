import AppKit
import ChemCraftCore

@MainActor
enum ClipboardSupport {
    @discardableResult static func copy(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    static func number(_ value: Double) -> String { String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), value) }
    static func coordinates(_ atoms: [Atom]) -> String {
        atoms.map { atom in
            ([atom.element] + [atom.position.x, atom.position.y, atom.position.z].map {
                String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), Double($0))
            }).joined(separator: "\t")
        }.joined(separator: "\n") + "\n"
    }
}
