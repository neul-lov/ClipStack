import Carbon

/// Shortcuts offered for opening the history from anywhere.
enum Shortcut: String, CaseIterable, Identifiable {
    case controlCommandV
    case optionCommandV
    case shiftCommandV
    case controlOptionV
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlCommandV: "⌃⌘V"
        case .optionCommandV: "⌥⌘V"
        case .shiftCommandV: "⇧⌘V"
        case .controlOptionV: "⌃⌥V"
        case .off: "None"
        }
    }

    var modifiers: UInt32? {
        switch self {
        case .controlCommandV: UInt32(controlKey | cmdKey)
        case .optionCommandV: UInt32(optionKey | cmdKey)
        case .shiftCommandV: UInt32(shiftKey | cmdKey)
        case .controlOptionV: UInt32(controlKey | optionKey)
        case .off: nil
        }
    }
}

/// A system-wide keyboard shortcut registered through Carbon, which needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Returns nil when the shortcut can't be registered, for example because another app holds it.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x434C_5354), id: 1) // "CLST"
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(),
                                                 OptionBits(kEventHotKeyExclusive), &hotKeyRef)
        guard installStatus == noErr, registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
