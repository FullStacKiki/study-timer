import Cocoa
// Genera AppIcon.icns: quadrato arrotondato bianco, cerchio rosso, triangolo play (design Study Timer).
let out = CommandLine.arguments[1]
func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.25); sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    sh.set()
    NSColor.white.setFill(); NSBezierPath(roundedRect: tile, xRadius: s * 0.225, yRadius: s * 0.225).fill()
    NSShadow().set()
    let d = s * 0.5
    let c = NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)
    NSColor(red: 0.898, green: 0.224, blue: 0.208, alpha: 1).setFill(); NSBezierPath(ovalIn: c).fill()
    let t = NSBezierPath()
    t.move(to: NSPoint(x: c.midX - d * 0.13, y: c.midY + d * 0.22))
    t.line(to: NSPoint(x: c.midX - d * 0.13, y: c.midY - d * 0.22))
    t.line(to: NSPoint(x: c.midX + d * 0.24, y: c.midY))
    t.close(); NSColor.white.setFill(); t.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let dir = out + ".iconset"; try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
