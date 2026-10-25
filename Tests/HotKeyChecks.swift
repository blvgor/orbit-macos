import AppKit
import Foundation

@main struct HotKeyChecks {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = AppController()
        controller.buildControls(); controller.refreshControls()
        controller.finderIsFrontmost = { true }
        let fixture = URL(fileURLWithPath:"/private/tmp/orbit-hotkey-fixture.pdf")
        controller.selectionProvider = {
            Thread.sleep(forTimeInterval:0.08)
            return [fixture]
        }
        var presentations = 0, dismissals = 0
        controller.presentationOverride = { presentations += 1 }
        controller.dismissalObserver = { dismissals += 1 }
        var checks:[String:Bool] = [:]
        controller.beginTabInvocation(); controller.endTabInvocation()
        try await Task.sleep(for:.milliseconds(200))
        checks["quick release prevents delayed reopening"] = presentations == 1 && dismissals == 1 && !controller.tabHeld && controller.selectionTask == nil

        controller.beginTabInvocation()
        try await Task.sleep(for:.milliseconds(200))
        checks["held Tab opens selected document"] = presentations == 2 && controller.tabHeld && controller.wheel.inputs == [fixture] && controller.wheel.phase == .ready
        controller.endTabInvocation()
        checks["release without sector closes wheel"] = dismissals == 2 && !controller.tabHeld && !controller.busy

        controller.beginTabInvocation(); controller.dismiss()
        try await Task.sleep(for:.milliseconds(200))
        checks["escape prevents delayed reopening"] = presentations == 3 && controller.selectionTask == nil && !controller.tabHeld

        controller.selectionProvider = { throw OrbitFailure.message("Finder permission denied") }
        controller.beginTabInvocation()
        try await Task.sleep(for:.milliseconds(150))
        checks["Finder failure presents visible error instead of silence"] = presentations == 4 && controller.wheel.phase == .failure && controller.wheel.message == "Finder permission denied"
        controller.endTabInvocation()

        controller.selectionProvider = { [] }
        controller.beginTabInvocation()
        try await Task.sleep(for:.milliseconds(150))
        checks["empty selection presents instruction"] = presentations == 5 && controller.wheel.phase == .failure && controller.wheel.message.contains("Выберите файл")
        controller.endTabInvocation()

        controller.finderIsFrontmost = { false }
        controller.beginTabInvocation()
        checks["other applications keep their Tab"] = !controller.tabHeld && controller.selectionTask == nil

        controller.finderIsFrontmost = { true }
        controller.selectionProvider = {
            Thread.sleep(forTimeInterval:0.15)
            return [fixture]
        }
        controller.beginTabInvocation(); controller.endTabInvocation()
        try await Task.sleep(for:.milliseconds(30))
        let nextFixture = URL(fileURLWithPath:"/private/tmp/orbit-hotkey-new-selection.png")
        controller.selectionProvider = { [nextFixture] }
        controller.beginTabInvocation()
        try await Task.sleep(for:.milliseconds(220))
        checks["new tap replaces stale selection read"] = presentations == 7 && controller.wheel.inputs == [nextFixture] && controller.selectionTask == nil
        controller.endTabInvocation()

        controller.selectionProvider = { Thread.sleep(forTimeInterval:0.15); return [fixture] }
        controller.beginTabInvocation(); controller.pending = .webp; controller.endTabInvocation()
        checks["early release keeps selected action while Finder replies"] = controller.selectionCommit == .webp && controller.selectionTask != nil && controller.busy && !controller.tabHeld
        controller.dismiss()
        try await Task.sleep(for:.milliseconds(220))
        checks["escape cancels queued action without reopening"] = controller.selectionTask == nil && controller.selectionCommit == nil && !controller.busy && presentations == 8

        controller.beginTabInvocation(); controller.pending = .webp; controller.endTabInvocation()
        controller.finderIsFrontmost = { false }
        try await Task.sleep(for:.milliseconds(220))
        checks["late Finder reply cannot process after switching app"] = controller.selectionTask == nil && controller.selectionCommit == nil && !controller.busy && !controller.tabHeld
        controller.finderIsFrontmost = { true }
        controller.wheel.inputs = [nextFixture]
        controller.tabHeld = true; controller.pending = .png
        controller.start(.png)
        checks["commit ends held gesture before unregister"] = !controller.tabHeld && controller.pending == nil && controller.selectionTask == nil && controller.busy
        controller.dismiss(); controller.job?.cancel()

        let data = try JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys])
        if CommandLine.arguments.count > 1 { try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic) }
        print(String(data:data,encoding:.utf8)!)
        if checks.values.contains(false) { exit(1) }
    }
}
