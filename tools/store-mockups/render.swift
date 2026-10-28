// App Store screenshot mockups for Meldo: real app screenshots in a drawn device
// frame on a brand background, with a headline and one supporting line.
// Usage: swift tools/store-mockups/render.swift <spec.json>
// spec: {"outDir": "...", "shots": [{"device": "iphone"|"ipad", "image": "...png",
//        "out": "01.png", "headline": "Melden mit *einem Tipp*", "sub": "..."}]}
// Words between *stars* in the headline are drawn in Meldo orange.
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shot: Decodable { let device, image, out, headline, sub: String }
/// `statusDate`: the date next to the iPad clock, matching the app's demo clock (e.g. "Fr. 23. Okt.").
struct Spec: Decodable { let outDir: String; let statusDate: String?; let shots: [Shot] }

// Warm near black fading to neutral black; the orange glow does the warming.
let ink = CGColor(red: 0x08 / 255, green: 0x08 / 255, blue: 0x0A / 255, alpha: 1)
let warmTop = CGColor(red: 0x1A / 255, green: 0x12 / 255, blue: 0x0E / 255, alpha: 1)
let orange = NSColor(red: 0xFF / 255, green: 0x9A / 255, blue: 0x4D / 255, alpha: 1)

/// App Store sizes: iPhone 6.9" portrait, iPad 13" portrait or landscape.
func canvas(_ device: String) -> CGSize {
    switch device {
    case "ipad": CGSize(width: 2064, height: 2752)
    case "ipad-landscape": CGSize(width: 2752, height: 2064)
    default: CGSize(width: 1320, height: 2868)
    }
}

func load(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(path)") }
    return img
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    else { fatalError("no symbol \(name)") }
    return image
}

/// Real captures show the real clock and battery. Paint over the status bar by
/// stretching its own top pixel row, above the clock and icons (keeps sidebar and
/// content colors apart), then draw a clean one: 9:41, full signal, Wi-Fi, full battery.
func cleanStatusBar(_ screen: CGImage, in ctx: CGContext, screenRect: CGRect, ipad: Bool, landscape: Bool, date: String) {
    // Screen width in points, status bar height and text layout in points.
    let points: CGFloat = landscape ? 1366 : ipad ? 1024 : 428
    let pt = screenRect.width / points
    let barPoints: CGFloat = ipad ? 24 : 42
    // Shrink the row first so the timetable grid behind the bar's blur doesn't streak.
    let row = screen.cropping(to: CGRect(x: 0, y: 2, width: screen.width, height: 1))!
    let small = CGContext(data: nil, width: screen.width / 10, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    small.interpolationQuality = .high
    small.draw(row, in: CGRect(x: 0, y: 0, width: small.width, height: 1))
    ctx.draw(small.makeImage()!, in: CGRect(x: screenRect.minX, y: screenRect.maxY - barPoints * pt, width: screenRect.width, height: barPoints * pt))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    // Vertical center of the status bar content, measured from the screen's top.
    let centerY = screenRect.maxY - (ipad ? 13 : 24) * pt
    let fontSize: CGFloat = (ipad ? 15 : 17) * pt

    let time = NSMutableAttributedString(string: "9:41", attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor.white,
    ])
    if ipad {
        time.append(NSAttributedString(string: "  " + date, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: NSColor.white,
        ]))
    }
    let timeSize = time.size()
    // iPhone: centered in the left ear; iPad: 20 pt from the edge.
    let timeX = ipad ? screenRect.minX + 20 * pt : screenRect.minX + 76 * pt - timeSize.width / 2
    time.draw(at: CGPoint(x: timeX, y: centerY - timeSize.height / 2 - fontSize * 0.04))

    // Right side, drawn right to left.
    let icons = [("battery.100percent", (ipad ? 15 : 17) * pt, NSFont.Weight.regular),
                 ("wifi", (ipad ? 13 : 15) * pt, .semibold),
                 ("cellularbars", (ipad ? 13 : 15) * pt, .semibold)]
    var right = screenRect.maxX - (ipad ? 20 : 30) * pt
    for (name, size, weight) in icons {
        let image = symbol(name, size: size, weight: weight)
        right -= image.size.width
        image.draw(in: CGRect(x: right, y: centerY - image.size.height / 2, width: image.size.width, height: image.size.height))
        right -= 6 * pt
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// Landscape captures come out in the device's portrait orientation, turned a quarter
/// clockwise: turn them back.
func uprightLandscape(_ image: CGImage) -> CGImage {
    guard image.height > image.width else { return image }
    let ctx = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: CGFloat(image.height), y: 0)
    ctx.rotate(by: .pi / 2)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func headline(_ text: String, size: CGFloat) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 0.95
    let out = NSMutableAttributedString()
    for (i, part) in text.components(separatedBy: "*").enumerated() {
        out.append(NSAttributedString(string: part, attributes: [
            .font: font, .foregroundColor: i % 2 == 1 ? orange : NSColor.white,
            .kern: -size * 0.02, .paragraphStyle: para,
        ]))
    }
    return out
}

func body(_ text: String, size: CGFloat) -> NSAttributedString {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = 1.1
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.72), .paragraphStyle: para,
    ])
}

/// Draws attributed text centered in `width`, top at `top` (y-down), returns its height.
func draw(_ text: NSAttributedString, in ctx: CGContext, top: CGFloat, width: CGFloat, canvas: CGSize) -> CGFloat {
    let setter = CTFramesetterCreateWithAttributedString(text)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    let rect = CGRect(x: (canvas.width - width) / 2, y: canvas.height - top - fit.height, width: width, height: ceil(fit.height))
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil), ctx)
    return ceil(fit.height)
}

func render(_ shot: Shot, outDir: String, date: String) {
    let size = canvas(shot.device)
    let ipad = shot.device.hasPrefix("ipad")
    let landscape = shot.device == "ipad-landscape"
    guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("no context") }

    // Background: warm near black with an orange glow behind the device (always orange).
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [warmTop, ink] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [orange.withAlphaComponent(0.22).cgColor, orange.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    let glowCenter = CGPoint(x: size.width * 0.5, y: size.height * (ipad ? 0.45 : 0.55))
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: size.width * (ipad ? 0.6 : 0.9), options: [])

    // Text block.
    let margin = size.width * 0.08
    var top = size.height * (ipad ? 0.055 : 0.06)
    top += draw(headline(shot.headline, size: ipad ? 118 : 104), in: ctx, top: top, width: size.width - 2 * margin, canvas: size)
    top += ipad ? 36 : 30
    top += draw(body(shot.sub, size: ipad ? 52 : 46), in: ctx, top: top, width: size.width - 2 * margin, canvas: size)

    // Device: titanium rim, black bezel, screenshot.
    let screen = landscape ? uprightLandscape(load(shot.image)) : load(shot.image)
    let deviceWidth = size.width * (landscape ? 0.78 : ipad ? 0.84 : 0.80)
    let rim: CGFloat = ipad ? 7 : 8
    let bezel: CGFloat = ipad ? 30 : 26
    let screenWidth = deviceWidth - 2 * bezel
    let screenHeight = screenWidth * CGFloat(screen.height) / CGFloat(screen.width)
    let deviceTop = top + (ipad ? 90 : 80)
    let device = CGRect(x: (size.width - deviceWidth) / 2, y: size.height - deviceTop - (screenHeight + 2 * bezel),
                        width: deviceWidth, height: screenHeight + 2 * bezel)
    let outerRadius: CGFloat = ipad ? 88 : 150
    let innerRadius = outerRadius - bezel * 0.85
    let shell = CGPath(roundedRect: device, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
    let titanium = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0.66, alpha: 1), CGColor(gray: 0.30, alpha: 1),
                                                          CGColor(gray: 0.22, alpha: 1), CGColor(gray: 0.46, alpha: 1)] as CFArray,
                              locations: [0, 0.35, 0.7, 1])!
    func fillTitanium(_ path: CGPath, _ rect: CGRect) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(titanium, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        ctx.restoreGState()
    }

    // Two shadows: a wide soft one for depth, a tight one where the device meets the page.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -70), blur: 180, color: CGColor(gray: 0, alpha: 0.6))
    ctx.addPath(shell)
    ctx.fillPath()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.5))
    ctx.addPath(shell)
    ctx.fillPath()
    ctx.restoreGState()

    if !ipad {
        // Side buttons (iPhone Pro proportions): action and volume left, side button right.
        let h = device.height
        for (right, from, length) in [(false, 0.165, 0.045), (false, 0.235, 0.075), (false, 0.33, 0.075), (true, 0.27, 0.11)] {
            let rect = CGRect(x: right ? device.maxX - 4 : device.minX - 7, y: device.maxY - h * (from + length), width: 11, height: h * length)
            fillTitanium(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil), rect)
        }
    }
    fillTitanium(shell, device)
    // Light catching the rim's outer edge.
    ctx.addPath(CGPath(roundedRect: device.insetBy(dx: 1.5, dy: 1.5), cornerWidth: outerRadius - 1.5, cornerHeight: outerRadius - 1.5, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
    ctx.setLineWidth(2)
    ctx.strokePath()
    let glass = device.insetBy(dx: rim, dy: rim)
    ctx.addPath(CGPath(roundedRect: glass, cornerWidth: outerRadius - rim, cornerHeight: outerRadius - rim, transform: nil))
    ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
    ctx.fillPath()

    let screenRect = device.insetBy(dx: bezel, dy: bezel)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(screen, in: screenRect)
    cleanStatusBar(screen, in: ctx, screenRect: screenRect, ipad: ipad, landscape: landscape, date: date)
    ctx.restoreGState()

    if !ipad {
        // Dynamic Island.
        let islandW = screenRect.width * 0.30, islandH = screenRect.width * 0.088
        let island = CGRect(x: screenRect.midX - islandW / 2, y: screenRect.maxY - screenRect.width * 0.03 - islandH, width: islandW, height: islandH)
        ctx.addPath(CGPath(roundedRect: island, cornerWidth: islandH / 2, cornerHeight: islandH / 2, transform: nil))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
    }

    guard let image = ctx.makeImage() else { fatalError("no image") }
    let url = URL(fileURLWithPath: outDir).appending(path: shot.out)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
    print("wrote \(url.path) \(Int(size.width))x\(Int(size.height))")
}

let specURL = URL(fileURLWithPath: CommandLine.arguments[1])
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: specURL))
try FileManager.default.createDirectory(atPath: spec.outDir, withIntermediateDirectories: true)
for shot in spec.shots { render(shot, outDir: spec.outDir, date: spec.statusDate ?? "Mo. 19. Okt.") }
