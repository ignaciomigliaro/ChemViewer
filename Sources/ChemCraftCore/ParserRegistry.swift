import Foundation

public enum ParserRegistry {
    public static func parse(url: URL) throws -> ParsedDocument {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.malformed("text encoding is neither UTF-8 nor ISO Latin-1")
        }
        return try parse(text: text, fileName: url.lastPathComponent)
    }

    public static func parse(text: String, fileName: String) throws -> ParsedDocument {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "xyz" {
            return try XYZParser.parse(text: text, title: fileName)
        }
        if text.contains("CARTESIAN COORDINATES (ANGSTROEM)") || text.contains("O   R   C   A") || text.contains("VIBRATIONAL FREQUENCIES") || text.contains("FINAL SINGLE POINT ENERGY") {
            return try ORCAParser.parse(text: text, title: fileName)
        }
        if let first = text.split(whereSeparator: \.isNewline).first,
           Int(first.trimmingCharacters(in: .whitespaces)) != nil {
            return try XYZParser.parse(text: text, title: fileName)
        }
        if text.contains("Standard orientation:") || text.contains("Input orientation:") {
            let analysis = try BuildingProject.analysis(text)
            return ParsedDocument(title: fileName, sourceFormat: "Gaussian", frames: analysis.frames)
        }
        throw ParseError.unsupportedFormat
    }
}
