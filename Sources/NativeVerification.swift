import AppKit
import Carbon

@MainActor enum NativeVerification {
    static func contentBitmap(of wheel:WheelView) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:236,pixelsHigh:236,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context = NSGraphicsContext(bitmapImageRep:bitmap) else { throw OrbitFailure.message("Center render failed") }
        NSGraphicsContext.saveGraphicsState()
        let c = context.cgContext
        c.clear(CGRect(x:0,y:0,width:236,height:236))
        c.translateBy(x:0,y:236); c.scaleBy(x:1,y:-1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:true)
        wheel.drawContent(wheel.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    static func maximumCenterAlpha(of wheel:WheelView) throws -> CGFloat {
        let bitmap = try contentBitmap(of:wheel)
        return (94..<142).flatMap { x in (94..<142).map { bitmap.colorAt(x:x,y:$0)?.alphaComponent ?? 1 } }.max() ?? 1
    }
    static func render(to folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let wheel = WheelView()
        var centerAlpha:[String:CGFloat] = [:]
        for (name,phase,fill) in [("ready",WheelPhase.ready,0.0),("processing",.working,0.55),("complete",.success,1.0)] {
            wheel.phase = phase; wheel.fill = fill
            if phase != .success { centerAlpha[name] = try maximumCenterAlpha(of:wheel) }
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:320,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context = NSGraphicsContext(bitmapImageRep:bitmap) else { throw OrbitFailure.message("Не удалось создать native preview.") }
            NSGraphicsContext.saveGraphicsState()
            let c = context.cgContext
            c.translateBy(x:0,y:320); c.scaleBy(x:1,y:-1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext:c,flipped:true)
            let colors = [NSColor(white:0.22,alpha:1).cgColor,NSColor(white:0.07,alpha:1).cgColor] as CFArray
            c.drawLinearGradient(CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!,start:.zero,end:CGPoint(x:400,y:320),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
            c.translateBy(x:82,y:42)
            // A neutral backdrop is used for offscreen material inspection;
            // native behind-window vibrancy is separately audited below.
            c.saveGState(); c.addPath(WheelGeometry.combined); c.setFillColor(NSColor(white:0.12,alpha:0.5).cgColor); c.fillPath(); c.restoreGState()
            wheel.drawContent(wheel.bounds)
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using:.png,properties:[:]) else { throw OrbitFailure.message("PNG render failed") }
            try data.write(to:folder.appendingPathComponent("native-\(name).png"))
        }
        let icon = WheelGeometry.icon()
        let rep = NSBitmapImageRep(data:icon.tiffRepresentation!)!
        try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("menu-icon.png"))
        let centerHits = OrbitAction.allCases.allSatisfy { WheelGeometry.action(at:WheelGeometry.polar(82,$0.angle)) == $0 }
        let controller = AppController(); controller.buildControls(); controller.refreshControls()
        let controlRoot = controller.controls.contentView!
        if let controlBitmap = controlRoot.bitmapImageRepForCachingDisplay(in:controlRoot.bounds) {
            controlRoot.cacheDisplay(in:controlRoot.bounds,to:controlBitmap)
            try controlBitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("native-controls.png"))
        }
        let shortHeight = controller.controls.frame.height
        controller.detail.stringValue = "Разрешите Orbit доступ к Finder в настройках macOS → Конфиденциальность → Автоматизация. После разрешения выберите файл и удерживайте Tab."
        controller.refreshControls()
        let longHeight = controller.controls.frame.height
        let controlFits = controller.controlsStack!.frame.maxY <= controlRoot.bounds.height && controller.controlsStack!.frame.minY >= 0
        func key(_ code:UInt16,type:NSEvent.EventType = .keyDown,flags:NSEvent.ModifierFlags = [],repeatKey:Bool = false) -> NSEvent {
            NSEvent.keyEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeatKey,keyCode:code)!
        }
        wheel.phase = .ready; wheel.selected = .optim
        var committed: OrbitAction?, escaped = false
        wheel.onAction = { committed = $0 }; wheel.onCancel = { escaped = true }
        wheel.keyDown(with:key(48)); let tabWorks = wheel.selected == .pdf
        wheel.keyDown(with:key(36)); wheel.keyDown(with:key(53))
        let keyboardWorks = tabWorks && committed == .pdf && escaped
        wheel.phase = .working; committed = nil; wheel.keyDown(with:key(36))
        let busyBlocksAction = committed == nil
        // Drive the real controller without installing global monitors,
        // touching Finder, showing a window or sending system-wide input.
        controller.finderIsFrontmost = { true }
        controller.presentationOverride = {}
        var invocation:[String:Bool] = [:]
        invocation["tabStartsSelectionRead"] = controller.handle(key(48)) && controller.tabHeld && controller.selectionTask != nil
        let readID = controller.selectionID
        controller.pending = .webp
        invocation["tabRepeatPreservesGesture"] = controller.handle(key(48,repeatKey:true)) && controller.selectionID == readID && controller.pending == .webp
        var hidden = false
        controller.dismissalObserver = { hidden = true }
        controller.pending = nil
        invocation["tabReleaseHidesAndCancelsLateOpen"] = controller.handle(key(48,type:.keyUp)) && !controller.tabHeld && controller.selectionTask == nil && controller.selectionID == nil && controller.pending == nil && hidden
        controller.cancelSelectionRead()
        invocation["unownedRepeatDoesNotOpen"] = !controller.handle(key(48,repeatKey:true)) && !controller.tabHeld
        invocation["modifiedTabsArePreserved"] = [NSEvent.ModifierFlags.command,.option,.control,.shift].allSatisfy { !controller.handle(key(48,flags:$0)) && !controller.tabHeld }
        controller.finderIsFrontmost = { false }
        invocation["tabOutsideFinderDoesNotOpen"] = !controller.handle(key(48)) && !controller.tabHeld
        controller.finderIsFrontmost = { true }
        _ = controller.handle(key(48))
        invocation["escapeCancelsHeldTab"] = controller.handle(key(53)) && !controller.tabHeld && controller.selectionTask == nil
        controller.wheel.phase = .working
        invocation["busyBlocksTabInvocation"] = !controller.handle(key(48)) && !controller.tabHeld
        controller.wheel.phase = .ready
        var registered:[String:Bool] = [:]
        registered["enabledOnlyInFinder"] = FinderTabPolicy.enabled(finderFrontmost:true,held:false,wheelVisible:false,busy:false,controlsKey:false) && !FinderTabPolicy.enabled(finderFrontmost:false,held:false,wheelVisible:false,busy:false,controlsKey:false)
        registered["busyAndControlsDoNotCaptureTab"] = !FinderTabPolicy.enabled(finderFrontmost:true,held:false,wheelVisible:false,busy:true,controlsKey:false) && !FinderTabPolicy.enabled(finderFrontmost:true,held:false,wheelVisible:false,busy:false,controlsKey:true)
        registered["openWheelKeepsNormalTabNavigation"] = !FinderTabPolicy.enabled(finderFrontmost:true,held:false,wheelVisible:true,busy:false,controlsKey:false)
        registered["heldGestureRetainsReleaseEvent"] = FinderTabPolicy.enabled(finderFrontmost:true,held:true,wheelVisible:true,busy:false,controlsKey:false)
        let adapter = RegisteredTabHotKey()
        var presses = 0, releases = 0, cancels = 0
        adapter.onPress = { presses += 1 }; adapter.onRelease = { releases += 1 }
        adapter.onCancel = { cancels += 1 }
        adapter.install()
        func sendHotKey(_ kind:UInt32,id:UInt32 = 1) -> OSStatus {
            var event: EventRef?
            guard CreateEvent(nil,OSType(kEventClassKeyboard),kind,0,EventAttributes(kEventAttributeUserEvent),&event) == noErr, let event else { return OSStatus(paramErr) }
            defer { ReleaseEvent(event) }
            var identifier = EventHotKeyID(signature:RegisteredTabHotKey.identifier.signature,id:id)
            let status = SetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),MemoryLayout<EventHotKeyID>.size,&identifier)
            guard status == noErr else { return status }
            return SendEventToEventTarget(event,GetApplicationEventTarget())
        }
        let firstPress = sendHotKey(UInt32(kEventHotKeyPressed))
        let repeatedPress = sendHotKey(UInt32(kEventHotKeyPressed))
        let released = sendHotKey(UInt32(kEventHotKeyReleased))
        registered["nativeHandlerDeliversPressRepeatReleaseOnce"] = adapter.handlerStatus == noErr && firstPress == noErr && repeatedPress == noErr && released == noErr && presses == 1 && releases == 1 && !adapter.isPressed
        let cancelled = sendHotKey(UInt32(kEventHotKeyPressed),id:2)
        registered["nativeEscapeHandlerCancelsPendingRead"] = cancelled == noErr && cancels == 1 && presses == 1
        _ = sendHotKey(UInt32(kEventHotKeyPressed),id:99)
        registered["unrelatedHotKeyIsIgnored"] = presses == 1 && releases == 1
        adapter.stop()
        var progressChecks:[String:Bool] = [:]
        for selected in OrbitAction.allCases {
            wheel.phase = .working; wheel.selected = selected; wheel.fill = 0
            let empty = try contentBitmap(of:wheel)
            wheel.fill = 0.55
            let half = try contentBitmap(of:wheel)
            var changed = Dictionary(uniqueKeysWithValues:OrbitAction.allCases.map { ($0.rawValue,0) })
            for x in 0..<236 { for y in 0..<236 {
                guard let a = empty.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), let b = half.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
                let delta = abs(a.redComponent-b.redComponent)+abs(a.greenComponent-b.greenComponent)+abs(a.blueComponent-b.blueComponent)+abs(a.alphaComponent-b.alphaComponent)
                guard delta > 0.02, let hit = WheelGeometry.action(at:CGPoint(x:CGFloat(x)+0.5,y:CGFloat(y)+0.5)) else { continue }
                changed[hit.rawValue,default:0] += 1
            } }
            progressChecks["onlySelectedPetal_\(selected.rawValue)"] = changed[selected.rawValue,default:0] > 50 && OrbitAction.allCases.filter { $0 != selected }.allSatisfy { changed[$0.rawValue,default:0] == 0 }
        }
        // Cache the actual child hierarchy in a window that is never ordered.
        // This includes glass and foreground in native view order.
        wheel.phase = .ready; wheel.selected = .optim; wheel.fill = 0
        let hiddenPanel = OrbitPanel(size:wheel.bounds.size)
        hiddenPanel.contentView = wheel; wheel.layoutSubtreeIfNeeded()
        var visibleLabels = 0
        if let bitmap = wheel.bitmapImageRepForCachingDisplay(in:wheel.bounds) {
            wheel.cacheDisplay(in:wheel.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("native-hierarchy-ready.png"))
            let scale = CGFloat(bitmap.pixelsWide)/wheel.bounds.width
            for action in OrbitAction.allCases {
                let center = WheelGeometry.polar(82,action.angle)
                var bright = 0
                for x in Int((center.x-25)*scale)..<Int((center.x+25)*scale) {
                    for y in Int((center.y-9)*scale)..<Int((center.y+10)*scale) {
                        if let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.85, color.redComponent > 0.83, color.greenComponent > 0.83, color.blueComponent > 0.83 { bright += 1 }
                    }
                }
                if bright > 8 { visibleLabels += 1 }
            }
        }
        let hierarchyInvisible = !hiddenPanel.isVisible
        var views:[NSView] = []
        func walk(_ v:NSView) { views.append(v); v.subviews.forEach(walk) }
        walk(wheel); walk(controller.controls.contentView!)
        let borderViews = views.filter { ($0.layer?.borderWidth ?? 0) > 0 }
        let ringButtons = views.compactMap { $0 as? NSButton }.filter { $0.focusRingType != .none || $0.isBordered }
        let dimensionLimits = views.flatMap(\.constraints).filter { $0.isActive && $0.relation != .equal && [.width,.height].contains($0.firstAttribute) }
        let audit:[String:Any] = ["wheelWidth":wheel.bounds.width,"wheelHeight":wheel.bounds.height,"sectorCount":WheelGeometry.paths.count,"sectorHitTests":centerHits,"centerDoesNotHitSector":WheelGeometry.action(at:CGPoint(x:118,y:118)) == nil,"readyCenterAlpha":centerAlpha["ready"] ?? 1,"processingCenterAlpha":centerAlpha["processing"] ?? 1,"iconWidth":icon.size.width,"iconHeight":icon.size.height,"iconIsTemplate":icon.isTemplate,"iconCenterTransparent":rep.colorAt(x:rep.pixelsWide/2,y:rep.pixelsHigh/2)?.alphaComponent == 0,"maskHasStroke":wheel.shapeMask.strokeColor != nil || wheel.shapeMask.lineWidth != 0,"borderViewCount":borderViews.count,"outlinedButtonCount":ringButtons.count,"layoutDimensionLimitCount":dimensionLimits.count,"glassMaterialHUD":wheel.glass.material == .hudWindow,"glassBlendsBehindWindow":wheel.glass.blendingMode == .behindWindow,"glassAlwaysActive":wheel.glass.state == .active,"accessibleActions":wheel.accessibilityChildren()?.count ?? 0,"keyboardTabEnterEscape":keyboardWorks,"busyBlocksAction":busyBlocksAction,"tabInvocation":invocation,"controlsFitLongMessage":controlFits && longHeight > shortHeight,"controlsShortHeight":shortHeight,"controlsLongHeight":longHeight,"previewNote":"Offscreen draw; real desktop compositing is not captured." ]
        var finalAudit = audit
        finalAudit["foregroundAboveGlass"] = wheel.subviews.first === wheel.glass && wheel.subviews.last === wheel.foreground && wheel.foreground.wheel === wheel
        finalAudit["progressChecks"] = progressChecks
        finalAudit["nativeHierarchyVisibleLabelCount"] = visibleLabels
        finalAudit["nativeHierarchyWindowNotShown"] = hierarchyInvisible
        finalAudit["registeredHotKeyChecks"] = registered
        try JSONSerialization.data(withJSONObject:finalAudit,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("native-audit.json"))
        print(String(data:try JSONSerialization.data(withJSONObject:finalAudit,options:[.prettyPrinted]),encoding:.utf8)!)
    }
}
