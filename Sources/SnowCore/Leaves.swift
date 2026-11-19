import Foundation

/// One airborne leaf. `body` reuses the snow particle's continuous contact handling.
public struct LeafParticle: Sendable {
    public var body: SnowParticle
    public var size: Float
    public var angle: Float
    /// Shape index in the integer part, colour position in the fraction.
    public var look: Float
    public var shade: Float
    var spin: Float
    var flipPhase: Float
    var flipRate: Float
    var swayRate: Float
    var sway: Float
    var fall: Float
    /// A decaying shove from the blower, added to an ambient leaf's scripted flutter.
    var push: SIMD2<Float> = .zero
}

/// GPU layout matches Metal: 32 bytes per leaf, resting or airborne.
public struct LeafInstance: Sendable {
    public var position: SIMD2<Float>
    public var size: Float
    public var angle: Float
    public var look: Float
    public var opacity: Float
    public var shade: Float
    /// Sideways foreshortening, -1...1, so a tumbling leaf appears to turn over.
    public var flip: Float

    public init(position: SIMD2<Float>, size: Float, angle: Float, look: Float, opacity: Float,
                shade: Float, flip: Float) {
        self.position = position
        self.size = size
        self.angle = angle
        self.look = look
        self.opacity = opacity
        self.shade = shade
        self.flip = flip
    }

    public init(_ leaf: LeafParticle) {
        position = leaf.body.position
        size = leaf.size
        angle = leaf.angle + 0.5 * sin(leaf.body.phase)
        look = leaf.look
        opacity = leaf.body.opacity * min(1, leaf.body.remainingLife * 2)
        shade = leaf.shade
        let turn = cos(leaf.flipPhase)
        flip = (turn < 0 ? -1 : 1) * (0.3 + 0.7 * abs(turn))
    }
}

/// The resting pile is drawn as rows of leaves stacked from the support upward.
enum LeafPile {
    /// Horizontal distance between resting leaves, in points.
    static let step: Float = 5
    /// Height each resting row adds.
    static let rise: Float = 3.6
    /// Pile area one leaf stands for; lifting a leaf removes this much, landing returns it.
    static let area: Float = step * rise

    static func hash(_ id: UInt64, _ slot: Int, _ row: Int) -> UInt64 {
        var h = id &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(truncatingIfNeeded: slot) &* 0xBF58_476D_1CE4_E5B9
        h ^= UInt64(truncatingIfNeeded: row) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        h = h &* 0xD6E8_FEB8_6659_FD93
        h ^= h >> 32
        return h
    }

    /// Eight independent 0...1 values from one hash.
    static func unit(_ hash: UInt64, _ index: Int) -> Float {
        Float((hash >> UInt64(index * 8)) & 0xFF) / 255
    }

    /// Early autumn leans yellow and green, late autumn red and brown.
    static func look(shape: Float, colour: Float, age: Float) -> Float {
        let kind: Float = shape < 0.45 ? 0 : (shape < 0.75 ? 1 : 2)
        let mean = 0.85 - 0.65 * max(0, min(1, age))
        return kind + max(0.02, min(0.98, mean + (colour - 0.5) * 0.75)) * 0.99
    }
}

enum LeafFlight {
    static let gravity: Float = 150
    static let drag: Float = 2
}
