import AppKit
import CoreGraphics

// An isolated, scripted native demonstration. No Finder access, global input,
// hot-key registration, app activation, login items, or permission prompts.
@MainActor final class DemoScene: NSView {
    override var isFlipped: Bool { true }
    var selected = false
    var complete = false
    var step = 0
    var previousStep: Int?
    var captionMix: CGFloat = 1
    var selectionOpacity: CGFloat = 1
    var resultOpacity: CGFloat = 1
    let fileCenter = CGPoint(x:480,y:312)
    let titles = ["Start with a document", "Click to select", "Press and hold", "Choose PNG", "Saved beside the original"]
    override func draw(_ dirtyRect:NSRect) {
        NSColor(white:0.12,alpha:1).setFill(); bounds.fill()
        text("ORBIT",rect:NSRect(x:40,y:30,width:160,height:20),size:12,weight:.semibold,color:NSColor(white:0.7,alpha:1))
        text(String(format:"%02d / 05",step+1),rect:NSRect(x:800,y:30,width:120,height:20),size:12,weight:.medium,color:NSColor(white:0.55,alpha:1),alignment:.right)
        drawFile("Demo.pdf",center:fileCenter,selected:selected,badge:"PDF",color:NSColor(red:0.81,green:0.22,blue:0.25,alpha:1))
        if complete {
            NSGraphicsContext.current?.cgContext.saveGState()
            NSGraphicsContext.current?.cgContext.setAlpha(resultOpacity)
            drawFile("Demo.png",center:CGPoint(x:640,y:312),selected:false,badge:"PNG",color:NSColor(red:0.2,green:0.48,blue:0.82,alpha:1))
            NSGraphicsContext.current?.cgContext.restoreGState()
        }
        if let previousStep, captionMix < 0.5 {
            caption(previousStep,opacity:1-2*captionMix)
        } else {
            caption(step,opacity:previousStep == nil ? 1 : 2*captionMix-1)
        }
    }
    func caption(_ step:Int,opacity:CGFloat) {
        NSGraphicsContext.current?.cgContext.saveGState()
        NSGraphicsContext.current?.cgContext.setAlpha(opacity)
        defer { NSGraphicsContext.current?.cgContext.restoreGState() }
        let captionY:CGFloat = 514
        if step == 2 {
            let start:CGFloat = 353
            text(titles[step],rect:NSRect(x:start,y:captionY,width:170,height:30),size:20,weight:.medium,color:.white)
            NSColor(white:0.29,alpha:1).setFill()
            NSBezierPath(roundedRect:NSRect(x:start+159,y:captionY-2,width:52,height:30),xRadius:7,yRadius:7).fill()
            text("Tab",rect:NSRect(x:start+159,y:captionY+1,width:52,height:25),size:16,weight:.semibold,color:.white,alignment:.center)
        } else {
            text(titles[step],rect:NSRect(x:80,y:captionY,width:800,height:30),size:20,weight:.medium,color:.white,alignment:.center)
        }
        let details = ["A blank PDF. Ready to convert.","The document is now selected.","The wheel opens around the document.","Move to PNG, then release Tab.","The original stays. The wheel closes."]
        text(details[step],rect:NSRect(x:80,y:552,width:800,height:22),size:13,weight:.regular,color:NSColor(white:0.65,alpha:1),alignment:.center)
    }
    func text(_ string:String,rect:NSRect,size:CGFloat,weight:NSFont.Weight,color:NSColor,alignment:NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle(); p.alignment = alignment
        (string as NSString).draw(in:rect,withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:p])
    }
    func drawFile(_ name:String,center:CGPoint,selected:Bool,badge:String,color:NSColor) {
        if selected {
            NSColor(white:0.27,alpha:selectionOpacity).setFill()
            NSBezierPath(roundedRect:NSRect(x:center.x-25,y:center.y-36,width:50,height:53),xRadius:7,yRadius:7).fill()
        }
        let x = center.x-16, y = center.y-32
        let page = NSBezierPath()
        page.move(to:CGPoint(x:x+4,y:y)); page.line(to:CGPoint(x:x+23,y:y))
        page.line(to:CGPoint(x:x+32,y:y+9)); page.line(to:CGPoint(x:x+32,y:y+40))
        page.curve(to:CGPoint(x:x+28,y:y+44),controlPoint1:CGPoint(x:x+32,y:y+43),controlPoint2:CGPoint(x:x+31,y:y+44))
        page.line(to:CGPoint(x:x+4,y:y+44)); page.curve(to:CGPoint(x:x,y:y+40),controlPoint1:CGPoint(x:x+1,y:y+44),controlPoint2:CGPoint(x:x,y:y+43))
        page.line(to:CGPoint(x:x,y:y+4)); page.curve(to:CGPoint(x:x+4,y:y),controlPoint1:CGPoint(x:x,y:y+1),controlPoint2:CGPoint(x:x+1,y:y)); page.close()
        NSColor(white:0.94,alpha:1).setFill(); page.fill()
        let fold=NSBezierPath(); fold.move(to:CGPoint(x:x+23,y:y)); fold.line(to:CGPoint(x:x+23,y:y+9)); fold.line(to:CGPoint(x:x+32,y:y+9)); fold.close()
        NSColor(white:0.73,alpha:1).setFill(); fold.fill()
        color.setFill(); NSBezierPath(roundedRect:NSRect(x:x-2,y:y+25,width:28,height:13),xRadius:3,yRadius:3).fill()
        text(badge,rect:NSRect(x:x-2,y:y+26,width:28,height:12),size:8,weight:.bold,color:.white,alignment:.center)
        if selected {
            NSColor(red:0.04,green:0.34,blue:0.91,alpha:selectionOpacity).setFill()
            NSBezierPath(roundedRect:NSRect(x:center.x-27,y:center.y+19,width:54,height:17),xRadius:5,yRadius:5).fill()
        }
        text(name,rect:NSRect(x:center.x-54,y:center.y+21,width:108,height:18),size:10,weight:.medium,color:.white,alignment:.center)
    }
}

@MainActor final class DemoCursor: NSView {
    override var isFlipped: Bool { true }
    var point = CGPoint(x:650,y:390)
    var pressed = false
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) {
        // Filled pointer; no outline, halo, or added center decoration.
        let p=NSBezierPath(), x=point.x, y=point.y
        p.move(to:CGPoint(x:x,y:y)); p.line(to:CGPoint(x:x+2,y:y+20))
        p.line(to:CGPoint(x:x+7,y:y+15)); p.line(to:CGPoint(x:x+11,y:y+23))
        p.line(to:CGPoint(x:x+15,y:y+21)); p.line(to:CGPoint(x:x+11,y:y+13))
        p.line(to:CGPoint(x:x+18,y:y+13)); p.close()
        (pressed ? NSColor(white:0.7,alpha:1) : .white).setFill(); p.fill()
    }
}

@main struct DemoCapture {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw OrbitFailure.message("Usage: DemoCapture OUTPUT_FOLDER WEBP_LIBRARY") }
        let folder=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:folder.appendingPathComponent("frames"),withIntermediateDirectories:true)
        let input=folder.appendingPathComponent("Demo.pdf")
        var page=CGRect(x:0,y:0,width:400,height:560)
        guard let pdf=CGContext(input as CFURL,mediaBox:&page,nil) else { throw OrbitFailure.message("Cannot make fixture") }
        pdf.beginPDFPage(nil); pdf.endPDFPage(); pdf.closePDF()
        let original=try Data(contentsOf:input)
        let app=NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()
        let frontBefore=NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let rect=NSRect(x:30,y:40,width:960,height:640)
        func panel() -> NSPanel {
            let p=NSPanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.backgroundColor=NSColor(white:0.12,alpha:1); p.isOpaque=true; p.hasShadow=false
            p.level = .normal; p.ignoresMouseEvents=true; p.hidesOnDeactivate=false; p.isReleasedWhenClosed=false
            return p
        }
        let backdrop=panel()
        let window=panel(), scene=DemoScene(frame:NSRect(origin:.zero,size:rect.size)), cursor=DemoCursor(frame:NSRect(origin:.zero,size:rect.size))
        let controller=AppController()
        let wheel=controller.wheel
        controller.finderIsFrontmost = { true }
        controller.selectionProvider = { [input] }
        controller.engine=FileProcessor(runner:controller.runner,webpLibrary:URL(fileURLWithPath:CommandLine.arguments[2]))
        wheel.frame.origin=CGPoint(x:scene.fileCenter.x-118,y:scene.fileCenter.y-118)
        wheel.isHidden=true
        controller.presentationOverride = { wheel.isHidden=false }
        controller.dismissalObserver = { wheel.isHidden=true }
        wheel.onHover = { controller.pending=$0 }
        scene.addSubview(wheel); scene.addSubview(cursor,positioned:.above,relativeTo:wheel)
        window.contentView=scene
        // Remain offscreen. Native cacheDisplay captures our own view hierarchy.
        scene.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil); backdrop.orderOut(nil) }
        RunLoop.current.run(until:Date().addingTimeInterval(0.35))
        guard !window.isVisible, !window.isKeyWindow, !window.isMainWindow,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw OrbitFailure.message("Window isolation failed") }
        func capture(_ url:URL) throws {
            scene.needsDisplay=true; cursor.needsDisplay=true; wheel.foreground.needsDisplay=true
            window.displayIfNeeded(); RunLoop.current.run(until:Date().addingTimeInterval(0.025))
            guard let bitmap=scene.bitmapImageRepForCachingDisplay(in:scene.bounds) else { throw OrbitFailure.message("Native bitmap unavailable") }
            scene.cacheDisplay(in:scene.bounds,to:bitmap)
            guard let data=bitmap.representation(using:.png,properties:[:]) else { throw OrbitFailure.message("Native capture failed") }
            try data.write(to:url)
        }
        func key(_ type:NSEvent.EventType) -> NSEvent {
            NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\t",charactersIgnoringModifiers:"\t",isARepeat:false,keyCode:48)!
        }
        func move(_ point:CGPoint,hover:Bool) {
            cursor.point=point
            if hover {
                let location=scene.convert(point,to:nil)
                let e=NSEvent.mouseEvent(with:.mouseMoved,location:location,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:0,pressure:0)!
                wheel.mouseMoved(with:e)
            }
        }
        let fps=30, frameCount=240
        var invoked=false, released=false
        var stepChangedAt = -1.0
        var motion:[ [String:Double] ] = []
        func smooth(_ value:Double) -> CGFloat {
            let u=CGFloat(max(0,min(1,value)))
            return u*u*u*(u*(u*6-15)+10)
        }
        func changeStep(_ next:Int,at time:Double) {
            guard next != scene.step else { return }
            scene.previousStep=scene.step; scene.step=next; stepChangedAt=time
        }
        let snapshots=[15:"01-document",60:"02-selected",95:"03-hold-tab",140:"04-choose-png",205:"05-complete"]
        for frame in 0..<frameCount {
            let t=Double(frame)/Double(fps)
            if t<0.6 { move(CGPoint(x:650,y:390),hover:false) }
            else if t<1.25 {
                let u=smooth((t-0.6)/0.65)
                move(CGPoint(x:650-170*u,y:390-78*u-8*sin(.pi*u)),hover:false)
            } else if t<3.6 { move(scene.fileCenter,hover:false) }
            if t>=1.25 && !scene.selected { scene.selected=true }
            scene.selectionOpacity=smooth((t-1.25)/0.12)
            cursor.pressed=t>=1.25 && t<1.35
            if t>=1.25 && t<2.35 { changeStep(1,at:t) }
            if t>=2.35 && !invoked {
                invoked=true; _=controller.handle(key(.keyDown))
                let deadline=Date().addingTimeInterval(3)
                while controller.selectionTask != nil && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
                guard controller.wheel.inputs == [input], controller.tabHeld else { throw OrbitFailure.message("Tab invocation failed") }
            }
            if t>=2.35 && t<3.6 {
                changeStep(2,at:t)
                wheel.alphaValue=smooth((t-2.35)/0.16)
            }
            if t>=3.6 && t<4.2 {
                changeStep(3,at:t)
                let u=smooth((t-3.6)/0.6)
                move(CGPoint(x:480+9*sin(.pi*u),y:312-82*u),hover:true)
            }
            if t>=4.2 && t<5.2 { move(CGPoint(x:480,y:230),hover:true) }
            if t>=5.2 && !released {
                released=true
                guard controller.pending == .png else { throw OrbitFailure.message("Pointer did not select PNG") }
                _=controller.handle(key(.keyUp))
                let deadline=Date().addingTimeInterval(5)
                while controller.job != nil && Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.005)) }
                guard controller.lastResult?.files.first?.pathExtension == "png", wheel.isHidden else { throw OrbitFailure.message("Output or dismissal failed") }
                scene.complete=true; changeStep(4,at:t)
            }
            if t>=5.2 {
                let u=smooth((t-5.2)/0.5)
                move(CGPoint(x:480+70*u,y:230+90*u),hover:false)
                scene.resultOpacity=smooth((t-5.2)/0.16)
            }
            scene.captionMix=smooth((t-stepChangedAt)/0.18)
            motion.append(["frame":Double(frame),"time":t,"x":cursor.point.x,"y":cursor.point.y])
            let frameURL=folder.appendingPathComponent(String(format:"frames/%03d.png",frame))
            try capture(frameURL)
            if let name=snapshots[frame] { try FileManager.default.copyItem(at:frameURL,to:folder.appendingPathComponent(name+".png")) }
        }
        try JSONSerialization.data(withJSONObject:motion,options:[.sortedKeys]).write(to:folder.appendingPathComponent("motion.json"))
        guard let output=controller.lastResult else { throw OrbitFailure.message("No conversion result") }
        for url in output.files { try ImageCodec.validate(url) }
        let report:[String:Any]=[
            "fps":fps,"frameCount":frameCount,"durationSeconds":Double(frameCount)/Double(fps),
            "version":"0.1.5","ownWindowID":window.windowNumber,"backdropWindowID":backdrop.windowNumber,
            "frontBefore":frontBefore,"frontAfter":NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
            "windowNeverKey":!window.isKeyWindow,"windowNeverMain":!window.isMainWindow,
            "tabInvokedActualController":invoked,"releaseSelectedPNG":released && wheel.selected == .png,
            "actualOutputValidated":output.files.count == 1,"originalUnchanged":try Data(contentsOf:input) == original,
            "wheelHiddenOnCompletion":wheel.isHidden,"centerDecorationAdded":false,
            "capture":"Offscreen native view hierarchy; actual WheelView and AppController, scripted file area, not Finder",
            "globalInputGenerated":false,"personalFilesRead":false,"windowsNeverOrdered":!window.isVisible && !backdrop.isVisible,
            "demoNeverFrontmost":frontBefore != ProcessInfo.processInfo.processIdentifier && NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            "wheelLayerBorderWidth":wheel.layer?.borderWidth ?? 0,
            "maskHasStroke":wheel.shapeMask.strokeColor != nil || wheel.shapeMask.lineWidth != 0
        ]
        guard report["demoNeverFrontmost"] as? Bool == true else { throw OrbitFailure.message("Demo unexpectedly became frontmost") }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("capture-report.json"))
        print("Five stages and 240 fresh animation frames captured at 30 fps. Actual Tab → hover PNG → release → save → dismissal passed.")
    }
}
