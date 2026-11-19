import Foundation

public enum Snowfall: String, CaseIterable, Sendable {
    case light = "Light"
    case steady = "Steady"
    case flurry = "Flurry"

    public var density: Float {
        switch self {
        case .light: 0.55
        case .steady: 1
        case .flurry: 1.65
        }
    }
}

public struct RenderPolicy: Equatable, Sendable {
    public var framesPerSecond: Int
    public var particleScale: Float
    public var renderScale: Float
    public var reducedMotion: Bool
    public var suspended: Bool

    /// A pure policy, so system-state handling can be verified without exercising a GPU.
    public init(lowPower: Bool, thermalLevel: Int, reducedMotion: Bool) {
        self.reducedMotion = reducedMotion
        suspended = thermalLevel >= 3
        framesPerSecond = thermalLevel >= 2 ? 15 : (lowPower ? 20 : 30)
        particleScale = thermalLevel >= 2 ? 0.35 : (lowPower ? 0.55 : 1)
        renderScale = lowPower || thermalLevel >= 2 ? 1 : 1.5
        if reducedMotion {
            framesPerSecond = 15
            particleScale = 0
            renderScale = 1
        }
    }
}

public struct SimulationBudget: Sendable {
    public let flakes: Int
    public let debris: Int
    public let cells: Int
    public let surfaces: Int
    /// Reuse the previous transport allocation as a bounded granular pool, without particle blobs.
    public var maximumGranules: Int { min(cells * 8, debris * 128) }
    public var maximumSnowVertices: Int { (cells + maximumGranules) * 12 }
    /// Leaves are larger than flakes, so far fewer of them fill the same sky.
    public var fallingLeaves: Int { flakes / 6 }
    /// Leaves lifted off a pile by the blower, a sweep, a moving window, or a gust.
    public var blownLeaves: Int { cells / 8 }
    /// Resting leaves drawn on the piles; the pile coarsens rather than exceed this.
    public var pileLeaves: Int { cells }
    public var maximumAirborneLeaves: Int { fallingLeaves + blownLeaves }

    public init(flakes: Int = 350, debris: Int = 96, cells: Int = 4096, surfaces: Int = 48) {
        self.flakes = max(0, min(900, flakes))
        self.debris = max(0, min(192, debris))
        self.cells = max(0, min(4096, cells))
        self.surfaces = max(0, min(48, surfaces))
    }
}
