// Draws the SimpleScanner app icon and writes Resources/AppIcon.icns. Usage: swift Scripts/make-icon.swift
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824 pt rounded square centred in 1024
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: color(0x000000, 0.48))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x14171C))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x222731), color(0x0E1014)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    let center = CGPoint(x: 512, y: 500)
    // Sweep: a quarter of accent light fading behind the beam
    ctx.saveGState()
    ctx.addArc(center: center, radius: 330, startAngle: .pi / 2, endAngle: .pi / 2 - 1.9, clockwise: true)
    ctx.addLine(to: center)
    ctx.closePath()
    ctx.clip()
    let sweep = CGGradient(colorsSpace: space, colors: [color(0xFFB454, 0.42), color(0xFFB454, 0.0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sweep, start: CGPoint(x: 512, y: 500), end: CGPoint(x: 820, y: 230), options: [])
    ctx.restoreGState()

    // Rings and crosshair
    for (radius, alpha) in [(330.0, 0.42), (220.0, 0.30), (110.0, 0.22)] {
        ctx.setStrokeColor(color(0xFFB454, alpha))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: center.x - 360, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + 360, y: center.y))
    ctx.move(to: CGPoint(x: center.x, y: center.y - 360)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 360))
    ctx.strokePath()

    // The beam
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26 * s, color: color(0xFFB454, 0.7))
    ctx.setStrokeColor(color(0xFFB454))
    ctx.setLineWidth(18)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + 330 * cos(0.95), y: center.y + 330 * sin(0.95)))
    ctx.strokePath()
    ctx.restoreGState()

    // Devices found: green, blue (ARP) and cyan (TCP) blips
    for (dx, dy, hex, r) in [(-150.0, 120.0, 0x9ECE6A, 26.0), (210.0, -90.0, 0x7AA2F7, 22.0), (-60.0, -230.0, 0x5CE1E6, 20.0), (120.0, 250.0, 0x9ECE6A, 18.0)] {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 22 * s, color: color(hex, 0.8))
        ctx.setFillColor(color(hex))
        ctx.fillEllipse(in: CGRect(x: center.x + dx - r, y: center.y + dy - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    // Centre
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30 * s, color: color(0xFFB454, 0.9))
    ctx.setFillColor(color(0xFFB454))
    ctx.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
    ctx.restoreGState()
    ctx.setFillColor(color(0x14171C))
    ctx.fillEllipse(in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))

    ctx.restoreGState()
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = fm.temporaryDirectory.appendingPathComponent("SimpleScanner-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try! fm.createDirectory(at: resources, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! drawIcon(size: size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! drawIcon(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(resources.path)/AppIcon.icns" : "iconutil failed")
exit(task.terminationStatus)
