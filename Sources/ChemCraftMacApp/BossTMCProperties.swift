import SwiftUI

/// Display metadata only: exports and queries retain the original column keys/units.
enum BossTMCProperties {
    static let hidden = Set("xyz mol2 mulliken_charges lowdin_charges mulliken_spins lowdin_spins geometry_details bond_lengths metal_ligand_bond_lengths coordinating_atoms metal_index dipole_moment_debye".split(separator:" ").map(String.init))
    static let categorical = Set("metal geometry charge spinmult ox_state coordination_number".split(separator:" ").map(String.init))
    static let names: [String:String] = [
        "refcode":"Reference code", "metal":"Metal", "charge":"Molecular charge", "spinmult":"Spin multiplicity", "ox_state":"Oxidation state", "geometry":"Coordination geometry", "coordination_number":"Coordination number", "molecular_formula":"Molecular formula", "coordination_formula":"Coordination formula", "natoms":"Atom count", "mw":"Molecular weight", "electronic_energy_Eh":"Electronic energy", "alpha_HOMO_Eh":"α HOMO energy", "beta_HOMO_Eh":"β HOMO energy", "alpha_LUMO_Eh":"α LUMO energy", "beta_LUMO_Eh":"β LUMO energy", "alpha_gap_Eh":"α HOMO–LUMO gap", "beta_gap_Eh":"β HOMO–LUMO gap", "energetic_gap_eV":"Energy gap", "dipole_magnitude_debye":"Dipole magnitude", "spin_contamination":"Spin contamination", "metal_lowdin_charge":"Metal Löwdin charge", "metal_lowdin_spin":"Metal Löwdin spin", "metal_mulliken_charge":"Metal Mulliken charge", "metal_mulliken_spin":"Metal Mulliken spin", "IS-LS_VSSE_kcal_mol":"Intermediate–low spin VSSE", "HS-LS_VSSE_kcal_mol":"High–low spin VSSE", "HS-IS_VSSE_kcal_mol":"High–intermediate spin VSSE", "atomization_energy_Eh":"Atomization energy", "relative_AE_kcal_g":"Relative atomization energy", "csd_r_factor":"CSD R factor"
    ]
    static func name(_ key:String)->String {names[key] ?? key.replacingOccurrences(of:"_",with:" ")}
    static func unit(_ key:String)->String {
        if key.hasSuffix("_Eh"){return "Eh"};if key.hasSuffix("_eV"){return "eV"};if key.hasSuffix("_kcal_mol"){return "kcal/mol"};if key.hasSuffix("_kcal_g"){return "kcal/g"};if key.contains("debye"){return "D"};if key=="mw"{return "g/mol"};return ""
    }
    static func title(_ key:String)->String {name(key)+(unit(key).isEmpty ? "":" (\(unit(key)))")}
    static func group(_ key:String)->String {
        if key.contains("VSSE") || key.contains("atomization") || key=="relative_AE_kcal_g"{return "Spin-state & atomization energies"}
        if key=="geometry" || key=="coordination_number" || key=="coordination_formula"{return "Coordination geometry"}
        if key=="spin_contamination" || key=="csd_r_factor"{return "Data quality"}
        if key.contains("HOMO") || key.contains("LUMO") || key.contains("gap") || key.contains("metal_") || key.contains("dipole") || key=="electronic_energy_Eh"{return "Electronic structure"}
        return "Composition"
    }
    static func number(_ text:String)->Double? {guard let v=Double(text.replacingOccurrences(of:"D",with:"E").replacingOccurrences(of:"d",with:"e")),v.isFinite else{return nil};return v}
    static func formatted(_ value:Double)->String {String(format:"%.6g",value)}
}

struct BossTMCRangeSlider: View {
    @Binding var lower:String
    @Binding var upper:String
    let minimum:Double
    let maximum:Double
    private func value(_ text:String,_ fallback:Double)->Double {BossTMCProperties.number(text) ?? fallback}
    var body: some View {
        GeometryReader { geo in
            let width=max(1,geo.size.width-18), span=max(Double.leastNormalMagnitude,maximum-minimum)
            let lo=min(1,max(0,(value(lower,minimum)-minimum)/span)), hi=min(1,max(0,(value(upper,maximum)-minimum)/span))
            ZStack(alignment:.leading){
                Capsule().fill(Color.secondary.opacity(0.2)).frame(height:4).padding(.horizontal,9)
                Capsule().fill(Color.accentColor).frame(width:max(0,CGFloat(hi-lo)*width),height:4).offset(x:9+CGFloat(lo)*width)
                thumb.offset(x:CGFloat(lo)*width).gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("range")).onChanged{g in let v=minimum+min(1,max(0,(g.location.x-9)/width))*span;lower=String(min(v,value(upper,maximum))) }).accessibilityLabel("Minimum")
                thumb.offset(x:CGFloat(hi)*width).gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("range")).onChanged{g in let v=minimum+min(1,max(0,(g.location.x-9)/width))*span;upper=String(max(v,value(lower,minimum))) }).accessibilityLabel("Maximum")
            }.frame(height:24).coordinateSpace(name:"range")
        }.frame(height:24)
    }
    private var thumb: some View {Circle().fill(Color(nsColor:.controlBackgroundColor)).overlay(Circle().stroke(Color.accentColor,lineWidth:2)).frame(width:18,height:18).shadow(radius:1)}
}
