// Composes the Mac App Store screenshots (2880 × 1800) from the debug snapshot renders.
//   swift build && "$(swift build --show-bin-path)/Maclip" --snapshot build/snapshots
//   swift AppStore/make-screenshots.swift
// Output: AppStore/screenshots/*.png, plus smaller copies in docs/screenshots/ for the website.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let snapshots = root.appendingPathComponent("build/snapshots")
let output = root.appendingPathComponent("AppStore/screenshots")
let web = root.appendingPathComponent("docs/screenshots")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)

struct Shot {
    let file: String, image: String, headline: String, detail: String, dark: Bool
}
let shots = [
    Shot(file: "1-history", image: "panel-light", headline: "Everything you copy,\none shortcut away",
         detail: "Press ⇧⌘V in any app to see your text and image history, then paste with a click.", dark: false),
    Shot(file: "2-search", image: "panel-search-dark", headline: "Find it in\na keystroke",
         detail: "Start typing to search everything you've copied. Pin the snippets you use most.", dark: true),
    Shot(file: "3-preferences", image: "preferences-light", headline: "Make it\nyours",
         detail: "Choose how long history is kept, how many items, light or dark, and your own shortcut.", dark: false),
    Shot(file: "4-private", image: "welcome-dark", headline: "Private\nby design",
         detail: "Your history never leaves your Mac. No network access, no accounts, no tracking.", dark: true),
]

let width = 2880, height = 1800
let icon = NSImage(contentsOf: root.appendingPathComponent("Support/AppIcon-1024.png"))!

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func compose(_ shot: Shot) throws {
    guard let window = NSImage(contentsOf: snapshots.appendingPathComponent("\(shot.image).png")),
          let windowRep = window.representations.first else {
        throw NSError(domain: "screenshots", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing \(shot.image).png; run the --snapshot step first"])
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)

    // Background: the icon's blue-violet for light shots, deep navy for dark ones.
    let colors = shot.dark ? [color(0x1B1D3A), color(0x2A1E5C)] : [color(0x4FA8FF), color(0x5A5CF2), color(0x7B3FE4)]
    NSGradient(colors: colors)!.draw(in: canvas, angle: -35)

    // Brand row.
    let left: CGFloat = 220
    icon.draw(in: NSRect(x: left, y: 1440, width: 132, height: 132))
    NSAttributedString(string: "Maclip", attributes: [
        .font: NSFont.systemFont(ofSize: 64, weight: .semibold), .foregroundColor: NSColor.white,
    ]).draw(at: NSPoint(x: left + 160, y: 1470))

    // Headline and detail text.
    let headline = NSMutableParagraphStyle(); headline.lineSpacing = 6
    NSAttributedString(string: shot.headline, attributes: [
        .font: NSFont.systemFont(ofSize: 132, weight: .bold), .foregroundColor: NSColor.white,
        .paragraphStyle: headline, .kern: -2,
    ]).draw(in: NSRect(x: left, y: 760, width: 1200, height: 600))
    let detail = NSMutableParagraphStyle(); detail.lineSpacing = 10
    NSAttributedString(string: shot.detail, attributes: [
        .font: NSFont.systemFont(ofSize: 52, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: detail,
    ]).draw(in: NSRect(x: left, y: 560, width: 1080, height: 340))

    // The window, scaled to fit the right half, with rounded corners and a soft shadow.
    let source = NSSize(width: windowRep.pixelsWide, height: windowRep.pixelsHigh)
    let scale = min(1360 / source.height, 1300 / source.width)
    let size = NSSize(width: source.width * scale, height: source.height * scale)
    let frame = NSRect(x: 2880 - 230 - size.width, y: (1800 - size.height) / 2 - 20, width: size.width, height: size.height)
    let shape = NSBezierPath(roundedRect: frame, xRadius: 40, yRadius: 40)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 70
    shadow.shadowOffset = NSSize(width: 0, height: -30)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    window.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    // App Store screenshots must not have an alpha channel: flatten to RGB with CoreGraphics
    // (AppKit can't draw into a bitmap without alpha), plus a 1440-wide JPEG for the website.
    let full = rep.cgImage!
    try write(flatten(full, width: width, height: height), to: output.appendingPathComponent("\(shot.file).png"),
              type: "public.png")
    try write(flatten(full, width: 1440, height: 900), to: web.appendingPathComponent("\(shot.file).jpg"),
              type: "public.jpeg", quality: 0.82)
    print("wrote \(shot.file)")
}

func flatten(_ image: CGImage, width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL, type: String, quality: Double? = nil) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
    CGImageDestinationAddImage(dest, image, options)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "screenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "could not write \(url.path)"])
    }
}

for shot in shots { try compose(shot) }
