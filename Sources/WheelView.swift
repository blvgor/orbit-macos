import AppKit

enum WheelPhase { case ready, working, success, failure }

@MainActor final class WheelActionHandler {
    let press: () -> Void
    init(_ press: @escaping () -> Void) { self.press = press }
}
final class WheelAccessibilityAction: NSAccessibilityElement {
    private let action: @Sendable () -> Void
    init(action: @escaping @Sendable () -> Void) { self.action = action; super.init() }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}

@MainActor final class WheelForegroundView: NSView {
    weak var wheel: WheelView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) { wheel?.drawContent(dirtyRect) }
}

@MainActor final class WheelView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    let glass = NSVisualEffectView()
    let foreground = WheelForegroundView()
    let shapeMask = CAShapeLayer()
    var selected: OrbitAction = .optim { didSet { foreground.needsDisplay = true } }
    var phase: WheelPhase = .ready { didSet { refreshAccessibility(); foreground.needsDisplay = true } }
    var fill: Double = 0 { didSet { foreground.needsDisplay = true } }
    var message = "" { didSet { setAccessibilityHelp(message) } }
    var inputs: [URL] = []
    var onAction: ((OrbitAction) -> Void)?
    var onCancel: (() -> Void)?
    var onDrop: (([URL],OrbitAction) -> Void)?
    var onChoose: (() -> Void)?
    var onHover: ((OrbitAction?) -> Void)?
    private var tracking: NSTrackingArea?
    private var axButtons: [WheelAccessibilityAction] = []
    private var keyboardFocus = false
    init() {
        super.init(frame:NSRect(x:0,y:0,width:236,height:236))
        wantsLayer = true; layer?.borderWidth = 0
        glass.frame = bounds; glass.autoresizingMask = [.width,.height]
        glass.material = .hudWindow; glass.blendingMode = .behindWindow; glass.state = .active
        glass.appearance = NSAppearance(named:.darkAqua); glass.wantsLayer = true
        shapeMask.path = WheelGeometry.combined; shapeMask.fillColor = NSColor.white.cgColor
        shapeMask.strokeColor = nil; shapeMask.lineWidth = 0
        glass.layer?.mask = shapeMask; glass.layer?.borderWidth = 0
        addSubview(glass)
        foreground.frame = bounds; foreground.autoresizingMask = [.width,.height]
        foreground.wheel = self; foreground.wantsLayer = true
        foreground.layer?.backgroundColor = NSColor.clear.cgColor
        foreground.layer?.borderWidth = 0
        addSubview(foreground,positioned:.above,relativeTo:glass)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Форматы и оптимизация Orbit")
        for action in OrbitAction.allCases {
            let handler = WheelActionHandler { [weak self] in guard let self, self.phase != .working else { return }; self.onAction?(action) }
            let child = WheelAccessibilityAction { Task { @MainActor in handler.press() } }
            child.setAccessibilityRole(.button); child.setAccessibilityLabel(action.title); child.setAccessibilityParent(self)
            axButtons.append(child)
        }
        setAccessibilityChildren(axButtons)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point:NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        addTrackingArea(area); tracking = area; super.updateTrackingAreas()
    }
    override func layout() { super.layout(); shapeMask.frame = glass.bounds; refreshAccessibility() }
    func refreshAccessibility() {
        for (i,button) in axButtons.enumerated() {
            let center = WheelGeometry.polar(82,OrbitAction.allCases[i].angle)
            let frame = convert(NSRect(x:center.x-25,y:center.y-22,width:50,height:44),to:nil)
            button.setAccessibilityFrame(window?.convertToScreen(frame) ?? frame)
            button.setAccessibilityEnabled(phase != .working)
        }
        setAccessibilityValue(phase == .working ? "Обработка" : phase == .success ? "Готово" : phase == .failure ? message : "Выберите формат")
    }
    func point(_ event:NSEvent) -> CGPoint { convert(event.locationInWindow,from:nil) }
    override func mouseMoved(with event:NSEvent) {
        guard phase == .ready else { return }
        let action = WheelGeometry.action(at:point(event)); onHover?(action)
        guard let action else { return }
        keyboardFocus = false; selected = action
    }
    override func mouseDown(with event:NSEvent) {
        if phase == .working { return }
        if let action = WheelGeometry.action(at:point(event)) { selected = action; onAction?(action) }
        else if hypot(point(event).x-118,point(event).y-118) < 35 { onChoose?() }
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        guard phase != .working else { return }
        if event.keyCode == 48 {
            keyboardFocus = true
            let index = OrbitAction.allCases.firstIndex(of:selected)!
            selected = OrbitAction.allCases[(index + (event.modifierFlags.contains(.shift) ? 5 : 1))%6]
        } else if [36,49].contains(event.keyCode) { onAction?(selected) }
        else if [123,124,125,126].contains(event.keyCode) {
            keyboardFocus = true
            selected = event.keyCode == 125 ? .optim : event.keyCode == 126 ? .png : event.keyCode == 124 ? .webp : .jpg
        } else { super.keyDown(with:event) }
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { phase == .working ? [] : .copy }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation {
        guard phase != .working else { return [] }
        let p = convert(sender.draggingLocation,from:nil)
        if let action = WheelGeometry.action(at:p) { selected = action }
        return .copy
    }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        guard phase != .working,
              let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls,selected); return true
    }
    func drawContent(_ dirtyRect:NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        for (i,action) in OrbitAction.allCases.enumerated() {
            let path = WheelGeometry.paths[i]
            c.saveGState(); c.addPath(path); c.clip()
            let focused = keyboardFocus && action == selected && phase == .ready
            let base = focused ? NSColor(calibratedWhite:0.84,alpha:1) : NSColor(calibratedWhite:action == selected ? 0.88 : 0.68,alpha:action == selected ? 0.18 : 0.10)
            c.setFillColor(base.cgColor); c.fill(bounds)
            if !focused, let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(white:1,alpha:0.08).cgColor,NSColor(white:1,alpha:0.01).cgColor] as CFArray,locations:[0,1]) {
                c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:236,y:236),options:[])
            }
            c.restoreGState()
        }
        if fill > 0 {
            let index = OrbitAction.allCases.firstIndex(of:selected)!
            let path = WheelGeometry.paths[index]
            let box = path.boundingBoxOfPath
            let bottom = box.minY + box.height * CGFloat(fill)
            c.saveGState(); c.addPath(path); c.clip()
            c.clip(to:CGRect(x:box.minX,y:box.minY,width:box.width,height:box.height*CGFloat(fill)))
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(white:1,alpha:0.28).cgColor,NSColor(white:1,alpha:0.20).cgColor,NSColor(white:1,alpha:0.06).cgColor] as CFArray,locations:[0,0.82,1]) {
                c.drawLinearGradient(gradient,start:CGPoint(x:box.minX,y:box.minY),end:CGPoint(x:box.minX,y:bottom),options:[])
            }
            c.restoreGState()
        }
        for action in OrbitAction.allCases {
            let center = WheelGeometry.polar(82,action.angle)
            let color = keyboardFocus && action == selected && phase == .ready ? NSColor(white:0.12,alpha:1) : NSColor(white:0.95,alpha:1)
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (action.label as NSString).draw(in:NSRect(x:center.x-26,y:center.y-7,width:52,height:15),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:color,.paragraphStyle:paragraph])
        }
        if phase == .success || phase == .failure {
            let mark = phase == .success ? "✓" : "!"
            let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:23,weight:.regular),.foregroundColor:NSColor.white]
            let size = (mark as NSString).size(withAttributes:attrs)
            (mark as NSString).draw(at:CGPoint(x:118-size.width/2,y:118-size.height/2),withAttributes:attrs)
        }
    }
}

@MainActor final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init(size:NSSize) {
        super.init(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        isReleasedWhenClosed = false; hidesOnDeactivate = false
        animationBehavior = .none
    }
}

@MainActor final class PlainButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect:NSRect) {
        let focused = window?.firstResponder === self
        (focused || isHighlighted ? NSColor(white:1,alpha:0.22) : NSColor(white:1,alpha:0.07)).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:9,yRadius:9).fill()
        super.draw(dirtyRect)
    }
    override func becomeFirstResponder() -> Bool { let value = super.becomeFirstResponder(); needsDisplay = true; return value }
    override func resignFirstResponder() -> Bool { let value = super.resignFirstResponder(); needsDisplay = true; return value }
}
