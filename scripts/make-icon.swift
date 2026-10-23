// Renders Glink's app icon at every size macOS needs and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // Body: Apple's 824pt grid inside a 1024 canvas, with a soft drop shadow.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 185 * s
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [NSColor(srgbRed: 0.10, green: 0.09, blue: 0.27, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.96, green: 0.45, blue: 0.71, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 0.78, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

    // Soft light bloom in the upper-left.
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: body.minX + 230 * s, y: body.maxY - 200 * s), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + 230 * s, y: body.maxY - 200 * s), endRadius: 520 * s, options: [])

    // A frosted "command bar" floating in the middle.
    let bar = CGRect(x: body.minX + 120 * s, y: body.midY - 95 * s, width: 584 * s, height: 190 * s)
    let barPath = CGPath(roundedRect: bar, cornerWidth: 64 * s, cornerHeight: 64 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(barPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Magnifying glass inside the bar.
    let lensCenter = CGPoint(x: bar.minX + 112 * s, y: bar.midY + 10 * s)
    ctx.setStrokeColor(NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1).cgColor)
    ctx.setLineWidth(22 * s)
    ctx.setLineCap(.round)
    ctx.strokeEllipse(in: CGRect(x: lensCenter.x - 38 * s, y: lensCenter.y - 38 * s, width: 76 * s, height: 76 * s))
    ctx.move(to: CGPoint(x: lensCenter.x + 28 * s, y: lensCenter.y - 28 * s))
    ctx.addLine(to: CGPoint(x: lensCenter.x + 62 * s, y: lensCenter.y - 62 * s))
    ctx.strokePath()

    // Typed text + caret.
    ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.09, blue: 0.27, alpha: 0.85).cgColor)
    let textBar = CGPath(roundedRect: CGRect(x: bar.minX + 200 * s, y: bar.midY - 14 * s, width: 230 * s, height: 28 * s),
                         cornerWidth: 14 * s, cornerHeight: 14 * s, transform: nil)
    ctx.addPath(textBar)
    ctx.fillPath()
    ctx.setFillColor(NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1).cgColor)
    ctx.fill(CGRect(x: bar.minX + 450 * s, y: bar.midY - 40 * s, width: 14 * s, height: 80 * s))

    // Spark above the bar.
    func spark(center: CGPoint, r: CGFloat, alpha: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: center.x, y: center.y + r))
        p.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y), control: center)
        p.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r), control: center)
        ctx.addPath(p)
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
    }
    spark(center: CGPoint(x: bar.maxX - 40 * s, y: bar.maxY + 120 * s), r: 70 * s, alpha: 0.95)
    spark(center: CGPoint(x: bar.maxX - 150 * s, y: bar.maxY + 200 * s), r: 32 * s, alpha: 0.7)

    // Glass edge highlight.
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    ctx.setLineWidth(4 * s)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let rep = render(size: CGFloat(points * scale))
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(name)"))
    }
}
print("Wrote \(output)")
