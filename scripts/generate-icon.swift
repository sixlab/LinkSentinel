#!/usr/bin/env swift
import AppKit
import Foundation

// 原创矢量绘制：蓝色圆角底、监控圆环与心跳线。无需外部图片或依赖。
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
let catalog = resources.appendingPathComponent("Assets.xcassets")
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: appIcon, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let scale = CGFloat(size) / 1024
    graphics.cgContext.scaleBy(x: scale, y: scale)
    graphics.imageInterpolation = .high
    graphics.shouldAntialias = true

    let background = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.31, blue: 0.84, alpha: 1).setFill()
    background.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.80, alpha: 1),
               ending: NSColor(calibratedRed: 0.16, green: 0.69, blue: 0.98, alpha: 1))!
        .draw(in: background, angle: 65)

    let ring = NSBezierPath(ovalIn: NSRect(x: 264, y: 264, width: 496, height: 496))
    ring.lineWidth = 24
    NSColor.white.withAlphaComponent(0.24).setStroke()
    ring.stroke()

    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: 248, y: 504))
    pulse.line(to: NSPoint(x: 364, y: 504))
    pulse.line(to: NSPoint(x: 433, y: 638))
    pulse.line(to: NSPoint(x: 512, y: 372))
    pulse.line(to: NSPoint(x: 590, y: 576))
    pulse.line(to: NSPoint(x: 650, y: 504))
    pulse.line(to: NSPoint(x: 776, y: 504))
    pulse.lineWidth = 66
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor.white.setStroke()
    pulse.stroke()
    return bitmap.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let data = render(size: size * scale)
        try data.write(to: iconset.appendingPathComponent(filename))
        try data.write(to: appIcon.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x"])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: appIcon.appendingPathComponent("Contents.json"))
try render(size: 512).write(to: resources.appendingPathComponent("AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", resources.appendingPathComponent("AppIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("已生成 AppIcon 资源目录、ICNS 与预览图。")
