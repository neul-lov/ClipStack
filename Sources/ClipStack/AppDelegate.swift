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
    private var hotKey: HotKey?
    private var keyMonitor: Any?

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
        store.start()

        // Control + Command + V opens the history from anywhere.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            MainActor.assumeIsolated { self?.togglePopover() }
        }
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
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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
}
