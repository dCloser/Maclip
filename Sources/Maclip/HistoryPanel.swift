import AppKit
import SwiftUI
import MaclipCore
import Carbon.HIToolbox

/// A floating panel that can take keyboard focus without activating this app, so the app
/// the user was typing in stays frontmost and receives the paste afterwards.
final class HistoryPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 460),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        self.contentView = contentView
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        backgroundColor = .clear
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// UI state shared between the SwiftUI view and the keyboard handling in the controller.
@MainActor
final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var hoveredID: UUID?
    @Published var accessibilityTrusted = Paster.isTrusted
    /// Bumped every time the panel opens so the view can refocus the search field.
    @Published var openToken = 0
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private let model = PanelModel()
    private var panel: HistoryPanel!
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore) {
        self.store = store
        super.init()
        let view = HistoryView(store: store, model: model, controller: self)
        let hosting = NSHostingView(rootView: view)
        panel = HistoryPanel(contentView: hosting)
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.query = ""
        model.hoveredID = nil
        model.selectedID = store.displayItems().first?.id
        model.accessibilityTrusted = Paster.isTrusted
        model.openToken += 1

        position()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // MARK: - Actions

    var visibleItems: [ClipItem] { store.displayItems(matching: model.query) }

    /// Puts the item on the clipboard and, if `paste` is set and Accessibility is
    /// granted, pastes it into the app that was focused before the panel opened.
    func choose(_ item: ClipItem, paste: Bool = true) {
        let pasteboard = NSPasteboard.general
        if item.isImage {
            guard let url = store.imageURL(for: item), let png = try? Data(contentsOf: url) else {
                NSSound.beep()
                return
            }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            // Many apps only accept TIFF images from the pasteboard.
            if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        } else {
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
        }
        store.moveToTop(id: item.id) // like a fresh copy
        close()

        guard paste else { return }
        guard Paster.isTrusted else {
            // Graceful fallback: the text is on the clipboard, the user can press Cmd+V.
            NSSound.beep()
            return
        }
        if let previousApp, previousApp != NSWorkspace.shared.frontmostApplication {
            previousApp.activate()
        }
        // Give the target window a moment to regain key focus before sending Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.pasteIntoFrontApp()
        }
    }

    func togglePin(_ item: ClipItem) { store.togglePin(id: item.id) }

    func delete(_ item: ClipItem) {
        let items = visibleItems
        if model.selectedID == item.id, let i = items.firstIndex(of: item) {
            // Keep the selection on the neighbouring row.
            let next = items.indices.contains(i + 1) ? items[i + 1] : (i > 0 ? items[i - 1] : nil)
            model.selectedID = next?.id
        }
        store.remove(id: item.id)
    }

    func clearAll() {
        store.clearUnpinned()
        model.selectedID = visibleItems.first?.id
    }

    func grantAccessibility() {
        close()
        Paster.requestTrust()
        Paster.openAccessibilitySettings()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the key was handled (and should not reach the search field).
    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let items = visibleItems
        let selected = items.first { $0.id == model.selectedID } ?? items.first

        switch Int(event.keyCode) {
        case kVK_Escape:
            // First Esc clears a search, the next one closes the panel.
            if model.query.isEmpty { close() } else { model.query = "" }
            return true
        case kVK_DownArrow, kVK_UpArrow:
            guard !items.isEmpty else { return true }
            let current = selected.flatMap { items.firstIndex(of: $0) } ?? 0
            let step = Int(event.keyCode) == kVK_DownArrow ? 1 : -1
            model.selectedID = items[min(max(current + step, 0), items.count - 1)].id
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let selected { choose(selected, paste: !mods.contains(.option)) }
            return true
        case kVK_Delete where mods.contains(.command), kVK_ForwardDelete where mods.contains(.command):
            if let selected { delete(selected) }
            return true
        case kVK_ANSI_P where mods.contains(.command):
            if let selected { togglePin(selected) }
            return true
        default:
            break
        }

        // Cmd+1 ... Cmd+9 pick the corresponding row directly.
        if mods == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
           (1...9).contains(digit), items.indices.contains(digit - 1) {
            choose(items[digit - 1])
            return true
        }
        return false
    }

    // MARK: - Window

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panel, like the Windows flyout.
        if panel.isVisible { close() }
    }

    /// Places the panel next to the mouse pointer, kept fully on screen.
    private func position() {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let anchor = NSPoint(x: mouse.x + 8, y: mouse.y - 8)
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)

        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height)
        if origin.y < visible.minY { origin.y = min(anchor.y + 24, visible.maxY - size.height) } // flip above
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}
