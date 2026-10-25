import AppKit
import ImageIO

@main struct ResponseTimeChecks {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let fixture = root.appendingPathComponent("response-fixture.png")
        let context = CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemOrange.cgColor); context.fill(CGRect(x:0,y:0,width:32,height:32))
        let destination = CGImageDestinationCreateWithURL(fixture as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,context.makeImage()!,nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Fixture write failed") }

        let controller = AppController()
        controller.buildControls()
        controller.finderIsFrontmost = { true }
        controller.selectionProvider = { Thread.sleep(forTimeInterval:0.25); return [fixture] }
        var firstPresentation: TimeInterval?
        let openingStart = ProcessInfo.processInfo.systemUptime
        controller.presentationOverride = {
            if firstPresentation == nil { firstPresentation = ProcessInfo.processInfo.systemUptime-openingStart }
        }
        controller.beginTabInvocation()
        try await Task.sleep(for:.milliseconds(400))
        let openingMilliseconds = (firstPresentation ?? 10)*1000
        controller.endTabInvocation()

        // A zero-length, invisible menu item supplies the real completion path's
        // tooltip target without ordering any panel or publishing another icon.
        controller.statusItem = NSStatusBar.system.statusItem(withLength:0)
        controller.statusItem.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.wheel.inputs = [fixture]
        var dismissal: TimeInterval?
        controller.dismissalObserver = { dismissal = ProcessInfo.processInfo.systemUptime }
        controller.start(.png)
        let initialProgress = controller.wheel.fill
        let processingStart = ProcessInfo.processInfo.systemUptime
        while controller.wheel.phase == .working && ProcessInfo.processInfo.systemUptime-processingStart < 3 {
            try await Task.sleep(for:.milliseconds(2))
        }
        let completedAt = ProcessInfo.processInfo.systemUptime
        while dismissal == nil && ProcessInfo.processInfo.systemUptime-completedAt < 3 {
            try await Task.sleep(for:.milliseconds(5))
        }
        let dismissalMilliseconds = max(0,(dismissal ?? (completedAt+10))-completedAt)*1000
        var checks = [
            "wheel responds before slow Finder reply": openingMilliseconds < 80,
            "progress responds in action callback": initialProgress > 0,
            "completed job closes within 80ms": dismissalMilliseconds < 80,
            "native window animations disabled": controller.wheelPanel.animationBehavior == .none,
            "real conversion completed": controller.wheel.phase == .success && controller.lastResult?.files.count == 1,
            "verification panels never shown": !controller.wheelPanel.isVisible && !controller.controls.isVisible
        ]
        controller.beginTabInvocation(); controller.pending = .jpg; controller.endTabInvocation()
        checks["early release queues chosen action"] = controller.selectionCommit == .jpg && controller.busy && !controller.tabHeld
        let queuedStart = ProcessInfo.processInfo.systemUptime
        while (controller.selectionTask != nil || controller.busy) && ProcessInfo.processInfo.systemUptime-queuedStart < 2 {
            try await Task.sleep(for:.milliseconds(5))
        }
        checks["queued action processes actual selected file"] = controller.selectionCommit == nil && controller.wheel.phase == .success && controller.lastResult?.files.first?.pathExtension == "jpg"
        let report: [String:Any] = ["checks":checks,"openingMilliseconds":openingMilliseconds,"dismissalMilliseconds":dismissalMilliseconds,"initialProgress":initialProgress,"fixtureConversionMilliseconds":(completedAt-processingStart)*1000]
        let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.appendingPathComponent("response-times.json"),options:.atomic)
        print(String(data:data,encoding:.utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
