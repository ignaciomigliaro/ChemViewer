import Foundation
import ChemCraftCore

let help = """
ChemViewerPortable 0.12.0 — Windows / Linux / macOS scientific viewer
Usage: ChemViewerPortable INPUT [--output FILE] [--json | --xyz]
  Default: write a self-contained interactive HTML viewer. Open it in a browser.
  --json   Export versioned scientific data, source values and units.
  --xyz    Export every geometry using the shared XYZ writer.
  --output Destination (default: INPUT.chemviewer.html/json/xyz).
  --help   Show this message. Existing files are never overwritten.
Supported inputs: XYZ trajectories, ORCA output/input, Gaussian geometry subset.
The native Mac editor, SSH, ChemRefine and BosTMC UI are not in this viewer.
"""

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--version"] { print("0.12.0"); return }
    if args.isEmpty || args == ["--help"] { print(help); return }
    var input: String?, output: String?, format = "html", i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--output":
            i += 1
            guard i < args.count, output == nil else { throw ParseError.malformed("--output requires one path") }
            output = args[i]
        case "--json", "--xyz":
            guard format == "html" else { throw ParseError.malformed("Choose one output format") }
            format = String(arg.dropFirst(2))
        default:
            guard !arg.hasPrefix("--"), input == nil else { throw ParseError.malformed("Unexpected argument: \(arg)") }
            input = arg
        }
        i += 1
    }
    guard let input else { throw ParseError.malformed("Provide an input file") }
    let url = URL(fileURLWithPath: input)
    let data = try Data(contentsOf: url)
    guard let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
        throw ParseError.malformed("Unsupported source encoding")
    }
    let document = try ParserRegistry.parse(text: source, fileName: url.lastPathComponent, baseURL: url)
    let portable = PortableDocument(document: document, source: source)
    let result: Data
    switch format {
    case "json": result = try portable.json()
    case "xyz":
        guard !document.frames.isEmpty else { throw ParseError.noGeometry }
        result = Data(document.frames.map { XYZWriter.string(frame: $0) }.joined().utf8)
    default:
        let template = try String(contentsOf: Bundle.module.url(forResource: "viewer", withExtension: "html")!, encoding: .utf8)
        result = Data(try portable.html(template: template).utf8)
    }
    let destination = URL(fileURLWithPath: output ?? (input + ".chemviewer." + format))
    try result.write(to: destination, options: .withoutOverwriting)
    print(destination.path)
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("ChemViewer: \(error.localizedDescription)\n".utf8))
    exit(1)
}
