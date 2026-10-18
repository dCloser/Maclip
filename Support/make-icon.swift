// Draws Maclip's app icon and writes the AppIcon asset catalog.
//   swift Support/make-icon.swift
// Output: Support/Assets.xcassets/AppIcon.appiconset (all macOS sizes) + Support/AppIcon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws the icon on a 1024×1024 canvas (origin bottom-left), scaled to `size` pixels.
func drawIcon(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.interpolationQuality = .high

    // Tile: Apple's macOS icon grid, 824×824 with ~185 corner radius and a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = roundedRect(tile, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x4A5BF0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x3FA0FF), color(0x5A5CF2), color(0x7B3FE4)]),
                           start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Gentle highlight across the top.
    ctx.drawLinearGradient(gradient([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])

    // History: two sheets fanned out behind the clipboard.
    for (angle, alpha, dx) in [(CGFloat(11), CGFloat(0.28), CGFloat(70)), (5, 0.45, 36)] {
        ctx.saveGState()
        ctx.translateBy(x: 512 + dx, y: 470)
        ctx.rotate(by: -angle * .pi / 180)
        ctx.addPath(roundedRect(CGRect(x: -230, y: -280, width: 460, height: 560), 56))
        ctx.setFillColor(color(0xFFFFFF, alpha)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Clipboard board.
    let board = CGRect(x: 282, y: 190, width: 460, height: 560)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x1A1060, 0.35))
    ctx.addPath(roundedRect(board, 56)); ctx.setFillColor(color(0xF6F8FF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedRect(board, 56)); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0xFFFFFF), color(0xE7ECFA)]),
                           start: CGPoint(x: 512, y: board.maxY), end: CGPoint(x: 512, y: board.minY), options: [])
    ctx.restoreGState()

    // List rows: the second one is "selected", like the picker panel.
    let left = board.minX + 52, width = board.width - 104
    ctx.addPath(roundedRect(CGRect(x: board.minX + 26, y: 470, width: board.width - 52, height: 92), 26))
    ctx.setFillColor(color(0x5A6CF5, 0.16)); ctx.fillPath()
    let rows: [(y: CGFloat, w: CGFloat, c: CGColor)] = [
        (606, 1.00, color(0xC8D1EC)),
        (500, 0.86, color(0x5A63F0)),
        (394, 0.94, color(0xC8D1EC)),
        (288, 0.62, color(0xC8D1EC)),
    ]
    for row in rows {
        ctx.addPath(roundedRect(CGRect(x: left, y: row.y, width: width * row.w, height: 32), 16))
        ctx.setFillColor(row.c); ctx.fillPath()
    }

    // Clip at the top of the board.
    let clip = CGRect(x: 512 - 118, y: board.maxY - 52, width: 236, height: 104)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x10083A, 0.35))
    ctx.addPath(roundedRect(clip, 34)); ctx.setFillColor(color(0x26305A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(roundedRect(clip, 34)); ctx.clip()
    ctx.drawLinearGradient(gradient([color(0x3B4777), color(0x1E2650)]),
                           start: CGPoint(x: 512, y: clip.maxY), end: CGPoint(x: 512, y: clip.minY), options: [])
    ctx.restoreGState()
    // Hole in the clip.
    ctx.addPath(roundedRect(CGRect(x: 512 - 46, y: clip.maxY - 44, width: 92, height: 24), 12))
    ctx.setFillColor(color(0x6F7FF6)); ctx.fillPath()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "could not write \(url.path)")
}

let support = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let set = support.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        writePNG(drawIcon(size: points * scale), to: set.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: support.appendingPathComponent("Assets.xcassets/Contents.json"))
writePNG(drawIcon(size: 1024), to: support.appendingPathComponent("AppIcon-1024.png"))
print("Wrote \(set.path)")
