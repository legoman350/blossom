import Carbon.HIToolbox

/// Global hotkey via Carbon `RegisterEventHotKey`.
///
/// Not `NSEvent.addGlobalMonitorForEvents`: that one is passive, so the keystroke would also
/// reach the frontmost app. RegisterEventHotKey consumes the keystroke, and it needs no
/// Input Monitoring permission.
final class Hotkey {
    private static let signature: OSType = 0x424C_534D  // 'BLSM'
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns nil if the combination is already registered by another app.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = Hotkey.nextID
        Hotkey.nextID += 1
        self.action = action

        // Every handler installed on the application target sees EVERY hotkey press, not
        // just its own. So each handler checks the pressed key's ID and passes on the
        // others; without this, pressing one hotkey would fire all of them.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
            guard status == noErr, pressed.signature == Hotkey.signature, pressed.id == hotkey.id else {
                return OSStatus(eventNotHandledErr)
            }
            hotkey.action()
            return noErr
        }, 1, &spec, userData, &handlerRef)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Hotkey.signature, id: id)
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
