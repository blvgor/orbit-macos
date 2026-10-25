import AppKit
@preconcurrency import ApplicationServices
import ServiceManagement
import Carbon

enum FinderSelection {
    static func permissionStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier:"com.apple.finder")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc,AEEventClass(kCoreEventClass),AEEventID(kAEGetData),false)
    }
    static func read() throws -> [URL] {
        let text = """
        tell application "Finder"
            set chosenFiles to selection as alias list
            set paths to {}
            repeat with chosenFile in chosenFiles
                set end of paths to POSIX path of chosenFile
            end repeat
            return paths
        end tell
        """
        guard let script = NSAppleScript(source:text) else { throw OrbitFailure.message("Не удалось получить выделение Finder.") }
        var error: NSDictionary?
        let reply = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw OrbitFailure.message("Разрешите Orbit доступ к Finder в настройках macOS → Конфиденциальность → Автоматизация.") }
            throw OrbitFailure.message("Не удалось прочитать выделение Finder. Файл можно выбрать через значок Orbit.")
        }
        guard reply.numberOfItems > 0 else { return [] }
        return (1...reply.numberOfItems).compactMap { reply.atIndex($0)?.stringValue }.map { URL(fileURLWithPath:$0) }
    }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    let runner = ChildProcessRunner()
    lazy var engine = FileProcessor(runner:runner,webpLibrary:Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libwebp.7.dylib"))
    let wheel = WheelView()
    let wheelPanel = OrbitPanel(size:NSSize(width:236,height:236))
    let controls = OrbitPanel(size:NSSize(width:252,height:282))
    var statusItem: NSStatusItem!
    var permissionButton: PlainButton!
    var loginButton: PlainButton!
    var resultButton: PlainButton!
    var chooseButton: PlainButton!
    var controlsStack: NSStackView?
    let detail = NSTextField(wrappingLabelWithString:"Выберите файл в Finder и удерживайте Tab")
    var globalMonitor: Any?, localMonitor: Any?
    var scopeWatch: Timer?, activationObserver: NSObjectProtocol?
    var hotKey: RegisteredTabHotKey?
    var job: Task<Void,Never>?, selectionTask: Task<Void,Never>?
    var jobID: UUID?, selectionID: UUID?
    var tabHeld = false, pending: OrbitAction?
    var selectionCommit: OrbitAction?
    var finderIsFrontmost: () -> Bool = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" }
    var selectionProvider: @Sendable () throws -> [URL] = { try FinderSelection.read() }
    var presentationOverride: (() -> Void)?
    var dismissalObserver: (() -> Void)?
    var invocationCount = 0, releaseCount = 0
    var selectionOutcome = "idle"
    var lastResult: JobResult?
    var diagnosticsURL: URL?
    var busy: Bool { wheel.phase == .working }

    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength:26)
        statusItem.button?.image = WheelGeometry.icon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.isBordered = false; statusItem.button?.focusRingType = .none
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggleControls)
        statusItem.button?.setAccessibilityLabel("Orbit — конвертация и оптимизация файлов")
        statusItem.button?.toolTip = "Orbit · выберите файл в Finder и удерживайте Tab"
        wheelPanel.contentView = wheel
        wheel.onAction = { [weak self] in self?.start($0) }
        wheel.onDrop = { [weak self] urls,action in self?.wheel.inputs = urls; self?.start(action) }
        wheel.onCancel = { [weak self] in self?.dismiss() }
        wheel.onChoose = { [weak self] in
            guard let self else { return }; if self.wheel.phase == .failure { self.showControls() } else { self.chooseFiles() }
        }
        wheel.onHover = { [weak self] action in guard let self, self.tabHeld else { return }; self.pending = action }
        buildControls()
        installEventMonitors()
        let hotKey = RegisteredTabHotKey(); self.hotKey = hotKey
        hotKey.onPress = { [weak self] in self?.beginTabInvocation() }
        hotKey.onRelease = { [weak self] in self?.endTabInvocation() }
        hotKey.onCancel = { [weak self] in self?.dismiss() }
        hotKey.install()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.finderIsFrontmost() {
                    self.tabHeld = false; self.pending = nil; self.cancelSelectionRead()
                    if !self.busy { self.hideWheel() }
                }
                self.refreshHotKeyScope(); self.refreshControls(); self.writeDiagnostics()
            }
        }
        scopeWatch = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshHotKeyScope(); self.refreshControls(); self.writeDiagnostics()
            }
        }
        if !CommandLine.arguments.contains("--no-login") && !UserDefaults.standard.bool(forKey:"loginPreferenceSet") {
            do { try SMAppService.mainApp.register(); UserDefaults.standard.set(true,forKey:"loginPreferenceSet") }
            catch { detail.stringValue = "Автозапуск можно включить здесь." }
        }
        refreshHotKeyScope(); refreshControls(); writeDiagnostics()
    }
    func applicationWillTerminate(_ notification:Notification) {
        runner.cancel(); scopeWatch?.invalidate(); hotKey?.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool { false }
    func application(_ sender:NSApplication,openFiles filenames:[String]) { show(filenames.map { URL(fileURLWithPath:$0) }); sender.reply(toOpenOrPrint:.success) }

    func installEventMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        // A registered hot key supplies Tab down/up without monitoring global
        // keyboard input. Only pointer events belong in this monitor.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseUp,.leftMouseDown,.leftMouseDragged,.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyUp,.keyDown,.leftMouseDown,.leftMouseUp,.leftMouseDragged,.mouseMoved]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    func refreshHotKeyScope() {
        hotKey?.setEnabled(FinderTabPolicy.enabled(finderFrontmost:finderIsFrontmost(),held:tabHeld,wheelVisible:wheelPanel.isVisible,busy:busy,controlsKey:controls.isKeyWindow))
        hotKey?.setCancelEnabled(finderIsFrontmost() && selectionTask != nil && !wheelPanel.isVisible && !busy)
    }
    func beginTabInvocation() {
        guard !tabHeld, finderIsFrontmost(), !busy, !wheelPanel.isVisible, !controls.isKeyWindow else { return }
        cancelSelectionRead()
        tabHeld = true; pending = nil; invocationCount += 1
        controls.orderOut(nil); wheel.inputs = []; wheel.phase = .ready; wheel.fill = 0
        wheel.selected = .optim; wheel.message = "Читаю выделенный файл…"
        presentWheel()
        readFinderSelection(); writeDiagnostics()
    }
    func endTabInvocation() {
        guard tabHeld else { return }
        let action = pending
        tabHeld = false; pending = nil; releaseCount += 1
        if let action, wheel.phase == .ready { start(action) }
        else {
            cancelSelectionRead()
            if !busy { hideWheel() }
        }
        refreshHotKeyScope(); writeDiagnostics()
    }

    @discardableResult func handle(_ event:NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 48 {
            // Consume repeats during the held gesture before WheelView can
            // interpret Tab as keyboard navigation between sectors.
            if tabHeld { return true }
            let modifiers = event.modifierFlags.intersection([.command,.control,.option,.shift])
            guard !event.isARepeat, modifiers.isEmpty, finderIsFrontmost(), !busy, !wheelPanel.isVisible, !controls.isKeyWindow else { return false }
            beginTabInvocation()
            return true
        }
        if event.type == .keyUp && event.keyCode == 48 && tabHeld {
            endTabInvocation()
            return true
        }
        if event.type == .keyDown && event.keyCode == 53 {
            let wasInvoked = tabHeld || wheelPanel.isVisible || controls.isVisible
            dismiss(); return wasInvoked
        }
        if event.type == .leftMouseDown {
            let p = NSEvent.mouseLocation
            if controls.isVisible && !controls.frame.contains(p) { controls.orderOut(nil) }
            if wheelPanel.isVisible && !wheelPanel.frame.contains(p) && !busy { dismiss() }
        }
        let finder = finderIsFrontmost()
        if event.type == .leftMouseUp && tabHeld && finder && !busy && !wheelPanel.isVisible {
            readFinderSelection(delay:.milliseconds(120))
        }
        if event.type == .leftMouseDragged && tabHeld && finder && !busy && !wheelPanel.isVisible { readFinderSelection(delay:.milliseconds(120)) }
        if (event.type == .mouseMoved || event.type == .leftMouseDragged) && tabHeld && wheelPanel.isVisible && !busy {
            let screen = NSEvent.mouseLocation
            let local = CGPoint(x:screen.x-wheelPanel.frame.minX,y:wheelPanel.frame.maxY-screen.y)
            pending = WheelGeometry.action(at:local)
            if let pending { wheel.selected = pending }
        }
        if event.type == .keyDown && tabHeld && wheelPanel.isVisible && !busy {
            let mapping:[UInt16:OrbitAction] = [125:.optim,126:.png,124:.webp,123:.jpg]
            if let action = mapping[event.keyCode] { wheel.selected = action; pending = action; return true }
        }
        return false
    }
    func cancelSelectionRead() {
        selectionTask?.cancel(); selectionTask = nil; selectionID = nil
        if selectionCommit != nil { selectionCommit = nil; wheel.phase = .ready; wheel.fill = 0 }
    }
    func readFinderSelection(delay:Duration = .zero) {
        guard selectionTask == nil else { return }
        let id = UUID(); selectionID = id
        selectionOutcome = "reading"
        selectionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.selectionID == id { self.selectionTask = nil; self.selectionID = nil }
                self.refreshHotKeyScope()
            }
            if delay != .zero { try? await Task.sleep(for:delay) }
            guard !Task.isCancelled else { return }
            do {
                let provider = self.selectionProvider
                let files = try await Task.detached(priority:.userInitiated) { try provider() }.value
                guard !Task.isCancelled, self.selectionID == id, !self.busy || self.selectionCommit != nil else { return }
                guard self.finderIsFrontmost() else {
                    self.tabHeld = false; self.pending = nil; self.cancelSelectionRead(); self.hideWheel(); return
                }
                guard !files.isEmpty else {
                    self.selectionOutcome = "empty"
                    self.selectionCommit = nil
                    self.report("Выберите файл в Finder и удерживайте Tab."); return
                }
                self.selectionOutcome = "selected"
                self.wheel.inputs = files; self.wheel.message = ""
                if let action = self.selectionCommit {
                    self.selectionCommit = nil; self.wheel.phase = .ready
                    self.start(action)
                } else { self.wheel.refreshAccessibility(); self.writeDiagnostics() }
            } catch {
                if !Task.isCancelled, self.selectionID == id {
                    self.selectionCommit = nil
                    self.selectionOutcome = "failed"
                    self.report(error.localizedDescription)
                }
            }
        }
        refreshHotKeyScope()
    }
    func show(_ files:[URL]) {
        guard !busy, !files.isEmpty else { return }
        controls.orderOut(nil); wheel.inputs = files; wheel.phase = .ready; wheel.fill = 0; wheel.selected = .optim; wheel.message = ""
        presentWheel()
    }
    func presentWheel() {
        if let presentationOverride { presentationOverride(); writeDiagnostics(); return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let visible = screen.visibleFrame.insetBy(dx:8,dy:8)
        let origin = CGPoint(x:min(max(mouse.x-118,visible.minX),visible.maxX-236),y:min(max(mouse.y-118,visible.minY),visible.maxY-236))
        // This nonactivating panel receives keys only after the user's invocation.
        // Arrow keys then stay in Orbit instead of changing Finder's selection.
        wheelPanel.setFrameOrigin(origin); wheelPanel.makeKeyAndOrderFront(nil); wheelPanel.makeFirstResponder(wheel)
        wheel.refreshAccessibility(); refreshHotKeyScope(); writeDiagnostics()
    }
    func hideWheel() { wheelPanel.orderOut(nil); dismissalObserver?() }
    func start(_ action:OrbitAction) {
        guard !busy else { return }
        if wheel.inputs.isEmpty && selectionTask != nil {
            tabHeld = false; pending = nil; selectionCommit = action
            wheel.selected = action; wheel.phase = .working; wheel.fill = 0.02
            detail.stringValue = "Обработка…"
            refreshHotKeyScope(); writeDiagnostics(); return
        }
        guard !busy, !wheel.inputs.isEmpty else { return }
        let id = UUID(); jobID = id
        tabHeld = false; pending = nil; cancelSelectionRead()
        runner.reset(); wheel.selected = action; wheel.phase = .working; wheel.fill = 0.02
        detail.stringValue = "Обработка…"; controls.orderOut(nil)
        refreshHotKeyScope()
        let inputs = wheel.inputs
        job = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.jobID == id { self.job = nil; self.jobID = nil }
                self.refreshHotKeyScope(); self.writeDiagnostics()
            }
            do {
                let result = try await self.engine.run(inputs:inputs,action:action) { [weak self] value in
                    Task { @MainActor in guard let self, self.jobID == id, self.busy else { return }; self.wheel.fill = max(self.wheel.fill,min(0.98,value)) }
                }
                guard self.jobID == id else { return }
                self.lastResult = result; self.wheel.phase = .success; self.wheel.fill = 1
                self.hideWheel()
                self.detail.stringValue = "Готово. \(result.files.count) файл(ов) рядом с оригиналом."
                self.statusItem?.button?.toolTip = "Orbit · готово"
                NSAccessibility.post(element:self.wheel,notification:.announcementRequested,userInfo:[.announcement:"Обработка завершена. Результат сохранён рядом с оригиналом.",.priority:NSAccessibilityPriorityLevel.high.rawValue])
                self.refreshControls(); self.writeDiagnostics()
            } catch is CancellationError {
                self.wheel.phase = .ready; self.wheel.fill = 0
                self.detail.stringValue = "Отменено. Оригиналы сохранены."; self.hideWheel(); self.writeDiagnostics()
            } catch { self.report(error.localizedDescription) }
        }
    }
    func report(_ message:String) {
        wheel.phase = .failure; wheel.message = message; wheel.toolTip = message
        detail.stringValue = message; statusItem?.button?.toolTip = "Orbit · " + message
        NSAccessibility.post(element:wheel,notification:.announcementRequested,userInfo:[.announcement:message,.priority:NSAccessibilityPriorityLevel.high.rawValue])
        refreshControls(); writeDiagnostics()
    }
    func dismiss() {
        tabHeld = false; pending = nil; cancelSelectionRead()
        if busy { runner.cancel() }
        hideWheel(); controls.orderOut(nil)
        refreshHotKeyScope(); writeDiagnostics()
    }
    @objc func chooseFiles() {
        guard !busy else { return }
        controls.orderOut(nil); hideWheel()
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.prompt = "Выбрать"; panel.message = "Выберите изображения или PDF"
        panel.begin { [weak self] reply in if reply == .OK { self?.show(panel.urls) } }
    }
    @objc func toggleControls() { if controls.isVisible { controls.orderOut(nil) } else { showControls() } }
    func showControls() {
        refreshControls()
        guard let button = statusItem.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds,to:nil))
        let screen = window.screen ?? NSScreen.main!
        controls.setFrameOrigin(CGPoint(x:min(max(anchor.midX-126,screen.visibleFrame.minX+8),screen.visibleFrame.maxX-260),y:anchor.minY-controls.frame.height-8))
        controls.orderFrontRegardless()
    }
    @objc func retryHotKey() {
        hotKey?.install()
        refreshHotKeyScope(); refreshControls(); writeDiagnostics()
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else { try SMAppService.mainApp.register() }
            UserDefaults.standard.set(true,forKey:"loginPreferenceSet")
        } catch { detail.stringValue = "Не удалось изменить автозапуск: " + error.localizedDescription }
        refreshControls(); writeDiagnostics()
    }
    @objc func revealResult() { if let result = lastResult { NSWorkspace.shared.activateFileViewerSelecting(result.files) } }
    @objc func quit() { runner.cancel(); NSApp.terminate(nil) }
    func refreshControls() {
        guard permissionButton != nil else { return }
        let failed = hotKey != nil && (hotKey!.handlerStatus != noErr || (finderIsFrontmost() && hotKey!.registrationStatus != noErr))
        permissionButton.title = failed ? "Повторить включение Tab" : "Tab: включён в Finder"
        permissionButton.isEnabled = failed
        if failed { detail.stringValue = "Не удалось включить Tab. Повторите попытку через кнопку ниже." }
        let state = SMAppService.mainApp.status
        loginButton.title = state == .enabled ? "Автозапуск: включён" : state == .requiresApproval ? "Автозапуск: разрешить…" : "Автозапуск: выключен"
        resultButton.isEnabled = lastResult != nil
        chooseButton.isEnabled = !busy
        detail.invalidateIntrinsicContentSize(); controls.contentView?.layoutSubtreeIfNeeded()
        if let controlsStack {
            controls.setContentSize(NSSize(width:252,height:controlsStack.fittingSize.height+28))
            controls.contentView?.layoutSubtreeIfNeeded()
        }
    }
    func button(_ title:String,_ selector:Selector) -> PlainButton {
        let b = PlainButton(title:title,target:self,action:selector)
        b.isBordered = false; b.focusRingType = .none; b.bezelStyle = .regularSquare
        b.font = .systemFont(ofSize:12,weight:.medium); b.contentTintColor = .white
        b.alignment = .center; b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant:32).isActive = true
        return b
    }
    func buildControls() {
        let root = NSView(frame:NSRect(x:0,y:0,width:252,height:282))
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor(white:0.13,alpha:0.98).cgColor
        root.layer?.cornerRadius = 18; root.layer?.cornerCurve = .continuous; root.layer?.borderWidth = 0
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        controlsStack = stack
        stack.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:14),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-14),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:14)])
        let title = NSTextField(labelWithString:"Orbit"); title.font = .systemFont(ofSize:13,weight:.medium); title.textColor = .white
        detail.font = .systemFont(ofSize:11); detail.textColor = NSColor(white:0.8,alpha:1)
        stack.addArrangedSubview(title); stack.addArrangedSubview(detail)
        chooseButton = button("Выбрать файл…",#selector(chooseFiles)); stack.addArrangedSubview(chooseButton)
        resultButton = button("Показать результат",#selector(revealResult)); stack.addArrangedSubview(resultButton)
        permissionButton = button("Tab: включён в Finder",#selector(retryHotKey)); stack.addArrangedSubview(permissionButton)
        loginButton = button("Автозапуск",#selector(toggleLogin)); stack.addArrangedSubview(loginButton)
        stack.addArrangedSubview(button("Завершить Orbit",#selector(quit)))
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true }
        controls.contentView = root
    }
    func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        let info:[String:Any] = ["pid":ProcessInfo.processInfo.processIdentifier,"bundleIdentifier":Bundle.main.bundleIdentifier ?? "","version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "","invocationKey":"Tab","tabHeld":tabHeld,"hotkeyBackend":"RegisterEventHotKey","hotkeyRequiresAccessibility":false,"hotkeyRegistered":hotKey?.isRegistered ?? false,"hotkeyHandlerStatus":hotKey?.handlerStatus ?? OSStatus(eventNotHandledErr),"hotkeyRegistrationStatus":hotKey?.registrationStatus ?? OSStatus(eventNotHandledErr),"finderFrontmost":finderIsFrontmost(),"invocationCount":invocationCount,"releaseCount":releaseCount,"selectionOutcome":selectionOutcome,"finderPermissionStatus":FinderSelection.permissionStatus(),"accessibilityTrusted":AXIsProcessTrusted(),"activationPolicy":NSApp.activationPolicy().rawValue,"loginStatus":SMAppService.mainApp.status.rawValue,"statusIconWidth":statusItem?.button?.image?.size.width ?? 0,"wheelSize":wheel.bounds.width,"wheelPhase":String(describing:wheel.phase),"progress":wheel.fill,"shapeMaskStroke":shapeMaskHasStroke(),"windowCount":NSApp.windows.filter { $0.isVisible }.count]
        if let data = try? JSONSerialization.data(withJSONObject:info,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:diagnosticsURL,options:.atomic) }
    }
    func shapeMaskHasStroke() -> Bool { wheel.shapeMask.strokeColor != nil || wheel.shapeMask.lineWidth != 0 }
}
