import SwiftUI
import RestFlowCore

/// Original vector scenes; no downloads, external assets or third-party artwork.
struct BuiltinVisualView: View {
    let visual: BuiltinVisual
    var isPaused = false
    var language: AppLanguage = .simplifiedChinese
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mint = Color(red: 0.63, green: 0.89, blue: 0.76)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: isPaused || reduceMotion)) { timeline in
            Canvas { context, size in
                let sx = size.width / 400, sy = size.height / 250
                context.scaleBy(x: sx, y: sy)
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                draw(in: &context, time: time)
            }
        }.accessibilityLabel(visual.title(in: language))
    }

    private func draw(in c: inout GraphicsContext, time t: Double) {
        func circle(_ x: Double, _ y: Double, _ radius: Double, _ color: Color) {
            c.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }
        func stroke(_ points: [CGPoint], color: Color, width: Double = 1) {
            guard let first = points.first else { return }
            var path = Path(); path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        func polygon(_ points: [CGPoint], color: Color) {
            var path = Path(); path.addLines(points); path.closeSubpath()
            c.fill(path, with: .color(color))
        }
        switch visual {
        case .rings:
            let breath = 1 + 0.06 * sin(t * .pi / 4)
            for i in 0..<4 {
                let r = Double(42 + i * 22) * breath
                c.stroke(Path(ellipseIn: CGRect(x: 200-r, y: 125-r, width: r*2, height: r*2)),
                         with: .color(mint.opacity(0.18 + Double(i) * 0.08)), lineWidth: 1.2)
            }
            circle(200, 125, 30 * breath, mint.opacity(0.22))
        case .orbit:
            for i in 0..<3 {
                let r = Double(42 + i * 30)
                c.stroke(Path(ellipseIn: CGRect(x: 200-r, y: 125-r, width: r*2, height: r*2)), with: .color(mint.opacity(0.13)), lineWidth: 1)
                let a = t * (0.16 + Double(i) * 0.04) + Double(i) * 2
                circle(200 + cos(a)*r, 125 + sin(a)*r, Double(5+i), mint.opacity(0.8))
            }
            circle(200, 125, 14, mint.opacity(0.5))
        case .waves:
            for row in 0..<5 {
                let points = (0...80).map { i -> CGPoint in
                    let x = Double(i)*5
                    return CGPoint(x: x, y: 78 + Double(row)*27 + sin(x/55 + t*0.38 + Double(row)*0.65)*13)
                }
                stroke(points, color: mint.opacity(0.18 + Double(row)*0.1), width: 2)
            }
        case .rain:
            for i in 0..<28 {
                let x = Double((i*71)%360 + 20)
                let y = (Double(i*37) + t*24).truncatingRemainder(dividingBy: 200)+10
                stroke([CGPoint(x:x,y:y),CGPoint(x:x-3,y:y+13)], color: mint.opacity(0.2+Double(i%4)*0.1), width: 1.5)
            }
            for i in 0..<3 {
                let r = 20 + (t*7 + Double(i)*20).truncatingRemainder(dividingBy: 55)
                c.stroke(Path(ellipseIn: CGRect(x:200-r,y:217-r/5,width:r*2,height:r*0.4)), with: .color(mint.opacity(0.25)), lineWidth: 1)
            }
        case .sunrise:
            let sun = Color(red: 1, green: 0.79, blue: 0.48)
            for i in (0..<4).reversed() { circle(200, 132, Double(37+i*16), sun.opacity(0.035)) }
            circle(200, 132, 37, sun.opacity(0.85))
            for i in 0..<6 {
                let y = 163 + Double(i)*12
                let half = 65 - Double(i)*8 + sin(t*0.4+Double(i))*4
                stroke([CGPoint(x:200-half,y:y),CGPoint(x:200+half,y:y)],color:sun.opacity(0.38-Double(i)*0.045),width:2)
            }
            stroke([CGPoint(x:40,y:155),CGPoint(x:360,y:155)],color:mint.opacity(0.3))
        case .mountains:
            circle(296, 62, 22, Color.white.opacity(0.45))
            polygon([.init(x:12,y:211),.init(x:119,y:68),.init(x:220,y:211)],color:mint.opacity(0.18))
            polygon([.init(x:100,y:211),.init(x:245,y:48),.init(x:390,y:211)],color:mint.opacity(0.28))
            polygon([.init(x:75,y:211),.init(x:168,y:117),.init(x:280,y:211)],color:mint.opacity(0.4))
            polygon([.init(x:225,y:70),.init(x:245,y:48),.init(x:272,y:78),.init(x:247,y:69),.init(x:239,y:78)],color:Color.white.opacity(0.5))
            stroke([.init(x:25,y:222),.init(x:375,y:222)],color:mint.opacity(0.2))
        case .forest:
            for i in 0..<7 {
                let x = 40 + Double(i)*53, h = Double(65+(i*31)%75), y = 213.0
                let color = mint.opacity(0.18 + Double(i%3)*0.13)
                stroke([.init(x:x,y:y),.init(x:x,y:y-h)],color:color,width:3)
                for branch in 0..<3 {
                    let top = y-h+Double(branch)*h*0.23, half = 17+Double(branch)*9
                    polygon([.init(x:x,y:top),.init(x:x-half,y:top+h*0.48),.init(x:x+half,y:top+h*0.48)],color:color)
                }
            }
            circle(318, 43, 14, mint.opacity(0.35))
        case .lotus:
            let opening = 0.7 + sin(t * .pi / 5)*0.06
            for i in -3...3 {
                var petal = Path()
                petal.move(to: CGPoint(x:200,y:205))
                let x = 200 + Double(i)*44*opening, y = 50+Double(abs(i))*20
                petal.addQuadCurve(to: CGPoint(x:x,y:y),control:CGPoint(x:126+Double(i)*25,y:110))
                petal.addQuadCurve(to: CGPoint(x:200,y:205),control:CGPoint(x:274+Double(i)*25,y:110))
                c.fill(petal,with:.color(mint.opacity(0.11)))
                c.stroke(petal,with:.color(mint.opacity(0.5)),lineWidth:1)
            }
            stroke([.init(x:100,y:218),.init(x:300,y:218)],color:mint.opacity(0.2))
        case .stars:
            for i in 0..<40 {
                let x = Double((i*83)%350+25), y = Double((i*53)%190+25)
                let glow = 0.3 + 0.3 * (1 + sin(t*0.5+Double(i))) / 2
                circle(x,y,Double(i%3+1),mint.opacity(glow))
            }
            c.stroke(Path(ellipseIn:CGRect(x:270,y:35,width:43,height:43)),with:.color(mint.opacity(0.7)),lineWidth:2)
        case .bamboo:
            for i in 0..<5 {
                let x = 70 + Double(i)*65, sway = sin(t*0.22+Double(i))*3
                stroke([.init(x:x,y:230),.init(x:x+sway,y:25)],color:mint.opacity(0.5),width:4)
                for j in 0..<4 {
                    let y = 54+Double(j)*44
                    stroke([.init(x:x-4,y:y),.init(x:x+4,y:y)],color:mint.opacity(0.7),width:2)
                    let sign = (i+j)%2 == 0 ? 1.0 : -1.0
                    var leaf = Path()
                    leaf.move(to:.init(x:x,y:y))
                    leaf.addQuadCurve(to:.init(x:x+sign*48,y:y-24),control:.init(x:x+sign*12,y:y-35))
                    leaf.addQuadCurve(to:.init(x:x,y:y),control:.init(x:x+sign*37,y:y+3))
                    c.fill(leaf,with:.color(mint.opacity(0.25)))
                }
            }
        case .fireflies:
            for i in 0..<22 {
                let x = Double((i*79)%340+30)+sin(t*0.25+Double(i))*9
                let y = Double((i*47)%180+35)+cos(t*0.21+Double(i))*8
                let glow = 0.25+0.5*(1+sin(t*0.65+Double(i)*1.8))/2
                circle(x,y,9,mint.opacity(glow*0.06))
                circle(x,y,4,mint.opacity(glow*0.16))
                circle(x,y,1.8,Color(red:0.86,green:1,blue:0.61).opacity(glow))
            }
        case .clouds:
            circle(294,62,24,Color(red:1,green:0.84,blue:0.6).opacity(0.65))
            for i in 0..<3 {
                let x = 105 + Double(i)*78 + sin(t*0.13+Double(i))*16, y = 82 + Double(i)*47
                var cloud = Path()
                cloud.addRoundedRect(in:CGRect(x:x-63,y:y,width:126,height:28),cornerSize:CGSize(width:14,height:14))
                cloud.addEllipse(in:CGRect(x:x-38,y:y-22,width:52,height:52))
                cloud.addEllipse(in:CGRect(x:x-4,y:y-13,width:44,height:44))
                c.fill(cloud,with:.color(mint.opacity(0.2+Double(i)*0.1)))
            }
        }
    }
}
