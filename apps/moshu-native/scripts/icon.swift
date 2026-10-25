import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Moshu.iconset")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let image = NSImage(size: NSSize(width: px, height: px))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: Double(px) * 0.08, dy: Double(px) * 0.08)
        let path = NSBezierPath(roundedRect: rect, xRadius: Double(px) * 0.2, yRadius: Double(px) * 0.2)
        NSGradient(starting: NSColor(red: 0.12, green: 0.56, blue: 0.54, alpha: 1), ending: NSColor(red: 0.04, green: 0.28, blue: 0.32, alpha: 1))!.draw(in: path, angle: -70)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Double(px) * 0.53, weight: .medium), .foregroundColor: NSColor.white]
        let text = "墨" as NSString
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (Double(px) - textSize.width) / 2, y: (Double(px) - textSize.height) / 2), withAttributes: attrs)
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
