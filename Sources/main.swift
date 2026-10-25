import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
if let index = CommandLine.arguments.firstIndex(of:"--diagnostics"), CommandLine.arguments.count > index+1 {
    controller.diagnosticsURL = URL(fileURLWithPath:CommandLine.arguments[index+1])
}
if let index = CommandLine.arguments.firstIndex(of:"--render"), CommandLine.arguments.count > index+1 {
    try NativeVerification.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
} else {
    let identifier = Bundle.main.bundleIdentifier
    let duplicates = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == identifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if duplicates.isEmpty { app.delegate = controller; withExtendedLifetime(controller) { app.run() } }
}
