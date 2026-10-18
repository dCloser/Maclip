#if DEBUG
import AppKit
import MaclipCore

/// Debug builds only: `Maclip --snapshot <dir>` opens the main windows with sample data,
/// renders each to a PNG in <dir> (light and dark), then quits. Uses an in-memory history,
/// so it never touches the real one.
@MainActor
enum Snapshots {
    private static var keepAlive: [AnyObject] = []

    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Paster.snapshotTrusted = true
        // A bare debug binary has no bundle icon; use the real one from the source tree.
        let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Support/AppIcon-1024.png").standardizedFileURL
        if let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }
        let store = HistoryStore(fileURL: nil)
        let now = Date()
        let samples: [(String, TimeInterval)] = [
            ("Meeting moved to Thursday 3pm — same Zoom link as last week.", 26 * 3600),
            ("git checkout -b feature/clipboard-search", 5 * 3600),
            ("https://developer.apple.com/documentation/appkit/nspasteboard", 3 * 3600),
            ("Dear Ms. Patel,\nThank you for your quick reply.\nI've attached the signed contract.", 2400),
            ("Link to the design review: https://figma.com/file/maclip-v1", 1800),
            ("#4F5BF0", 600),
            ("Maclip keeps everything you copy, one shortcut away.", 60),
        ]
        for (text, ago) in samples { store.add(text, date: now.addingTimeInterval(-ago)) }
        if let swatch = sampleImage() { store.addImage(png: swatch, width: 640, height: 360, date: now.addingTimeInterval(-30)) }
        store.togglePin(id: store.items.first { $0.text.hasPrefix("Meeting") }!.id)

        let panel = PanelController(store: store)
        let prefs = PreferencesController(onClearHistory: {})
        let welcome = WelcomeController()
        keepAlive = [store, panel, prefs, welcome]

        func capture(_ suffix: String, only panelOnly: Bool = false) {
            let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 50 && (!panelOnly || $0 is HistoryPanel) }
            for window in windows {
                // The panel's title bar is invisible, so render only its content; other
                // windows include their title bar (the frame view).
                guard let view = window is HistoryPanel ? window.contentView
                                 : (window.contentView?.superview ?? window.contentView),
                      let rep = render(view, scale: 3) else { continue }
                let name = window is HistoryPanel ? (panelOnly ? "panel-search" : "panel")
                    : window.title.isEmpty ? (window.frame.width < 400 ? "about" : "welcome") : "preferences"
                let url = dir.appendingPathComponent("\(name)-\(suffix).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("wrote \(url.path)")
            }
        }

        NSApp.appearance = NSAppearance(named: .aqua)
        panel.show(); prefs.show(); welcome.show(); About.show()
        panel.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capture("light")
            NSApp.appearance = NSAppearance(named: .darkAqua)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                capture("dark")
                panel.setQueryForSnapshot("link")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    capture("dark", only: true)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Draws `view` at `scale` × its point size (sharper than the screen's backing scale).
    private static func render(_ view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func sampleImage() -> Data? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 360, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSGradient(colors: [NSColor(red: 0.25, green: 0.63, blue: 1, alpha: 1),
                            NSColor(red: 0.48, green: 0.25, blue: 0.89, alpha: 1)])?
            .draw(in: NSRect(x: 0, y: 0, width: 640, height: 360), angle: -30)
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 300, height: 240), xRadius: 24, yRadius: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
