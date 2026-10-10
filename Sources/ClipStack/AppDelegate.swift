import AppKit
import Carbon
import SwiftUI

@main
enum ClipStackApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = ClipboardStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    /// The app in front before the popover opened; pastes go back to it.
    private var previousApp: NSRunningApplication?
    private var askedForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // New status items land at the far left of the menu bar, where menu bar managers hide them.
        // Start next to the system icons instead; macOS remembers wherever the user drags it later.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position ClipStack": 300])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ClipStack"
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipStack")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: ContentView.width, height: ContentView.height)
        popover.contentViewController = NSHostingController(rootView: ContentView(store: store))

        store.onRequestClose = { [weak self] in self?.popover.performClose(nil) }
        store.onRequestPaste = { [weak self] in self?.pasteIntoPreviousApp() }
        store.start()
        #if DEBUG
        if CommandLine.arguments.contains("--demo") {
            runDemo()
            return
        }
        #endif
        // Ask for Accessibility up front so the first paste already works.
        if store.pasteAfterCopy { requestAccessibilityIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushSave()
    }

    // Opening the app again (from Launchpad, Spotlight or Finder) shows the history.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { showPopover() }
        return false
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.didOpen()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor()
        // A transient popover misses clicks on other apps and the desktop, so watch for those too.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.popover.isShown, !self.store.isDemo else { return }
                    // Clicks on the popover itself or the menu bar icon can arrive here while the
                    // app is still becoming active; only a click somewhere else closes it.
                    let point = NSEvent.mouseLocation
                    let ownWindows = [self.popover.contentViewController?.view.window, self.statusItem.button?.window]
                    guard !ownWindows.contains(where: { $0?.frame.contains(point) == true }) else { return }
                    self.popover.performClose(nil)
                }
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Activation can flicker while the popover opens or is clicked; close only if another app
        // really took over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.popover.isShown, !NSApp.isActive, !self.store.isDemo else { return }
            self.popover.performClose(nil)
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !askedForAccessibility, !AXIsProcessTrusted() else { return }
        askedForAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func pasteIntoPreviousApp() {
        popover.performClose(nil)
        // Sending ⌘V to another app needs Accessibility access. Without it the clip is still copied.
        guard AXIsProcessTrusted() else {
            requestAccessibilityIfNeeded()
            return
        }
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let source = CGEventSource(stateID: .combinedSessionState)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        // Hand focus back to the app the user was working in.
        NSApp.hide(nil)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            store.moveHighlight(by: 1)
        case kVK_UpArrow:
            store.moveHighlight(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            store.copyPrimary()
        case kVK_Tab:
            store.toggleHighlighted()
        case kVK_Escape:
            if !store.selection.isEmpty {
                store.clearSelection()
            } else if !store.query.isEmpty {
                store.query = ""
            } else {
                popover.performClose(nil)
            }
        case kVK_Delete where flags.contains(.command):
            store.deleteHighlighted()
        case kVK_ANSI_P where flags.contains(.command):
            if let id = store.highlightedID { store.togglePin(id) }
        default:
            return false
        }
        return true
    }

    #if DEBUG
    /// Plays a scripted walkthrough with sample clips, for recording the README demo.
    private func runDemo() {
        setvbuf(stdout, nil, _IONBF, 0)
        store.loadDemoItems()
        let steps: [(TimeInterval, () -> Void)] = [
            (0.4, { [self] in
                showPopover()
                if let window = popover.contentViewController?.view.window {
                    print("DEMO_WINDOW \(window.windowNumber)")
                }
            }),
            (1.6, { [self] in store.demoSelect(0) }),
            (2.3, { [self] in store.demoSelect(2) }),
            (3.0, { [self] in store.demoSelect(1) }),
            (4.4, { [self] in store.copySelection() }),
            (7.0, { print("DEMO_DONE") }),
        ]
        for (delay, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
    }
    #endif
}
