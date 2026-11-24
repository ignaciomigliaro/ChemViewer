import AppKit
import ChemCraftCore

@MainActor
enum ClipboardSupport {
    @discardableResult static func copy(_ text: String, pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    static func copy(_ image: NSBitmapImageRep, pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = image.representation(using: .png, properties: [:]),
              let tiff = image.representation(using: .tiff, properties: [:]) else { return false }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
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
