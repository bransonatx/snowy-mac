import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draw in logical points. Finder gets paired 1x/2x artwork; the app icon gets
// every required size from the same paths, with no raster scaling at build time.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}
func render(_ width: Int, _ height: Int, scale: Int, to url: URL, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: width * scale, height: height * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: CGFloat(height * scale))
    context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
    draw(context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let density = 72 * scale
    CGImageDestinationAddImage(destination, context.makeImage()!, [
        kCGImagePropertyDPIWidth: density, kCGImagePropertyDPIHeight: density
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}
func label(_ text: String, at point: CGPoint, size: CGFloat, ink: CGColor,
           medium: Bool = false, centered: Bool = false, in c: CGContext) {
    let font = CTFontCreateWithName((medium ? "HelveticaNeue-Medium" : "HelveticaNeue") as CFString, size, nil)
    let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink] as CFDictionary
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
    c.saveGState()
    let offset = centered ? CTLineGetTypographicBounds(line, nil, nil, nil) / 2 : 0
    c.translateBy(x: point.x - offset, y: point.y)
    c.scaleBy(x: 1, y: -1)
    c.textPosition = .zero
    CTLineDraw(line, c)
    c.restoreGState()
}
func background(_ c: CGContext) {
    // Late-afternoon autumn: bark brown at the edges, an amber glow where the title sits.
    c.drawLinearGradient(gradient([color(0x7a3d1c), color(0x3b1d13), color(0x1c0f0c)]),
                         start: CGPoint(x: 0, y: 0), end: CGPoint(x: 650, y: 450), options: [.drawsAfterEndLocation])
    c.drawRadialGradient(gradient([color(0xf4a63c, 0.26), color(0xf4a63c, 0)]),
                         startCenter: CGPoint(x: 130, y: 45), startRadius: 0,
                         endCenter: CGPoint(x: 130, y: 45), endRadius: 330, options: [])
    // Two soft hills at the foot of the window.
    for (hill, ink) in [
        ([(0, 372), (150, 338), (330, 366), (500, 330), (660, 356)], color(0xc9692a, 0.16)),
        ([(0, 408), (170, 372), (340, 404), (520, 370), (660, 398)], color(0x120907, 0.45))
    ] {
        c.setFillColor(ink); c.beginPath(); c.move(to: CGPoint(x: 0, y: 440))
        c.addLine(to: CGPoint(x: hill[0].0, y: hill[0].1))
        for index in 1..<hill.count {
            let from = hill[index - 1], to = hill[index]
            let mid = CGFloat(from.0 + to.0) / 2
            c.addCurve(to: CGPoint(x: to.0, y: to.1), control1: CGPoint(x: mid, y: CGFloat(from.1)),
                       control2: CGPoint(x: mid, y: CGFloat(to.1)))
        }
        c.addLine(to: CGPoint(x: 660, y: 440)); c.closePath(); c.fillPath()
    }
    // Drifting leaves, kept clear of the title and the two Finder icons.
    let inks: [UInt32] = [0xf4a63c, 0xe2742a, 0xd6501a, 0xf2c14e, 0xb5391a]
    for index in 0..<58 {
        let x = CGFloat((index * 113 + 29) % 653)
        let y = CGFloat((index * 73 + 51) % 426)
        if (x < 360 && y < 130) || (y > 150 && y < 330 && x > 90 && x < 570) || (y > 337 && x > 110 && x < 550) { continue }
        let large = index.isMultiple(of: 4)
        let length: CGFloat = large ? 11 : 6.5
        c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: CGFloat(index) * 0.83)
        c.setFillColor(color(inks[index % inks.count], large ? 0.72 : 0.42))
        c.move(to: CGPoint(x: 0, y: -length))
        c.addQuadCurve(to: CGPoint(x: 0, y: length), control: CGPoint(x: length * 0.95, y: 0))
        c.addQuadCurve(to: CGPoint(x: 0, y: -length), control: CGPoint(x: -length * 0.95, y: 0))
        c.fillPath(); c.restoreGState()
    }
    label("Seasons", at: CGPoint(x: 48, y: 79), size: 47, ink: color(0xfff6ea), medium: true, in: c)
    label("Leaves in fall. Snow in winter.", at: CGPoint(x: 50, y: 109), size: 17, ink: color(0xf1cfa6), in: c)
    c.setStrokeColor(color(0xf1cfa6, 0.25)); c.setLineWidth(1)
    c.move(to: CGPoint(x: 49, y: 135)); c.addLine(to: CGPoint(x: 611, y: 135)); c.strokePath()
    label("Drag Seasons to Applications", at: CGPoint(x: 330, y: 168), size: 17,
          ink: color(0xfff1df), medium: true, centered: true, in: c)
    c.setStrokeColor(color(0xf7c98a, 0.82)); c.setLineWidth(3); c.setLineCap(.round); c.setLineJoin(.round)
    c.move(to: CGPoint(x: 285, y: 240)); c.addLine(to: CGPoint(x: 374, y: 240))
    c.move(to: CGPoint(x: 359, y: 226)); c.addLine(to: CGPoint(x: 374, y: 240))
    c.addLine(to: CGPoint(x: 359, y: 254)); c.strokePath()
    label("Then open Seasons from Applications.", at: CGPoint(x: 330, y: 361), size: 15,
          ink: color(0xfff1df), centered: true, in: c)
    label("macOS 14 or later", at: CGPoint(x: 330, y: 396), size: 12,
          ink: color(0xdcb48c), centered: true, in: c)
}
func icon(_ c: CGContext, size: CGFloat) {
    c.scaleBy(x: size / 1024, y: size / 1024)
    let box = CGRect(x: 118, y: 100, width: 788, height: 788)
    let shape = CGPath(roundedRect: box, cornerWidth: 198, cornerHeight: 198, transform: nil)
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 29), blur: 40, color: color(0x071c38, 0.38))
    c.setFillColor(color(0x8a4a22)); c.addPath(shape); c.fillPath(); c.restoreGState()
    c.saveGState(); c.addPath(shape); c.clip()
    // Winter blue in one corner, autumn orange in the other: the app covers both.
    c.drawLinearGradient(gradient([color(0x9bdcfb), color(0x4a9fe0), color(0xf4a63c), color(0xd6501a)], [0, 0.40, 0.60, 1]),
                         start: CGPoint(x: 150, y: 130), end: CGPoint(x: 874, y: 858), options: [])
    c.setFillColor(color(0xffffff, 0.30)); c.move(to: CGPoint(x: 140, y: 377))
    c.addQuadCurve(to: CGPoint(x: 884, y: 377), control: CGPoint(x: 512, y: 130))
    c.addLine(to: CGPoint(x: 884, y: 108)); c.addLine(to: CGPoint(x: 140, y: 108)); c.closePath(); c.fillPath()
    c.restoreGState()
    c.addPath(shape); c.setStrokeColor(color(0x3a2a22, 0.40)); c.setLineWidth(10); c.strokePath()
    // A single leaf, tilted as if falling.
    c.saveGState(); c.translateBy(x: 512, y: 480); c.rotate(by: .pi / 5)
    c.setLineCap(.round); c.setLineJoin(.round)
    c.setStrokeColor(color(0xffffff)); c.setLineWidth(40)
    c.move(to: CGPoint(x: 0, y: 170)); c.addLine(to: CGPoint(x: 0, y: 318)); c.strokePath()
    c.setFillColor(color(0xffffff)); c.move(to: CGPoint(x: 0, y: -290))
    c.addCurve(to: CGPoint(x: 0, y: 215), control1: CGPoint(x: 265, y: -175), control2: CGPoint(x: 240, y: 135))
    c.addCurve(to: CGPoint(x: 0, y: -290), control1: CGPoint(x: -240, y: 135), control2: CGPoint(x: -265, y: -175))
    c.fillPath()
    c.setStrokeColor(color(0xe2742a)); c.setLineWidth(24)
    c.move(to: CGPoint(x: 0, y: -165)); c.addLine(to: CGPoint(x: 0, y: 175))
    for y in [CGFloat(-35), 80] {
        c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: 112, y: y - 96))
        c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: -112, y: y - 96))
    }
    c.strokePath(); c.restoreGState()
}
let arguments = CommandLine.arguments
if arguments.count != 3 { fatalError("Usage: render-install-art.swift background|icon output-directory") }
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
switch arguments[1] {
case "background":
    for scale in [1, 2] {
        try render(660, 440, scale: scale, to: output.appendingPathComponent(scale == 1 ? "Seasons.png" : "Seasons@2x.png"), draw: background)
    }
case "icon":
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try render(size, size, scale: scale, to: output.appendingPathComponent(name)) { icon($0, size: CGFloat(size)) }
        }
    }
default: fatalError("Unknown artwork type")
}
