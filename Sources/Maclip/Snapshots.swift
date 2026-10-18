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
        let store = HistoryStore(fileURL: nil)
        let now = Date()
        let samples: [(String, TimeInterval)] = [
            ("Meeting moved to Thursday 3pm — same Zoom link as last week.", 26 * 3600),
            ("git checkout -b feature/clipboard-search", 5 * 3600),
            ("https://developer.apple.com/documentation/appkit/nspasteboard", 3 * 3600),
            ("Dear Ms. Patel,\nThank you for your quick reply.\nI've attached the signed contract.", 2400),
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

        func capture(_ suffix: String) {
            let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 50 }
            for window in windows {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window is HistoryPanel ? "panel"
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
                NSApp.terminate(nil)
            }
        }
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
