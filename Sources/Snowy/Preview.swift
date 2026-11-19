import AppKit
import ImageIO
import SnowCore
import UniformTypeIdentifiers

/// Development tool. `swift run Snowy --preview out.png [--season fall] [--at 8,30,75] [--tool blower]
/// [--stroke 29.5] [--age 0.6] [--scale 2]` runs the real simulation and renderer over a mock
/// desktop and writes the requested moments as one stacked image, so a visual change can be
/// checked without covering the actual desktop.
@MainActor
enum Preview {
    private static let size = CGSize(width: 960, height: 600)
    private static let windows: [CGRect] = [
        CGRect(x: 90, y: 210, width: 430, height: 300),
        CGRect(x: 560, y: 330, width: 310, height: 200),
        CGRect(x: 640, y: 120, width: 170, height: 110)
    ]

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let path = value("--preview") else { return false }
        let times = (value("--at") ?? "8,30,75").split(separator: ",").compactMap { Float($0) }.sorted()
        let stroke = value("--stroke").flatMap { Float($0) }
        let scale = CGFloat(value("--scale").flatMap { Double($0) } ?? 2)
        do {
            let renderer = try MetalRenderer(context: MetalContext(), size: size, menuInset: 24,
                                             budget: SimulationBudget(flakes: 900, debris: 192, cells: 4096),
                                             seed: 7)
            let simulation = renderer.simulation
            simulation.season = Season(rawValue: (value("--season") ?? "Fall").capitalized) ?? .fall
            simulation.leafAge = value("--age").flatMap { Float($0) } ?? 0.6
            simulation.snowfall = Snowfall(rawValue: (value("--fall") ?? "Steady").capitalized) ?? .steady
            simulation.tool = SnowTool(rawValue: (value("--tool") ?? "Glove").capitalized) ?? .glove
            var surfaces = [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: Float(size.height),
                                    width: Float(size.width))]
            var bodies: [SolidBody] = []
            for (index, window) in windows.enumerated() {
                let id = UInt64(index + 1)
                surfaces.append(Surface(id: id, x: Float(window.minX), y: Float(window.minY),
                                        width: Float(window.width), cornerRadius: 10))
                bodies.append(SolidBody(id: id, bounds: window, cornerRadius: 10))
            }
            simulation.updateScene(surfaces: surfaces, bodies: bodies)

            var frames: [CGImage] = []
            var clock: Float = 0
            let dt: Float = 1 / 30
            for moment in times {
                while clock < moment {
                    var cursor: SIMD2<Float>?
                    // One pointer pass, left to right, just above the big window's pile.
                    if let stroke, clock >= stroke, clock < stroke + 0.6 {
                        cursor = SIMD2(70 + (clock - stroke) / 0.6 * 470, 196)
                    }
                    simulation.step(dt: dt, cursor: cursor)
                    clock += dt
                }
                if let overlay = renderer.snapshot(scale: scale), let frame = compose(overlay, scale: scale) {
                    frames.append(frame)
                }
            }
            guard !frames.isEmpty, let sheet = stack(frames) else { throw RendererError.allocationFailed }
            let url = URL(fileURLWithPath: path)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                    1, nil) else { throw RendererError.allocationFailed }
            CGImageDestinationAddImage(destination, sheet, nil)
            guard CGImageDestinationFinalize(destination) else { throw RendererError.allocationFailed }
            print("\(frames.count) frame(s) -> \(path); leaves in air \(simulation.leaves.count)+\(simulation.blownLeaves.count), resting \(simulation.pileLeaves.count)")
        } catch {
            FileHandle.standardError.write(Data("Preview failed: \(error)\n".utf8))
            exit(1)
        }
        return true
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Wallpaper, then the overlay, then the windows: the overlay sits on the desktop plane.
    private static func compose(_ overlay: CGImage, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = bitmap(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let colors = [CGColor(red: 0.33, green: 0.47, blue: 0.62, alpha: 1),
                      CGColor(red: 0.86, green: 0.80, blue: 0.70, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0),
                                       options: [])
        }
        context.draw(overlay, in: full)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        for (index, window) in windows.enumerated() {
            let shape = CGPath(roundedRect: window, cornerWidth: 10, cornerHeight: 10, transform: nil)
            context.addPath(shape)
            context.setFillColor(index == 1 ? CGColor(gray: 0.16, alpha: 1) : CGColor(gray: 0.95, alpha: 1))
            context.fillPath()
            context.addPath(shape)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.25))
            context.setLineWidth(0.5)
            context.strokePath()
        }
        return context.makeImage()
    }

    private static func stack(_ frames: [CGImage]) -> CGImage? {
        let gap = 8
        let width = frames[0].width
        let height = frames.reduce(0) { $0 + $1.height } + gap * (frames.count - 1)
        guard let context = bitmap(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height
        for frame in frames {
            top -= frame.height
            context.draw(frame, in: CGRect(x: 0, y: top, width: frame.width, height: frame.height))
            top -= gap
        }
        return context.makeImage()
    }
}
