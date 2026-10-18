import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar only: no Dock icon or app menu (Info.plist also sets LSUIElement for the bundle).
    app.setActivationPolicy(.accessory)
    app.run()
}
