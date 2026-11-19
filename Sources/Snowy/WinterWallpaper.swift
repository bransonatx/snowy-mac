import CoreGraphics
import Foundation
import SnowCore

/// The starter artwork: Snowy's two winter scenes and Seasons' two autumn ones. Each image is
/// drawn only when previewed or applied. The type keeps its original name because the raw
/// values identify saved wallpapers.
enum WinterWallpaper: String, CaseIterable, Sendable {
    case blueHour = "blue-hour"
    case alpenglow
    case goldenHour = "golden-hour"
    case harvestMoon = "harvest-moon"

    var title: String {
        switch self {
        case .blueHour: "Blue Hour"
        case .alpenglow: "Alpenglow"
        case .goldenHour: "Golden Hour"
        case .harvestMoon: "Harvest Moon"
        }
    }

    var season: Season {
        switch self {
        case .blueHour, .alpenglow: .winter
        case .goldenHour, .harvestMoon: .fall
        }
    }

    func makeImage(width: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: width * 9 / 16,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let scale = CGFloat(width) / 1_600
        context.scaleBy(x: scale, y: scale)
        if season == .fall {
            drawAutumn(context, space: space)
            return context.makeImage()
        }
        let blue = self == .blueHour
        let sky = blue ? [0x0b1c38, 0x2d5578, 0x8ca7b2] : [0x201c38, 0x57496a, 0xb57e84]
        if let gradient = CGGradient(colorsSpace: space, colors: sky.map { color($0) } as CFArray,
                                     locations: [0, 0.65, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 650, y: 900),
                                       end: CGPoint(x: 1_030, y: 250),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        let moon = blue ? CGPoint(x: 1_220, y: 687) : CGPoint(x: 384, y: 561)
        let moonlight = blue ? 0xe3edf0 : 0xffd3ab
        if let glow = CGGradient(colorsSpace: space,
                                 colors: [color(moonlight, opacity: 0.17), color(moonlight, opacity: 0)] as CFArray,
                                 locations: [0, 1]) {
            context.drawRadialGradient(glow, startCenter: moon, startRadius: 0,
                                       endCenter: moon, endRadius: 124, options: [])
        }
        context.setFillColor(color(moonlight, opacity: 0.91))
        context.fillEllipse(in: CGRect(x: moon.x - 29, y: moon.y - 29, width: 58, height: 58))
        for index in 0..<62 {
            let x = (index * 233 + 53) % 1_600
            let y = (index * index * 27 + index * 89) % 420 + 470
            let size = index.isMultiple(of: 9) ? 3 : 1
            let opacity = CGFloat((index * 13) % 5 + 1) * (blue ? 0.12 : 0.07)
            context.setFillColor(color(0xe6edff, opacity: opacity))
            context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }

        polygon(context, [(0, 237), (168, 306), (318, 280), (562, 425), (690, 325), (784, 348),
                          (899, 256), (1_079, 350), (1_272, 288), (1_469, 407), (1_600, 325),
                          (1_600, 0), (0, 0)], blue ? 0x3b5673 : 0x735971)
        polygon(context, [(377, 316), (562, 425), (690, 325), (598, 353), (556, 338), (527, 365)],
                blue ? 0x92a7bc : 0xc69c9a)
        polygon(context, [(1_311, 312), (1_469, 407), (1_600, 325), (1_515, 345),
                          (1_456, 332), (1_446, 355)], blue ? 0x889fb7 : 0xc69899)
        polygon(context, [(0, 210), (192, 254), (357, 178), (517, 227), (641, 196),
                          (895, 284), (1_066, 219), (1_169, 241), (1_335, 179), (1_600, 250),
                          (1_600, 0), (0, 0)], blue ? 0x263d58 : 0x463d56)

        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 0, y: 126))
        hill.addQuadCurve(to: CGPoint(x: 780, y: 83), control: CGPoint(x: 370, y: 32))
        hill.addQuadCurve(to: CGPoint(x: 1_600, y: 128), control: CGPoint(x: 1_223, y: 142))
        hill.addLines(between: [CGPoint(x: 1_600, y: 0), .zero])
        hill.closeSubpath()
        context.addPath(hill)
        context.setFillColor(color(blue ? 0x1b2e48 : 0x322c46))
        context.fillPath()

        for index in 0..<24 {
            let x = CGFloat(index * 47 + (index * 73) % 32) + (blue ? 2 : 485)
            let y = CGFloat((index * 29) % 47 + 89)
            let height = CGFloat((index * 37) % 88 + 30)
            tree(context, x: x, y: y, height: height, fill: blue ? 0x182c42 : 0x2d263e)
        }
        if !blue { cabin(context) }
        return context.makeImage()
    }

    /// The same ridges and hill as the winter scenes, in autumn light: a low sun over turning
    /// trees by day, or a harvest moon over a lit cabin by night.
    private func drawAutumn(_ context: CGContext, space: CGColorSpace) {
        let day = self == .goldenHour
        let sky = day ? [0x4d7fa8, 0xdcae86, 0xf6d9a2] : [0x10182f, 0x3b2c52, 0xb5653a]
        if let gradient = CGGradient(colorsSpace: space, colors: sky.map { color($0) } as CFArray,
                                     locations: [0, 0.62, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 650, y: 900),
                                       end: CGPoint(x: 1_030, y: 250),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        let light = day ? CGPoint(x: 1_190, y: 470) : CGPoint(x: 1_215, y: 660)
        let glowColour = day ? 0xfff0c4 : 0xffb968
        if let glow = CGGradient(colorsSpace: space,
                                 colors: [color(glowColour, opacity: day ? 0.5 : 0.26), color(glowColour, opacity: 0)] as CFArray,
                                 locations: [0, 1]) {
            context.drawRadialGradient(glow, startCenter: light, startRadius: 0,
                                       endCenter: light, endRadius: day ? 330 : 210, options: [])
        }
        let radius: CGFloat = day ? 44 : 60
        context.setFillColor(color(day ? 0xfff6dc : 0xffc777, opacity: 0.96))
        context.fillEllipse(in: CGRect(x: light.x - radius, y: light.y - radius, width: radius * 2, height: radius * 2))
        if day {
            // Thin evening cloud bands.
            for (x, y, w, h, opacity): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) in [
                (180, 640, 420, 22, 0.30), (300, 668, 300, 14, 0.22), (820, 720, 360, 18, 0.24),
                (1_240, 600, 300, 16, 0.26), (60, 540, 260, 12, 0.18),
            ] {
                context.setFillColor(color(0xfff1dd, opacity: opacity))
                context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
        } else {
            for index in 0..<62 {
                let x = (index * 233 + 53) % 1_600
                let y = (index * index * 27 + index * 89) % 420 + 470
                let size = index.isMultiple(of: 9) ? 3 : 1
                context.setFillColor(color(0xfde9cf, opacity: CGFloat((index * 13) % 5 + 1) * 0.09))
                context.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
            // Craters keep the big moon from reading as a sun.
            for (dx, dy, r): (CGFloat, CGFloat, CGFloat) in [(-20, 14, 11), (16, -8, 15), (8, 26, 7), (-24, -22, 8)] {
                context.setFillColor(color(0xe79a4e, opacity: 0.42))
                context.fillEllipse(in: CGRect(x: light.x + dx - r, y: light.y + dy - r, width: r * 2, height: r * 2))
            }
        }

        polygon(context, [(0, 237), (168, 306), (318, 280), (562, 425), (690, 325), (784, 348),
                          (899, 256), (1_079, 350), (1_272, 288), (1_469, 407), (1_600, 325),
                          (1_600, 0), (0, 0)], day ? 0xb07f68 : 0x4b3552)
        polygon(context, [(377, 316), (562, 425), (690, 325), (598, 353), (556, 338), (527, 365)],
                day ? 0xdcae84 : 0x86566a)
        polygon(context, [(1_311, 312), (1_469, 407), (1_600, 325), (1_515, 345),
                          (1_456, 332), (1_446, 355)], day ? 0xd9a77e : 0x805266)
        polygon(context, [(0, 210), (192, 254), (357, 178), (517, 227), (641, 196),
                          (895, 284), (1_066, 219), (1_169, 241), (1_335, 179), (1_600, 250),
                          (1_600, 0), (0, 0)], day ? 0x8e5134 : 0x2f2238)

        // A band of distant woodland softens the foot of the ridges.
        let crowns = day ? [0xc9682c, 0xdf9433, 0xa8421f, 0xe7b548, 0x8a4a24] : [0x4a2a2c, 0x5e3327, 0x3a2030, 0x6e3d26, 0x2c1c2c]
        for index in 0..<64 {
            let x = CGFloat(index * 26 + (index * 37) % 17) - 20
            let y = CGFloat(118 + (index * 53) % 34)
            let r = CGFloat(20 + (index * 29) % 16)
            context.setFillColor(color(crowns[(index * 7) % crowns.count], opacity: day ? 0.92 : 0.95))
            context.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.7))
        }

        let hill = CGMutablePath()
        hill.move(to: CGPoint(x: 0, y: 126))
        hill.addQuadCurve(to: CGPoint(x: 780, y: 83), control: CGPoint(x: 370, y: 32))
        hill.addQuadCurve(to: CGPoint(x: 1_600, y: 128), control: CGPoint(x: 1_223, y: 142))
        hill.addLines(between: [CGPoint(x: 1_600, y: 0), .zero])
        hill.closeSubpath()
        context.addPath(hill)
        context.setFillColor(color(day ? 0x6a3c1f : 0x1e1828))
        context.fillPath()

        for index in 0..<24 {
            let x = CGFloat(index * 47 + (index * 73) % 32) + (day ? 2 : 485)
            let y = CGFloat((index * 29) % 47 + 86)
            let height = CGFloat((index * 37) % 70 + 46)
            let crown = crowns[(index * 3 + 1) % crowns.count]
            maple(context, x: x, y: y, height: height, crown: crown,
                  lit: day ? 0xf5c865 : 0x8c4a2a, trunk: day ? 0x3f2616 : 0x15101c)
        }
        if day {
            barn(context)
        } else {
            cabin(context)
            for (x, y, r): (CGFloat, CGFloat, CGFloat) in [(382, 86, 9), (402, 82, 12), (250, 84, 8)] {
                context.setFillColor(color(0xd8742a))
                context.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6))
            }
        }
    }

    /// A round-crowned tree: a dark mass with a smaller lit cap toward the light.
    private func maple(_ context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat,
                       crown: Int, lit: Int, trunk: Int) {
        context.setFillColor(color(trunk))
        context.fill(CGRect(x: x - height * 0.035, y: y, width: height * 0.07, height: height * 0.5))
        for (dx, dy, r): (CGFloat, CGFloat, CGFloat) in [(0, 0.66, 0.30), (-0.2, 0.52, 0.22), (0.2, 0.54, 0.21)] {
            context.setFillColor(color(crown))
            context.fillEllipse(in: CGRect(x: x + (dx - r) * height, y: y + (dy - r) * height,
                                           width: r * 2 * height, height: r * 2 * height))
        }
        context.setFillColor(color(lit, opacity: 0.5))
        context.fillEllipse(in: CGRect(x: x - height * 0.02, y: y + height * 0.68,
                                       width: height * 0.26, height: height * 0.2))
    }

    private func barn(_ context: CGContext) {
        context.setFillColor(color(0x8e2f26))
        context.fill(CGRect(x: 262, y: 82, width: 104, height: 52))
        polygon(context, [(254, 132), (270, 160), (314, 176), (358, 160), (374, 132)], 0x6f241f)
        polygon(context, [(254, 132), (270, 160), (314, 176), (358, 160), (374, 132),
                          (366, 132), (354, 154), (314, 168), (274, 154), (262, 132)], 0x4a2a26)
        context.setFillColor(color(0xf1e2c6))
        context.fill(CGRect(x: 298, y: 82, width: 32, height: 34))
        context.setFillColor(color(0x8e2f26))
        context.fill(CGRect(x: 301, y: 82, width: 26, height: 31))
        context.setFillColor(color(0xf1e2c6))
        context.fill(CGRect(x: 313, y: 82, width: 2, height: 31))
        context.fill(CGRect(x: 304, y: 140, width: 20, height: 14))
        context.setFillColor(color(0x3a2420))
        context.fill(CGRect(x: 307, y: 143, width: 14, height: 8))
        // Round hay bales in the field.
        for (x, y, r): (CGFloat, CGFloat, CGFloat) in [(470, 70, 17), (540, 62, 14), (150, 76, 15)] {
            context.setFillColor(color(0x5a3219, opacity: 0.5))
            context.fillEllipse(in: CGRect(x: x - r * 1.3, y: y - r * 0.95, width: r * 2.6, height: r * 0.5))
            context.setFillColor(color(0xcf9c40))
            context.fillEllipse(in: CGRect(x: x - r * 1.2, y: y - r * 0.8, width: r * 2.4, height: r * 1.6))
            context.setFillColor(color(0xecc874))
            context.fillEllipse(in: CGRect(x: x - r * 1.0, y: y - r * 0.1, width: r * 1.7, height: r * 0.7))
        }
    }

    private func tree(_ context: CGContext, x: CGFloat, y: CGFloat, height: CGFloat, fill: Int) {
        for tier in 0..<3 {
            let base = y + CGFloat(tier) * height * 0.23
            let spread = height * (0.21 - CGFloat(tier) * 0.035)
            polygon(context, [(x - spread, base), (x + 1, base + height * 0.53), (x + spread, base)], fill)
        }
    }

    private func cabin(_ context: CGContext) {
        context.setFillColor(color(0x2a263d))
        context.fill(CGRect(x: 271, y: 82, width: 83, height: 44))
        polygon(context, [(257, 121), (309, 161), (368, 121)], 0x352a40)
        polygon(context, [(258, 122), (309, 164), (368, 122), (353, 122), (309, 151), (272, 122)], 0x97899a)
        context.setFillColor(color(0xe5a771))
        context.fill(CGRect(x: 282, y: 97, width: 12, height: 11))
        context.fill(CGRect(x: 329, y: 97, width: 12, height: 11))
    }

    private func polygon(_ context: CGContext, _ points: [(CGFloat, CGFloat)], _ fill: Int) {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(fill))
        context.fillPath()
    }

    private func color(_ rgb: Int, opacity: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: opacity)
    }
}
