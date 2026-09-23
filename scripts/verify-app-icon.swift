#!/usr/bin/env swift
import AppKit
import Foundation

// 通过真实的 macOS 图标服务检查打包产物；不截屏、不读取通知、不修改系统设置。
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let appURL = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? project.appendingPathComponent("build/链接哨兵.app")

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("验证失败：\(message)\n".utf8))
        exit(1)
    }
}

guard let bundle = Bundle(url: appURL), let identifier = bundle.bundleIdentifier,
      let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else {
    require(false, "应用缺少 Bundle ID 或 CFBundleIconFile")
    exit(1)
}
let iconName = (name as NSString).deletingPathExtension
guard let assetName = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
      !assetName.isEmpty,
      bundle.url(forResource: "Assets", withExtension: "car") != nil,
      let catalogIcon = bundle.image(forResource: NSImage.Name(assetName)) else {
    require(false, "应用缺少已编译的 AppIcon 资源目录或 CFBundleIconName 无法加载")
    exit(1)
}
guard let iconURL = bundle.url(forResource: iconName, withExtension: "icns"),
      let resource = NSImage(contentsOf: iconURL) else {
    require(false, "声明的 ICNS 图标不能加载")
    exit(1)
}
let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
require(registeredURL?.resolvingSymlinksInPath().standardizedFileURL == appURL.resolvingSymlinksInPath().standardizedFileURL,
        "系统选中了其他应用副本：\(registeredURL?.path ?? "未注册")")
print("注册路径正确：\(appURL.path)")

for (label, icon) in [("ICNS 兼容资源", resource), ("命名图标资源", catalogIcon), ("系统图标服务", NSWorkspace.shared.icon(forFile: appURL.path))] {
    for size in [32, 64, 128, 256] {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var visible = 0
        var blue = 0
        for y in stride(from: 0, to: size, by: 4) {
            for x in stride(from: 0, to: size, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.1 else { continue }
                visible += 1
                if color.blueComponent > color.redComponent + 0.1 { blue += 1 }
            }
        }
        let samples = (size / 4) * (size / 4)
        require(visible > samples / 4 && blue > samples / 8, "\(label) \(size)px 为空白或不是蓝色应用图标")
        print("\(label) \(size)px：图案正常")
    }
}
print("图标集成验证通过，构建号 \(bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "未知")")
