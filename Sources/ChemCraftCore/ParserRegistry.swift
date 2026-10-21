import Foundation

public enum ParserRegistry {
    public static func parse(url: URL) throws -> ParsedDocument {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.malformed("text encoding is neither UTF-8 nor ISO Latin-1")
        }
        return try parse(text: text, fileName: url.lastPathComponent, baseURL: url)
    }

    public static func parse(text: String, fileName: String, baseURL: URL? = nil, externalXYZFiles: [String:URL] = [:]) throws -> ParsedDocument {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "xyz" {
            return try XYZParser.parse(text: text, title: fileName)
        }
        if !["inp", "in"].contains(ext) && (text.contains("CARTESIAN COORDINATES (ANGSTROEM)") || text.contains("O   R   C   A") || text.contains("VIBRATIONAL FREQUENCIES") || text.contains("FINAL SINGLE POINT ENERGY")) {
            return try ORCAParser.parse(text: text, title: fileName)
        }
        if ["inp", "in"].contains(ext) || text.range(of: #"(?im)^\s*\*\s+(xyz|xyzfile|int|internal|gzmt)\s"#, options: .regularExpression) != nil {
            return try ORCAInputParser.parse(text: text, title: fileName, resolveXYZ: { name in
                let file = externalXYZFiles[name] ?? (baseURL.map { URL(fileURLWithPath: name, relativeTo: $0.deletingLastPathComponent()).standardizedFileURL })
                guard let file else { throw ParseError.malformed("Open this input from its file location to resolve XYZ companion: \(name)") }
                let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard size <= 100_000_000 else { throw ParseError.malformed("XYZ companion exceeds 100 MB") }
                return try String(contentsOf: file, encoding: .utf8)
            })
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
