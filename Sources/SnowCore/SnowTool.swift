public enum SnowTool: String, CaseIterable, Sendable {
    case glove = "Glove"
    case shovel = "Shovel"
    /// Fall only: lifts settled leaves into the air from a distance.
    case blower = "Blower"

    public var radius: Float {
        switch self {
        case .glove: 24
        case .shovel: 36
        case .blower: 72
        }
    }
}
