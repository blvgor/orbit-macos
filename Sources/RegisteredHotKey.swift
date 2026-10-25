import AppKit
import Carbon

enum FinderTabPolicy {
    static func enabled(finderFrontmost:Bool,held:Bool,wheelVisible:Bool,busy:Bool,controlsKey:Bool) -> Bool {
        finderFrontmost && !busy && !controlsKey && (held || !wheelVisible)
    }
}

private let orbitHotKeyHandler: EventHandlerUPP = { _,event,context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    // Carbon invokes this handler synchronously on the application event loop.
    precondition(Thread.isMainThread)
    let owner = Unmanaged<RegisteredTabHotKey>.fromOpaque(context).takeUnretainedValue()
    let address = UInt(bitPattern:event)
    return MainActor.assumeIsolated {
        owner.receive(EventRef(bitPattern:address)!)
    }
}

@MainActor final class RegisteredTabHotKey {
    static let identifier = EventHotKeyID(signature:0x4F524254,id:1)
    private var handler: EventHandlerRef?
    private var registration: EventHotKeyRef?
    private var cancelRegistration: EventHotKeyRef?
    private(set) var handlerStatus: OSStatus = OSStatus(eventNotHandledErr)
    private(set) var registrationStatus: OSStatus = OSStatus(eventNotHandledErr)
    private(set) var cancelRegistrationStatus: OSStatus = OSStatus(eventNotHandledErr)
    private(set) var isPressed = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var isRegistered: Bool { registration != nil }
    var isCancelRegistered: Bool { cancelRegistration != nil }

    func install() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))
        ]
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(),orbitHotKeyHandler,types.count,&types,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    func setEnabled(_ enabled:Bool) {
        guard handlerStatus == noErr else { return }
        if enabled && registration == nil {
            registrationStatus = RegisterEventHotKey(UInt32(kVK_Tab),0,Self.identifier,GetApplicationEventTarget(),0,&registration)
        } else if !enabled, let registration {
            UnregisterEventHotKey(registration)
            self.registration = nil; isPressed = false
        }
    }
    func setCancelEnabled(_ enabled:Bool) {
        guard handlerStatus == noErr else { return }
        if enabled && cancelRegistration == nil {
            let identifier = EventHotKeyID(signature:Self.identifier.signature,id:2)
            cancelRegistrationStatus = RegisterEventHotKey(UInt32(kVK_Escape),0,identifier,GetApplicationEventTarget(),0,&cancelRegistration)
        } else if !enabled, let cancelRegistration {
            UnregisterEventHotKey(cancelRegistration)
            self.cancelRegistration = nil
        }
    }
    func stop() {
        setEnabled(false)
        setCancelEnabled(false)
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
    func receive(_ event:EventRef) -> OSStatus {
        guard GetEventClass(event) == OSType(kEventClassKeyboard) else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID(signature:0,id:0)
        let status = GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&identifier)
        guard status == noErr, identifier.signature == Self.identifier.signature else { return OSStatus(eventNotHandledErr) }
        if identifier.id == 2 {
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { onCancel?() }
            return noErr
        }
        guard identifier.id == Self.identifier.id else { return OSStatus(eventNotHandledErr) }
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            if !isPressed { isPressed = true; onPress?() }
        case UInt32(kEventHotKeyReleased):
            if isPressed { isPressed = false; onRelease?() }
        default: return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
