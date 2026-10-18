import AppKit
import Combine
import MaclipCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private var store: HistoryStore!
    private var watcher: PasteboardWatcher!
    private var hotKey: HotKey!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private let welcome = WelcomeController()
    private var preferences: PreferencesController!
    private var subscriptions: Set<AnyCancellable> = []
    private var purgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            Snapshots.run(into: URL(fileURLWithPath: args[i + 1]))
            return
        }
        #endif
        store = HistoryStore(fileURL: HistoryStore.defaultFileURL,
                             maxUnpinned: prefs.maxItems, maxAge: prefs.maxAge)
        panel = PanelController(store: store)
        preferences = PreferencesController { [weak self] in self?.store.clearUnpinned() }

        watcher = PasteboardWatcher(
            onText: { [weak self] text in self?.store.add(text) },
            onImage: { [weak self] png, width, height in self?.store.addImage(png: png, width: width, height: height) })
        watcher.start()

        hotKey = HotKey { [weak self] in self?.panel.toggle() }
        registerHotKey(prefs.hotKey)
        observePreferences()

        // Items expire by age even when nothing new is copied.
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.purgeExpired() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                           accessibilityDescription: "Maclip")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // First launch: explain the app and the auto-paste permission before asking for it.
        if !UserDefaults.standard.bool(forKey: WelcomeController.shownKey) {
            welcome.show()
        }
        if CommandLine.arguments.contains("--show-panel") { panel.show() }
        if CommandLine.arguments.contains("--show-preferences") { preferences.show() }
    }

    /// Opening Maclip again (e.g. from Applications or Spotlight) while it is already running
    /// shows Preferences, in case the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
    }

    // MARK: - Preferences

    private func observePreferences() {
        // @Published sends the new value before the property changes, so use the value given.
        prefs.$maxItems.dropFirst().sink { [weak self] in self?.store.maxUnpinned = $0 }
            .store(in: &subscriptions)
        prefs.$historyDays.dropFirst().sink { [weak self] days in
            self?.store.maxAge = days > 0 ? TimeInterval(days) * 86_400 : nil
        }.store(in: &subscriptions)
        prefs.$appearance.sink { NSApp.appearance = $0.nsAppearance }
            .store(in: &subscriptions)
        prefs.$hotKey.dropFirst().sink { [weak self] in self?.registerHotKey($0) }
            .store(in: &subscriptions)
        prefs.$isRecordingShortcut.dropFirst().removeDuplicates().sink { [weak self] recording in
            guard let self else { return }
            if recording { self.hotKey.unregister() } else { self.registerHotKey(self.prefs.hotKey) }
        }.store(in: &subscriptions)
    }

    private func registerHotKey(_ combo: KeyCombo) {
        if hotKey.register(combo) {
            prefs.hotKeyProblem = nil
        } else {
            prefs.hotKeyProblem = "macOS didn't accept \(combo.title); it may be reserved. Try another shortcut."
        }
    }

    // MARK: - Menu bar menu (rebuilt each time it opens so its state is current)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let combo = prefs.hotKey

        menu.addItem(item("About Maclip", #selector(showAbout)))
        menu.addItem(.separator())

        let show = item("Show Maclip", #selector(showPanel), key: combo.menuKeyEquivalent ?? "")
        show.keyEquivalentModifierMask = combo.flags
        menu.addItem(show)
        if prefs.hotKeyProblem != nil {
            menu.addItem(disabled("⚠︎ \(combo.title) isn't working — choose another in Preferences"))
        }
        menu.addItem(.separator())

        let count = store.items.count
        menu.addItem(disabled("\(count) item\(count == 1 ? "" : "s") (\(store.items.filter(\.pinned).count) pinned)"))
        menu.addItem(item("Clear History (keeps pinned)", #selector(clearHistory)))
        menu.addItem(.separator())

        if Paster.isTrusted {
            menu.addItem(disabled("✓ Auto-paste enabled"))
        } else {
            menu.addItem(item("Enable Auto-paste (grant Accessibility)…", #selector(grantAccessibility)))
        }
        // macOS 15.4+ lets users restrict apps from reading the clipboard in the background.
        // A clipboard manager needs "Allow", otherwise it records nothing (or asks every time).
        if #available(macOS 15.4, *),
           [.ask, .alwaysDeny].contains(NSPasteboard.general.accessBehavior) {
            menu.addItem(item("⚠︎ Clipboard reading restricted — allow \"Paste from Other Apps\"…",
                              #selector(openPrivacySettings)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Preferences…", #selector(showPreferences), key: ","))
        menu.addItem(item("Welcome & Setup…", #selector(showWelcome)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Maclip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func showAbout() { About.show() }

    @objc private func showPanel() { panel.show() }

    @objc private func showPreferences() { preferences.show() }

    @objc private func showWelcome() { welcome.show() }

    @objc private func clearHistory() { store.clearUnpinned() }

    @objc private func grantAccessibility() {
        Paster.requestTrust()
        Paster.openAccessibilitySettings()
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }
}
