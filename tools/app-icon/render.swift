// Builds every Meldo app icon from one image, Design/meldo-icon.png (white hand and
// sparkles on a blue gradient). Usage: swift tools/app-icon/render.swift
//
// iOS light is the image itself. For the other variants the hand and sparkles are cut out of
// the blue (the nails are background blue, so they become holes) and placed on that variant's
// background. Android gets the cut-out as its foreground and monochrome layers.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appending(path: "MeldePlanner/Resources/Assets.xcassets")
// The Android icon layers go to a meldo-android checkout next to this repo, if there is one.
let drawable = root.deletingLastPathComponent().appending(path: "meldo-android/app/src/main/res/drawable-nodpi")
let size = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct RGB { var r, g, b: Double }

func pixels(of image: CGImage, side: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: side * side * 4)
    let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return px
}

func image(from px: [UInt8], side: Int) -> CGImage {
    var copy = px
    let ctx = CGContext(data: &copy, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL, opaque: Bool) {
    var out = image
    if opaque {
        let flat = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        flat.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        out = flat.makeImage()!
    }
    try! NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

guard let source = NSImage(contentsOf: root.appending(path: "Design/meldo-icon.png"))?
    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("missing Design/meldo-icon.png") }
let src = pixels(of: source, side: size)

// The source background, sampled down the centre: lighter blue at the top, deeper at the bottom.
let bgTop = RGB(r: 0x32, g: 0x44, b: 0xFB), bgBottom = RGB(r: 0x20, g: 0x1F, b: 0xD8)

// Cut-out: how far a pixel is from "background blue" (blue far above red and green) sets its
// alpha; the colour is un-mixed from the background so edges and the sparkle glow stay clean.
var cutout = [UInt8](repeating: 0, count: size * size * 4)
var mono = [UInt8](repeating: 0, count: size * size * 4)
for y in 0..<size {
    let t = Double(y) / Double(size - 1)
    let bg = RGB(r: bgTop.r + (bgBottom.r - bgTop.r) * t, g: bgTop.g + (bgBottom.g - bgTop.g) * t, b: bgTop.b + (bgBottom.b - bgTop.b) * t)
    for x in 0..<size {
        let i = (y * size + x) * 4
        let r = Double(src[i]), g = Double(src[i + 1]), b = Double(src[i + 2])
        let blueness = b - max(r, g)
        let a = min(1, max(0, (150 - blueness) / 90))
        guard a > 0 else { continue }
        func unmix(_ c: Double, _ k: Double) -> Double { min(255, max(0, (c - (1 - a) * k) / a)) }
        let (fr, fg, fb) = (unmix(r, bg.r), unmix(g, bg.g), unmix(b, bg.b))
        cutout[i] = UInt8(fr * a); cutout[i + 1] = UInt8(fg * a); cutout[i + 2] = UInt8(fb * a); cutout[i + 3] = UInt8(a * 255)
        let lum = (0.299 * fr + 0.587 * fg + 0.114 * fb) / 255
        let m = a * min(1, lum * 1.15)   // tinted/monochrome: white where the hand is, fading with shading
        mono[i] = UInt8(255 * m); mono[i + 1] = UInt8(255 * m); mono[i + 2] = UInt8(255 * m); mono[i + 3] = UInt8(255 * m)
    }
}
let cutoutImage = image(from: cutout, side: size)
let monoImage = image(from: mono, side: size)

func onGradient(_ top: String, _ bottom: String) -> CGImage {
    func color(_ hex: String) -> CGColor {
        let v = Int(hex.dropFirst(), radix: 16)!
        return CGColor(srgbRed: CGFloat(v >> 16) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.drawLinearGradient(CGGradient(colorsSpace: sRGB, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: size), end: .zero, options: [])
    ctx.draw(cutoutImage, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

// iOS
write(image(from: src, side: size), to: assets.appending(path: "AppIcon.appiconset/icon-light.png"), opaque: true)
write(cutoutImage, to: assets.appending(path: "AppIcon.appiconset/icon-dark.png"), opaque: false)
write(monoImage, to: assets.appending(path: "AppIcon.appiconset/icon-tinted.png"), opaque: false)
write(onGradient("#FFAE66", "#F2843A"), to: assets.appending(path: "AppIcon-Orange.appiconset/icon-orange.png"), opaque: true)
write(onGradient("#1E2040", "#0E0F1F"), to: assets.appending(path: "AppIcon-Night.appiconset/icon-night.png"), opaque: true)

// Android adaptive layers: 108 dp at 4x = 432 px; the 1024 artwork fills the middle 66 dp so
// the hand and sparkles stay inside the 66 dp safe circle.
func androidLayer(_ art: CGImage) -> CGImage {
    let side = 432, inner = 264
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let o = (side - inner) / 2
    ctx.draw(art, in: CGRect(x: o, y: o, width: inner, height: inner))
    return ctx.makeImage()!
}
try? FileManager.default.createDirectory(at: drawable, withIntermediateDirectories: true)
write(androidLayer(cutoutImage), to: drawable.appending(path: "ic_launcher_foreground.png"), opaque: false)
write(androidLayer(monoImage), to: drawable.appending(path: "ic_launcher_monochrome.png"), opaque: false)
