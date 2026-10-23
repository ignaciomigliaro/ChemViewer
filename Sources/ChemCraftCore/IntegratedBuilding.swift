import Foundation

// Original project-owned implementation, retained in a namespace to avoid parser/model collisions.
enum IntegratedBuilding {
// Integrated from the original MoleculeView Parsing.swift

static let elements = "X H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr Rf Db Sg Bh Hs Mt Ds Rg Cn Nh Fl Mc Lv Ts Og".split(separator: " ").map(String.init)
struct Atom: Codable { let symbol: String; let x: Double; let y: Double; let z: Double }
struct SummaryFact { let label: String; let value: String; let unit: String; let line: Int; let job: Int }
struct Document {
 let frames: [[Atom]]; let text: String; let format: String
 let modesByFrame: [[VibrationalMode]]
 let geometryLines: [Int]
 let facts: [SummaryFact]
 func modes(forFrame index: Int) -> [VibrationalMode] { modesByFrame.indices.contains(index) ? modesByFrame[index] : [] }
 var abstractText: String { summary }
 var summary: String {
  var rows = ["Format: \(format)", "Geometries: \(frames.count) • coordinates in Å"]
  for fact in facts { rows.append("Job \(fact.job + 1) • \(fact.label): \(fact.value) \(fact.unit) [source line \(fact.line)]") }
  for i in modesByFrame.indices where !modesByFrame[i].isEmpty {
   let modes = modesByFrame[i]; rows.append("Geometry \(i + 1): \(modes.count) complete normal modes; \(modes.filter { $0.frequency < 0 }.count) imaginary. Frequencies in cm⁻¹; displacement vectors as printed by ORCA.")
   for mode in modes { rows.append("  Mode \(mode.index): \(String(format: "%.2f", mode.frequency)) cm⁻¹\(mode.frequency < 0 ? " (imaginary)" : "")") }
  }
  rows.append("Missing properties are not inferred. Bond connectivity is a distance estimate. Edited structures are initial geometries, not energy minimized.")
  return rows.joined(separator: "\n")
 }
}
struct ParseError: LocalizedError { let message: String; var errorDescription: String? { message } }
static func number(_ s: String) -> Double? { guard let n = Double(s.replacingOccurrences(of: "D", with: "E").replacingOccurrences(of: "d", with: "e")), n.isFinite, abs(n) < 1e6 else { return nil }; return n }
static func atom(_ p: [String], allowDummy: Bool = false) -> Atom? { guard p.count >= 4, elements.contains(p[0]), (p[0] != "X" || allowDummy), let x = number(p[1]), let y = number(p[2]), let z = number(p[3]) else { return nil }; return Atom(symbol:p[0],x:x,y:y,z:z) }
static func parse(_ text: String) throws -> Document {
 let lines = text.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n").components(separatedBy:"\n")
 func fields(_ i: Int) -> [String] { lines[i].split(whereSeparator: { $0.isWhitespace }).map(String.init) }
 var frames: [[Atom]] = []; var geometryLines: [Int] = []; var i = 0; var format = ""
 while i < lines.count && lines[i].trimmingCharacters(in:.whitespaces).isEmpty { i += 1 }
 if i < lines.count, Int(lines[i].trimmingCharacters(in:.whitespaces)) != nil {
  format = "XYZ"
  while i < lines.count {
   if lines[i].trimmingCharacters(in:.whitespaces).isEmpty { i += 1; continue }
   guard let n = Int(lines[i].trimmingCharacters(in:.whitespaces)), n > 0, n <= 10000, i + n + 1 < lines.count else { throw ParseError(message:"Invalid or truncated XYZ frame at line \(i+1).") }
   var a: [Atom] = []
   for j in (i+2)...(i+n+1) { guard let v = atom(fields(j), allowDummy:true) else { throw ParseError(message:"Invalid atom at line \(j+1).") }; a.append(v) }
   geometryLines.append(i); frames.append(a); i += n+2
  }
 } else {
  i = 0
  while i < lines.count {
   guard frames.count <= 2000, frames.reduce(0, { $0 + $1.count }) <= 500000 else { throw ParseError(message:"Trajectory exceeds supported bounds.") }
   if lines[i].contains("CARTESIAN COORDINATES (ANGSTROEM)") {
    format = "ORCA"; let start = i; i += 1; var a: [Atom] = []
    var headerRows = 0
    while i < lines.count {
     if let v = atom(fields(i)) { a.append(v) }
     else if !a.isEmpty {
      let row = fields(i)
      if !row.isEmpty && !row[0].allSatisfy({ $0 == "-" }) { throw ParseError(message:"Malformed ORCA coordinate row at line \(i+1).") }
      break
     } else { headerRows += 1; if headerRows > 4 { break } }
     i += 1
     if a.count > 10000 { throw ParseError(message:"Geometry exceeds 10,000 atoms.") }
    }
    guard !a.isEmpty, i < lines.count else { throw ParseError(message:"Empty or unterminated ORCA coordinate block at line \(start+1).") }
    geometryLines.append(start); frames.append(a)
   } else if lines[i].contains("Standard orientation:") || lines[i].contains("Input orientation:") {
    format = "Gaussian"; let start = i; i += 1; var a: [Atom] = []; var separators = 0
    while i < lines.count {
     if lines[i].contains("-----") { separators += 1; if separators == 3 { break } }
     else if separators == 2 {
      let p = fields(i)
      guard p.count >= 6, let z = Int(p[1]), z > 0, z < elements.count, let v = atom([elements[z],p[3],p[4],p[5]]) else { throw ParseError(message:"Unsupported Gaussian geometry row at line \(i+1).") }
      a.append(v)
     }
     i += 1
     if a.count > 10000 { throw ParseError(message:"Geometry exceeds 10,000 atoms.") }
    }
    if !a.isEmpty { geometryLines.append(start); frames.append(a) }
   }
   i += 1
  }
 }
 guard frames.count <= 2000, frames.reduce(0, { $0 + $1.count }) <= 500000 else { throw ParseError(message:"Trajectory exceeds the 2,000-frame or 500,000-atom limit.") }
 guard !frames.isEmpty else { throw ParseError(message:"No supported geometry found. Open XYZ, ORCA Angstrom coordinate output, or Gaussian orientation output.") }
 let analysis = analyzeOrca(lines: lines, frames: frames, geometryLines: geometryLines)
 return Document(frames:frames,text:text,format:format,modesByFrame:format == "ORCA" ? analysis.modes : Array(repeating: [], count: frames.count),geometryLines:geometryLines.map { $0 + 1 },facts:format == "ORCA" ? analysis.facts : [])
}
static func loadDocument(_ url: URL) throws -> Document {
 let size = (try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
 guard size <= 100_000_000 else { throw ParseError(message:"File exceeds the 100 MB viewer limit.") }
 let data = try Data(contentsOf:url)
 guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) else { throw ParseError(message:"Cannot decode file text.") }
 return try parse(text)
}

private static func analyzeOrca(lines: [String], frames: [[Atom]], geometryLines: [Int]) -> (modes: [[VibrationalMode]], facts: [SummaryFact]) {
 var modes = Array(repeating: [VibrationalMode](), count: frames.count)
 var facts: [SummaryFact] = []; var job = 0; var jobStart = 0
 let properties: [(String,String,String)] = [
 ("FINAL SINGLE POINT ENERGY","Electronic energy","Eh"),
 ("Total Charge","Charge","e"),("Multiplicity","Multiplicity",""),
 ("Zero point energy","Zero point energy","Eh"),
 ("Total thermal energy","Thermal energy","Eh"),
 ("Total Enthalpy","Enthalpy","Eh"),
 ("Final Gibbs free energy","Gibbs free energy","Eh"),
 ("Temperature","Temperature","K"),
 ("Pressure","Pressure","atm")]
 for i in lines.indices {
  let line = lines[i]
  if line.trimmingCharacters(in:.whitespaces).lowercased() == "$new_job" { job += 1; jobStart = i }
  if line.contains("JOB NUMBER") {
   let words = line.split(whereSeparator: { !$0.isNumber })
   if let n = words.first.flatMap({ Int($0) }), n > 0 { job = n - 1 }
   jobStart = i
  }
  for (needle,label,unit) in properties where line.contains(needle) {
   let tail = line.components(separatedBy: needle).last ?? ""
   let tokens = tail.split(whereSeparator: { $0.isWhitespace || $0 == ":" || $0 == "=" })
   if let value = tokens.first(where: { number(String($0)) != nil }) {
    // ORCA thermochemistry prints units; pressure variants must retain their actual unit.
    let printedUnit = label == "Pressure" ? (tokens.last.map(String.init) ?? "") : unit
    if label != "Pressure" || ["atm", "bar", "Pa"].contains(printedUnit) {
     facts.append(SummaryFact(label:label,value:String(value),unit:printedUnit,line:i+1,job:job))
    }
   }
  }
  if line.contains("THE OPTIMIZATION HAS CONVERGED") { facts.append(SummaryFact(label:"Optimization",value:"converged",unit:"",line:i+1,job:job)) }
  if line.contains("ORCA TERMINATED NORMALLY") { facts.append(SummaryFact(label:"Termination",value:"normal",unit:"",line:i+1,job:job)); jobStart = i + 1 }
  // Only explicit echoed method/basis keywords; no inference from banners.
  let cleaned = line.trimmingCharacters(in:.whitespaces)
  if cleaned.hasPrefix("!") || (cleaned.hasPrefix("|") && cleaned.contains("> !")) {
   let value = cleaned.components(separatedBy:"!").dropFirst().joined(separator:"!").trimmingCharacters(in:.whitespaces)
   if !value.isEmpty { facts.append(SummaryFact(label:"Input keywords",value:value,unit:"",line:i+1,job:job)) }
  }
  if cleaned == "VIBRATIONAL FREQUENCIES" {
   guard let frame = geometryLines.indices.last(where: { geometryLines[$0] < i && geometryLines[$0] >= jobStart }) else { continue }
   // Freeze association at this heading; later geometries cannot receive these vectors.
   var end = i + 1
   while end < lines.count && !lines[end].contains("JOB NUMBER") && lines[end].trimmingCharacters(in:.whitespaces).lowercased() != "$new_job" && lines[end].trimmingCharacters(in:.whitespaces) != "VIBRATIONAL FREQUENCIES" { end += 1 }
   modes[frame] = parseOrcaModes(lines[i..<end].joined(separator:"\n"),atomCount:frames[frame].count)
  }
 }
 return (modes,facts)
}

// Integrated from the original MoleculeView OrcaModes.swift

/// ORCA's printed Cartesian displacement vectors, in the geometry's atom order.
/// Indices retain ORCA's zero-based numbering. Negative frequencies are imaginary.
struct VibrationalMode: Codable {
    let index: Int
    let frequency: Double
    let displacements: [SIMD3<Double>]
}

/// Read only the final frequency calculation, never mixing compound-job blocks.
/// A mode is returned only when every Cartesian component is finite and present.
static func parseOrcaModes(_ text: String, atomCount: Int) -> [VibrationalMode] {
    guard atomCount > 0, atomCount <= 10000 else { return [] }
    let dimension = atomCount * 3
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    guard let frequencyStart = lines.lastIndex(where: {
        $0.trimmingCharacters(in: .whitespaces) == "VIBRATIONAL FREQUENCIES"
    }) else { return [] }
    guard let normalStart = ((frequencyStart + 1)..<lines.count).first(where: {
        lines[$0].trimmingCharacters(in: .whitespaces) == "NORMAL MODES"
    }) else { return [] }

    func number(_ token: Substring) -> Double? {
        Double(token.replacingOccurrences(of: "D", with: "E")
            .replacingOccurrences(of: "d", with: "e"))
    }
    var frequencies: [Int: Double] = [:]
    var invalid = Set<Int>()
    for line in lines[(frequencyStart + 1)..<normalStart] {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        guard fields.count >= 3, fields[0].hasSuffix(":"),
              let index = Int(fields[0].dropLast()), index >= 0, index < dimension,
              fields[2].contains("cm") else { continue }
        guard let frequency = number(fields[1]), frequency.isFinite, abs(frequency) <= 1_000_000,
              frequencies[index] == nil else { invalid.insert(index); continue }
        frequencies[index] = frequency
    }
    var columns: [Int] = []
    var values: [Int: [Int: Double]] = [:]
    var started = false
    var componentCount = 0
    for line in lines[(normalStart + 1)...] {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        if fields.isEmpty { continue }
        // ORCA prints a column header of integers, followed by decimal-valued rows.
        let header = fields.compactMap { Int($0) }
        if header.count == fields.count, header.allSatisfy({ $0 >= 0 && $0 < dimension }) {
            columns = header
            if Set(header).count != header.count { invalid.formUnion(header) }
            started = true
            continue
        }
        guard started else { continue }
        guard let row = Int(fields[0]) else {
            // The next spectrum/thermochemistry heading terminates the matrix.
            if fields.contains(where: { $0.contains(where: { $0.isLetter }) }) { break }
            continue
        }
        guard row >= 0, row < dimension else { invalid.formUnion(columns); continue }
        guard fields.count == columns.count + 1 else {
            invalid.formUnion(columns)
            continue
        }
        for (offset, index) in columns.enumerated() {
            guard let value = number(fields[offset + 1]), value.isFinite, abs(value) <= 1000,
                  values[index]?[row] == nil else {
                invalid.insert(index)
                continue
            }
            componentCount += 1
            guard componentCount <= 2_000_000 else { return [] }
            values[index, default: [:]][row] = value
        }
    }
    return frequencies.keys.sorted().compactMap { index in
        guard !invalid.contains(index), let frequency = frequencies[index],
              let vector = values[index], vector.count == dimension else { return nil }
        let displacements = (0..<atomCount).map { atom in
            SIMD3<Double>(vector[atom * 3]!, vector[atom * 3 + 1]!, vector[atom * 3 + 2]!)
        }
        return VibrationalMode(index: index, frequency: frequency, displacements: displacements)
    }
}

// Integrated from the original MoleculeView Editing.swift

static func position(_ a: Atom) -> SIMD3<Double> { SIMD3(a.x, a.y, a.z) }
static func movedAtom(_ a: Atom, _ p: SIMD3<Double>) -> Atom { Atom(symbol: a.symbol, x: p.x, y: p.y, z: p.z) }

static func transformedAtoms(_ atoms: [Atom], selection: Set<Int>, translation: SIMD3<Double>, axis: SIMD3<Double>, radians: Double, pivot: SIMD3<Double>) -> [Atom] {
    let length = VectorMath.length(axis)
    let unit = length > 1e-12 ? axis / length : SIMD3<Double>(0, 0, 1)
    let angle = length > 1e-12 ? radians : 0
    let c = cos(angle), s = sin(angle)
    return atoms.enumerated().map { i, a in
        guard selection.contains(i) else { return a }
        let v = position(a) - pivot
        let rotated = v * c + VectorMath.cross(unit, v) * s + unit * VectorMath.dot(unit, v) * (1 - c)
        return movedAtom(a, pivot + rotated + translation)
    }
}

static let editingRadii: [String: Double] = ["H":0.31,"He":0.28,"Li":1.28,"Be":0.96,"B":0.84,"C":0.76,"N":0.71,"O":0.66,"F":0.57,"Ne":0.58,"Na":1.66,"Mg":1.41,"Al":1.21,"Si":1.11,"P":1.07,"S":1.05,"Cl":1.02,"Ar":1.06,"K":2.03,"Ca":1.76,"Sc":1.70,"Ti":1.60,"V":1.53,"Cr":1.39,"Mn":1.39,"Fe":1.32,"Co":1.26,"Ni":1.24,"Cu":1.32,"Zn":1.22,"Ga":1.22,"Ge":1.20,"As":1.19,"Se":1.20,"Br":1.20,"Kr":1.16,"Rb":2.20,"Sr":1.95,"Y":1.90,"Zr":1.75,"Nb":1.64,"Mo":1.54,"Ru":1.46,"Rh":1.42,"Pd":1.39,"Ag":1.45,"Cd":1.44,"In":1.42,"Sn":1.39,"Sb":1.39,"Te":1.38,"I":1.39,"Xe":1.40,"Cs":2.44,"Ba":2.15,"Pt":1.36,"Au":1.36,"Hg":1.32,"Pb":1.46]
private struct BondCell: Hashable { let x: Int; let y: Int; let z: Int }

/// Distance-based connectivity is a visualization heuristic, not a bond-order assignment.
static func inferredBondPairs(_ atoms: [Atom]) -> [(Int, Int)] {
    let radii = atoms.map { editingRadii[$0.symbol] ?? 1.4 }
    let width = max(1, 2 * (radii.max() ?? 1.4) * 1.25)
    var grid: [BondCell: [Int]] = [:]
    var pairs: [(Int, Int)] = []
    // Bound candidate work for pathological coincident or excessively dense inputs.
    var comparisons = 0
    for (i, atom) in atoms.enumerated() {
        let p = position(atom)
        guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
        let coords = p / width
        guard abs(coords.x) < Double(Int.max / 2), abs(coords.y) < Double(Int.max / 2), abs(coords.z) < Double(Int.max / 2) else { continue }
        let cell = BondCell(x: Int(floor(coords.x)), y: Int(floor(coords.y)), z: Int(floor(coords.z)))
        for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
            for j in grid[BondCell(x: cell.x + dx, y: cell.y + dy, z: cell.z + dz)] ?? [] {
                comparisons += 1
                if comparisons > 2_000_000 { return pairs }
                let d = VectorMath.length(p - position(atoms[j]))
                if d > 0.35 && d <= 1.25 * (radii[i] + radii[j]) {
                    pairs.append((j, i))
                    if pairs.count >= 30_000 { return pairs }
                }
            }
        } } }
        grid[cell, default: []].append(i)
    }
    return pairs
}

static func connectedAtomSelection(_ atoms: [Atom], seed: Int) -> Set<Int> {
    guard atoms.indices.contains(seed) else { return [] }
    var adjacency = Array(repeating: [Int](), count: atoms.count)
    for (a, b) in inferredBondPairs(atoms) { adjacency[a].append(b); adjacency[b].append(a) }
    var visited: Set<Int> = [seed], queue = [seed], cursor = 0
    while cursor < queue.count {
        let current = queue[cursor]; cursor += 1
        for next in adjacency[current] where !visited.contains(next) { visited.insert(next); queue.append(next) }
    }
    return visited
}

private static func fragmentAtom(_ symbol: String, _ x: Double, _ y: Double, _ z: Double = 0) -> Atom { Atom(symbol: symbol, x: x, y: y, z: z) }
static let builtInFragments: [(name: String, atoms: [Atom])] = {
    let tetra = 1.09 / sqrt(3.0)
    var benzene: [Atom] = []
    for i in 0..<6 {
        let angle = Double(i) * Double.pi / 3
        benzene.append(fragmentAtom("C", 1.397 * cos(angle), 1.397 * sin(angle)))
    }
    for i in 0..<6 {
        let angle = Double(i) * Double.pi / 3
        benzene.append(fragmentAtom("H", 2.477 * cos(angle), 2.477 * sin(angle)))
    }
    return [
        ("Water", [fragmentAtom("O",0,0), fragmentAtom("H",0.9572,0), fragmentAtom("H",-0.23999,0.92663)]),
        ("Methane", [fragmentAtom("C",0,0), fragmentAtom("H",tetra,tetra,tetra), fragmentAtom("H",tetra,-tetra,-tetra), fragmentAtom("H",-tetra,tetra,-tetra), fragmentAtom("H",-tetra,-tetra,tetra)]),
        ("Ammonia", [fragmentAtom("N",0,0,0.117), fragmentAtom("H",0.9377,0,-0.264), fragmentAtom("H",-0.46885,0.81207,-0.264), fragmentAtom("H",-0.46885,-0.81207,-0.264)]),
        ("Methyl", [fragmentAtom("C",0,0), fragmentAtom("X",tetra,tetra,tetra), fragmentAtom("H",tetra,-tetra,-tetra), fragmentAtom("H",-tetra,tetra,-tetra), fragmentAtom("H",-tetra,-tetra,tetra)]),
        ("Carbonyl", [fragmentAtom("C",0,0), fragmentAtom("O",1.21,0), fragmentAtom("H",-0.55,0.953), fragmentAtom("X",-0.55,-0.953)]),
        ("Benzene", benzene),
        ("Ethylene", [fragmentAtom("C",-0.669,0), fragmentAtom("C",0.669,0), fragmentAtom("H",-1.232,0.924), fragmentAtom("H",-1.232,-0.924), fragmentAtom("H",1.232,0.924), fragmentAtom("H",1.232,-0.924)])
    ]
}()

struct FragmentAttachment {
    let atoms: [Atom]
    let insertedIndices: Set<Int>
}
struct EditingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Replace one terminal H/dummy at each end with a rigidly aligned fragment.
/// Covalent radii supply an initial bond length, without an energy minimization.
static func attachFragment(host: [Atom], hostLeaving: Int, fragment: [Atom], fragmentLeaving: Int, bondLength: Double? = nil) throws -> FragmentAttachment {
    func anchor(_ atoms: [Atom], _ leaving: Int) throws -> Int {
        guard atoms.indices.contains(leaving), ["H", "X", "Du"].contains(atoms[leaving].symbol) else {
            throw EditingError(message: "Choose a leaving hydrogen or dummy atom at each attachment site.")
        }
        let candidates = atoms.indices.filter { $0 != leaving && !["H", "X", "Du"].contains(atoms[$0].symbol) }
        guard let nearest = candidates.min(by: { VectorMath.distance(position(atoms[$0]), position(atoms[leaving])) < VectorMath.distance(position(atoms[$1]), position(atoms[leaving])) }) else {
            throw EditingError(message: "The leaving atom needs a heavy-atom anchor.")
        }
        let distance = VectorMath.distance(position(atoms[nearest]), position(atoms[leaving]))
        guard distance.isFinite, distance > 0.1, distance < 2.6 else {
            throw EditingError(message: "The leaving atom is too far from an attachment anchor.")
        }
        // Hydrogen must have a unique inferred neighbor; dummy coordinates define
        // their anchor explicitly by the closest heavy atom rather than a radius.
        if atoms[leaving].symbol == "H" {
            let neighbors = inferredBondPairs(atoms).compactMap { a, b -> Int? in a == leaving ? b : (b == leaving ? a : nil) }
            guard neighbors.count == 1, neighbors[0] == nearest else {
                throw EditingError(message: "Choose a terminal hydrogen bonded to exactly one heavy atom.")
            }
        }
        return nearest
    }
    guard host.count + fragment.count <= 10_002,
          (host + fragment).allSatisfy({ position($0).x.isFinite && position($0).y.isFinite && position($0).z.isFinite }) else {
        throw EditingError(message: "Invalid coordinates or too many atoms for attachment.")
    }
    let h = try anchor(host, hostLeaving), f = try anchor(fragment, fragmentLeaving)
    let direction = VectorMath.normalize(position(host[hostLeaving]) - position(host[h]))
    let source = VectorMath.normalize(position(fragment[fragmentLeaving]) - position(fragment[f]))
    let target = -direction
    let dot = max(-1.0, min(1.0, VectorMath.dot(source, target)))
    var axis = VectorMath.cross(source, target)
    if VectorMath.length(axis) < 1e-10 {
        axis = VectorMath.cross(source, abs(source.x) < 0.8 ? SIMD3<Double>(1,0,0) : SIMD3<Double>(0,1,0))
    }
    let length = bondLength ?? ((editingRadii[host[h].symbol] ?? 0.76) + (editingRadii[fragment[f].symbol] ?? 0.76))
    guard length.isFinite, length >= 0.5, length <= 4 else {
        throw EditingError(message: "Attachment bond length must be between 0.5 and 4 Å.")
    }
    let rotated = transformedAtoms(fragment, selection: Set(fragment.indices), translation: .zero, axis: axis, radians: acos(dot), pivot: position(fragment[f]))
    let destination = position(host[h]) + direction * length
    let offset = destination - position(rotated[f])
    let keptHost = host.enumerated().filter { $0.offset != hostLeaving }.map(\.element)
    let inserted = rotated.enumerated().filter { $0.offset != fragmentLeaving }.map { movedAtom($0.element, position($0.element) + offset) }
    return FragmentAttachment(atoms: keptHost + inserted, insertedIndices: Set(keptHost.count..<(keptHost.count + inserted.count)))
}

// Integrated from the original MoleculeView EditingState.swift

/// A bounded editable snapshot. Source calculation data remains outside this model.
struct EditableProject: Codable {
    var atoms: [Atom]
    var groups: [[Int]]
    var selection: [Int]
    var charge: Int
    var multiplicity: Int
    init(atoms: [Atom], groups: [[Int]] = [], selection: [Int] = [], charge: Int = 0, multiplicity: Int = 1) {
        self.atoms = atoms; self.groups = groups; self.selection = selection
        self.charge = charge; self.multiplicity = multiplicity
    }
    enum CodingKeys: String, CodingKey { case atoms, groups, selection, charge, multiplicity }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        atoms = try c.decode([Atom].self, forKey: .atoms)
        groups = try c.decodeIfPresent([[Int]].self, forKey: .groups) ?? []
        selection = try c.decodeIfPresent([Int].self, forKey: .selection) ?? []
        charge = try c.decodeIfPresent(Int.self, forKey: .charge) ?? 0
        multiplicity = try c.decodeIfPresent(Int.self, forKey: .multiplicity) ?? 1
        try validate()
    }
    func validate() throws {
        guard atoms.count <= 10_000, atoms.allSatisfy({ elements.contains($0.symbol) && [$0.x,$0.y,$0.z].allSatisfy { $0.isFinite && abs($0) < 1e6 } }) else {
            throw EditingError(message: "Project contains invalid atoms or exceeds 10,000 atoms.")
        }
        guard selection.count <= atoms.count, Set(selection).count == selection.count,
              selection.allSatisfy({ atoms.indices.contains($0) }), groups.count <= 10_000,
              groups.reduce(0, { $0 + $1.count }) <= 100_000,
              groups.allSatisfy({ Set($0).count == $0.count && $0.allSatisfy { atoms.indices.contains($0) } }) else {
            throw EditingError(message: "Project contains invalid selection or fragment indices.")
        }
        guard (-1000...1000).contains(charge), (1...1000).contains(multiplicity) else {
            throw EditingError(message: "Charge must be between −1000 and 1000; multiplicity must be 1–1000.")
        }
    }
    func deleting(_ indices: Set<Int>) throws -> EditableProject {
        try validate()
        guard indices.allSatisfy({ atoms.indices.contains($0) }) else { throw EditingError(message: "Invalid deleted atom index.") }
        var map: [Int:Int] = [:], kept: [Atom] = []
        for i in atoms.indices where !indices.contains(i) { map[i] = kept.count; kept.append(atoms[i]) }
        let project = EditableProject(atoms: kept, groups: groups.map { $0.compactMap { map[$0] } }.filter { !$0.isEmpty }, selection: selection.compactMap { map[$0] }, charge: charge, multiplicity: multiplicity)
        try project.validate(); return project
    }
    func appending(_ added: [Atom]) throws -> EditableProject {
        let indices = Array(atoms.count..<(atoms.count + added.count))
        let p = EditableProject(atoms: atoms + added, groups: groups + (indices.isEmpty ? [] : [indices]), selection: indices, charge: charge, multiplicity: multiplicity)
        try p.validate(); return p
    }
    func attaching(_ result: FragmentAttachment, hostLeaving: Int) throws -> EditableProject {
        let kept = try deleting([hostLeaving])
        guard result.atoms.count >= kept.atoms.count,
              result.insertedIndices == Set(kept.atoms.count..<result.atoms.count) else { throw EditingError(message: "Invalid attachment result indices.") }
        let p = EditableProject(atoms: result.atoms, groups: kept.groups + [result.insertedIndices.sorted()], selection: result.insertedIndices.sorted(), charge: charge, multiplicity: multiplicity)
        try p.validate(); return p
    }
    private func exportRows() throws -> String {
        try validate()
        guard !atoms.isEmpty, !atoms.contains(where: { $0.symbol == "X" }) else { throw EditingError(message: "Export needs real atoms; remove remaining dummy sites first.") }
        let locale = Locale(identifier: "en_US_POSIX")
        return atoms.map { String(format: "%@ %.10f %.10f %.10f", locale: locale, $0.symbol, $0.x, $0.y, $0.z) }.joined(separator: "\n")
    }
    func xyzText() throws -> String { "\(atoms.count)\nChemViewer; Angstrom; initial geometry approximation\n\(try exportRows())\n" }
    func orcaGeometryText() throws -> String { "# Coordinates in Angstrom; initial geometry approximation\n* xyz \(charge) \(multiplicity)\n\(try exportRows())\n*\n" }
}

struct ProjectHistory {
    private(set) var current: EditableProject
    private var past: [EditableProject] = []
    private var future: [EditableProject] = []
    private let limit: Int
    init(_ project: EditableProject, limit: Int = 100) throws {
        try project.validate(); current = project; self.limit = max(1, min(100, limit))
    }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    mutating func apply(_ project: EditableProject) throws {
        try project.validate(); past.append(current)
        if past.count > limit { past.removeFirst(past.count - limit) }
        current = project; future.removeAll()
    }
    @discardableResult mutating func undo() -> Bool {
        guard let p = past.popLast() else { return false }; future.append(current); current = p; return true
    }
    @discardableResult mutating func redo() -> Bool {
        guard let p = future.popLast() else { return false }; past.append(current); current = p; return true
    }
}

}
