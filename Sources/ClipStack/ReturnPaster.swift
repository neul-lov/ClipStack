import AppKit
import ApplicationServices
import Carbon

/// After a copy, waits for the next ⏎ in a text field of any app and pastes there instead.
///
/// Waiting ends after one use, after a few seconds, or as soon as another key is typed, so a ⏎ meant
/// to send something typed afterwards is never taken over. Needs Accessibility access.
@MainActor
final class ReturnPaster {
    /// Called when waiting starts or stops, to update the menu bar icon.
    var onStateChange: ((Bool) -> Void)?
    private(set) var isArmed = false

    private let timeout: TimeInterval = 10
    private var eventTap: CFMachPort?
    private var expiry: DispatchWorkItem?

    /// Apps where ⏎ should always reach the app itself.
    private static let excludedApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
    ]
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]

    /// Starts waiting. Returns false when the key watcher can't run (no Accessibility access).
    @discardableResult
    func arm() -> Bool {
        guard installTap() else { return false }
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.disarm() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        if !isArmed {
            isArmed = true
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            onStateChange?(true)
        }
        return true
    }

    func disarm() {
        expiry?.cancel()
        expiry = nil
        guard isArmed else { return }
        isArmed = false
        // Stop watching keys entirely while idle.
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        onStateChange?(false)
    }

    private func installTap() -> Bool {
        if eventTap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let paster = Unmanaged<ReturnPaster>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { paster.handle(type: type, event: event) }
        }, userInfo: context) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isArmed, let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard isArmed, type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter

        // Shortcuts such as ⌘Tab move between apps without cancelling.
        if flags.contains(.maskCommand) && !isReturn { return Unmanaged.passUnretained(event) }

        guard isReturn, flags.isEmpty, focusIsEmptyTextField() else {
            // Any other key (typing, esc, ⇧⏎) means the user moved on.
            disarm()
            return Unmanaged.passUnretained(event)
        }
        disarm()
        DispatchQueue.main.async { Self.postPaste() }
        return nil
    }

    /// True when the focused element is an editable, non-password text field that's empty (or whose
    /// contents can't be read, as in some web and Electron apps).
    private func focusIsEmptyTextField() -> Bool {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.excludedApps.contains(bundleID) { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement

        let role = stringAttribute(element, kAXRoleAttribute)
        let subrole = stringAttribute(element, kAXSubroleAttribute)
        if subrole == (kAXSecureTextFieldSubrole as String) { return false }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        guard Self.textRoles.contains(role ?? "") || settable.boolValue else { return false }

        if let value = stringAttribute(element, kAXValueAttribute) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
