import AppKit

@MainActor enum WheelGeometry {
    static let size: CGFloat = 236
    static let paths = OrbitAction.allCases.map { contour($0.angle) }
    static let combined: CGPath = {
        let path = CGMutablePath(); paths.forEach { path.addPath($0) }; return path
    }()
    static func action(at point: CGPoint) -> OrbitAction? {
        for (i,path) in paths.enumerated() where path.contains(point) { return OrbitAction.allCases[i] }
        return nil
    }
    static func polar(_ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x:118 + radius * sin(angle),y:118 - radius * cos(angle))
    }
    private static func plus(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x:a.x+b.x,y:a.y+b.y) }
    private static func scaled(_ a: CGPoint,_ s: CGFloat) -> CGPoint { CGPoint(x:a.x*s,y:a.y*s) }
    private static func unit(_ angle: Double) -> CGPoint { CGPoint(x:sin(angle),y:-cos(angle)) }
    private static func tangent(_ angle: Double) -> CGPoint { CGPoint(x:cos(angle),y:sin(angle)) }
    private static func transition(_ path: CGMutablePath,_ p0: CGPoint,_ v0: CGPoint,_ a0: CGPoint,_ p1: CGPoint,_ v1: CGPoint,_ a1: CGPoint) {
        let b1 = plus(p0,scaled(v0,0.2)), b4 = plus(p1,scaled(v1,-0.2))
        let b2 = plus(plus(scaled(a0,0.05),scaled(b1,2)),scaled(p0,-1))
        let b3 = plus(plus(scaled(a1,0.05),scaled(b4,2)),scaled(p1,-1))
        let points = [p0,b1,b2,b3,b4,p1]
        let derivatives = (0..<5).map { plus(scaled(points[$0+1],5),scaled(points[$0],-5)) }
        func at(_ control:[CGPoint],_ t:CGFloat) -> CGPoint {
            var level = control
            while level.count > 1 { level = (0..<(level.count-1)).map { plus(scaled(level[$0],1-t),scaled(level[$0+1],t)) } }
            return level[0]
        }
        for i in 0..<8 {
            let t0 = CGFloat(i)/8, t1 = CGFloat(i+1)/8
            let p = at(points,t0), q = at(points,t1)
            path.addCurve(to:q,control1:plus(p,scaled(at(derivatives,t0),1/24)),control2:plus(q,scaled(at(derivatives,t1),-1/24)))
        }
    }
    static func contour(_ angle: Double) -> CGPath {
        let a = angle-28.6*Double.pi/180, b = angle+28.6*Double.pi/180
        let ro:CGFloat = 118, ri:CGFloat = 43, outer:CGFloat = 19, inner:CGFloat = 12
        let ao = Double(outer/ro), ai = Double(inner/ri), lo = outer*1.65, li = inner*1.65
        let zero = CGPoint.zero
        func normal(_ angle:Double,_ length:CGFloat,_ radius:CGFloat) -> CGPoint { scaled(unit(angle),-length*length/radius) }
        let path = CGMutablePath()
        path.move(to:polar(ro,a+ao))
        // Angles in this top-down coordinate space increase clockwise.
        path.addArc(center:CGPoint(x:118,y:118),radius:ro,startAngle:a+ao-Double.pi/2,endAngle:b-ao-Double.pi/2,clockwise:false)
        transition(path,polar(ro,b-ao),scaled(tangent(b-ao),lo),normal(b-ao,lo,ro),polar(ro-outer,b),scaled(unit(b),-lo),zero)
        path.addLine(to:polar(ri+inner,b))
        transition(path,polar(ri+inner,b),scaled(unit(b),-li),zero,polar(ri,b-ai),scaled(tangent(b-ai),-li),normal(b-ai,li,ri))
        path.addArc(center:CGPoint(x:118,y:118),radius:ri,startAngle:b-ai-Double.pi/2,endAngle:a+ai-Double.pi/2,clockwise:true)
        transition(path,polar(ri,a+ai),scaled(tangent(a+ai),-li),normal(a+ai,li,ri),polar(ri+inner,a),scaled(unit(a),li),zero)
        path.addLine(to:polar(ro-outer,a))
        transition(path,polar(ro-outer,a),scaled(unit(a),lo),zero,polar(ro,a+ao),scaled(tangent(a+ao),lo),normal(a+ao,lo,ro))
        path.closeSubpath(); return path
    }
    static func icon() -> NSImage {
        let image = NSImage(size:NSSize(width:12,height:12),flipped:true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x:rect.width/236,y:rect.height/236)
            context.addPath(combined); context.setFillColor(NSColor.black.cgColor); context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orbit"
        return image
    }
}
