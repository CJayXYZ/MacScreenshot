import Carbon.HIToolbox

/// A system-wide hotkey registered through the Carbon event API.
/// Each instance needs a distinct `id`: every handler sees every hotkey press and
/// ignores the ones that aren't its own.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard status == noErr, pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            me.action()
            return noErr
        }, 1, &spec, context, &handlerRef)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D53_4354), id: id) // "MSCT"
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
