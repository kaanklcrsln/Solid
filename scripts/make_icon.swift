// Renders the SOLID app icon (black square, white wordmark) into an .iconset folder.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSColor(white: 0.07, alpha: 1).setFill()
    path.fill()
    NSColor(white: 0.30, alpha: 1).setStroke()
    path.lineWidth = max(1, s * 0.008)
    path.stroke()
    // storage bar
    let bar = NSRect(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.26, width: rect.width * 0.68, height: rect.height * 0.06)
    NSColor(white: 0.25, alpha: 1).setFill(); NSBezierPath(rect: bar).fill()
    NSColor(white: 0.9, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: bar.minX, y: bar.minY, width: bar.width * 0.62, height: bar.height)).fill()
    let font = NSFont.monospacedSystemFont(ofSize: s * 0.19, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.92, alpha: 1), .kern: s * 0.012]
    let text = NSAttributedString(string: "SOLID", attributes: attrs)
    let size = text.size()
    text.draw(at: NSPoint(x: (s - size.width) / 2, y: rect.minY + rect.height * 0.46))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
