import SwiftUI

struct BossTMCGraphs: View {
    @ObservedObject var catalog: BossTMCStore
    private var selected:Double? {catalog.details[catalog.graphProperty].flatMap(BossTMCProperties.number)}
    private var orbitals:[(String,Double)] { ["alpha_HOMO_Eh","alpha_LUMO_Eh","beta_HOMO_Eh","beta_LUMO_Eh"].compactMap{key in guard let v=catalog.details[key].flatMap(BossTMCProperties.number) else{return nil};return (BossTMCProperties.name(key),v)} }
    private var dipole:[(String,Double)] {
        guard let raw=catalog.details["dipole_moment_debye"],let data=raw.data(using:.utf8),let components=try? JSONSerialization.jsonObject(with:data) as? [Double],components.count==3,components.allSatisfy({$0.isFinite}) else{return []}
        return zip(["x","y","z"],components).map{($0,$1)}
    }
    var body: some View {
        ScrollView{VStack(alignment:.leading,spacing:14){
            Text("PROPERTY DISTRIBUTION").font(.caption.bold())
            Picker("Property",selection:$catalog.graphProperty){ForEach(catalog.headers.filter{BossTMCStore.numericProperties.contains($0) && !BossTMCProperties.hidden.contains($0)},id:\.self){Text(BossTMCProperties.title($0)).tag($0)}}.labelsHidden()
            if catalog.histogram.isEmpty{Text(catalog.graphStatus).font(.caption).foregroundStyle(.secondary)}else{
                distribution.frame(height:155)
                Text("Horizontal: \(BossTMCProperties.title(catalog.graphProperty)) · Vertical: record count").font(.caption2).foregroundStyle(.secondary)
                if let selected{Label("Selected: \(BossTMCProperties.formatted(selected)) \(BossTMCProperties.unit(catalog.graphProperty))",systemImage:"line.diagonal").font(.caption).foregroundStyle(.orange)}else{Text("Select a molecule with this descriptor to mark its position.").font(.caption).foregroundStyle(.secondary)}
                Text(catalog.graphStatus).font(.caption2).foregroundStyle(.secondary)
            }
            if !orbitals.isEmpty{Divider();Text("ORBITAL ENERGIES · Eh").font(.caption.bold());orbitalPlot.frame(height:190);Text("CSV orbital eigenvalues; α and β remain separate.").font(.caption2).foregroundStyle(.secondary)}
            if !dipole.isEmpty{Divider();Text("DIPOLE COMPONENTS · D").font(.caption.bold());ForEach(dipole,id:\.0){component in HStack{Text(component.0).frame(width:15);GeometryReader{g in let extent=dipole.map{abs($0.1)}.max() ?? 1;let fraction=abs(component.1)/max(extent,1e-12);ZStack(alignment:.leading){Capsule().fill(Color.secondary.opacity(0.1));Capsule().fill(component.1<0 ? Color.teal:Color.accentColor).frame(width:max(1,g.size.width*fraction))}}.frame(height:9);Text(BossTMCProperties.formatted(component.1)).font(.caption.monospaced()).frame(width:80,alignment:.trailing)}}}
            if catalog.details.isEmpty{Text("Select a candidate for its orbital energies, dipole components and position in the catalog distribution.").font(.caption).foregroundStyle(.secondary)}
        }.padding(.vertical,4).padding(.trailing,5)}
    }
    private var distribution: some View {
        Canvas{context,size in
            let bins=catalog.histogram
            guard let first=bins.first,let last=bins.last else{return}
            let left:CGFloat=38,bottom=size.height-25,plotWidth=max(1,size.width-left-10),plotHeight=max(1,bottom-12)
            let peak=max(1,bins.map(\.count).max() ?? 1),span=max(last.upper-first.lower,1e-12)
            for b in bins{let x=left+CGFloat((b.lower-first.lower)/span)*plotWidth,w=max(1,CGFloat((b.upper-b.lower)/span)*plotWidth-1),h=CGFloat(b.count/peak)*plotHeight;context.fill(Path(CGRect(x:x,y:bottom-h,width:w,height:h)),with:.color(.accentColor.opacity(0.65)))}
            var axes=Path();axes.move(to:CGPoint(x:left,y:8));axes.addLine(to:CGPoint(x:left,y:bottom));axes.addLine(to:CGPoint(x:size.width-5,y:bottom));context.stroke(axes,with:.color(.secondary),lineWidth:1)
            context.draw(Text("\(Int(peak))").font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:left-4,y:12),anchor:.trailing)
            context.draw(Text(BossTMCProperties.formatted(first.lower)).font(.system(size:9)),at:CGPoint(x:left,y:bottom+14),anchor:.leading)
            context.draw(Text(BossTMCProperties.formatted(last.upper)).font(.system(size:9)),at:CGPoint(x:size.width-5,y:bottom+14),anchor:.trailing)
            if let v=selected{let x=left+CGFloat(min(1,max(0,(v-first.lower)/span)))*plotWidth;var marker=Path();marker.move(to:CGPoint(x:x,y:8));marker.addLine(to:CGPoint(x:x,y:bottom));context.stroke(marker,with:.color(.orange),lineWidth:2)}
        }
    }
    private var orbitalPlot: some View {
        Canvas{context,size in
            let values=orbitals,low=values.map(\.1).min() ?? 0,high=values.map(\.1).max() ?? 1,span=max(high-low,0.01)
            for (i,value) in values.enumerated(){let x=CGFloat(i)*size.width/CGFloat(values.count),y=20+CGFloat((high-value.1)/span)*(size.height-75);var line=Path();line.move(to:CGPoint(x:x+8,y:y));line.addLine(to:CGPoint(x:x+size.width/CGFloat(values.count)-8,y:y));context.stroke(line,with:.color(i<2 ? .teal:.purple),lineWidth:3)
                context.draw(Text(BossTMCProperties.formatted(value.1)).font(.system(size:10,design:.monospaced)),at:CGPoint(x:x+size.width/CGFloat(values.count)/2,y:y+13))
                context.draw(Text(value.0.replacingOccurrences(of:" energy",with:"")).font(.system(size:10)),at:CGPoint(x:x+size.width/CGFloat(values.count)/2,y:size.height-10))
            }
        }
    }
}
