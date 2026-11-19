import Foundation
import SnowCore

extension Season {
    /// The season on the desktop right now: the Season menu's pick, or the calendar's.
    static var active: Season {
        if let pick = Season(rawValue: UserDefaults.standard.string(forKey: "season") ?? "") { return pick }
        let today = Calendar.current.dateComponents([.month, .day], from: Date())
        return Season.current(month: today.month ?? 1, day: today.day ?? 1)
    }

    var other: Season { self == .fall ? .winter : .fall }
    var collectionTitle: String { self == .fall ? "Autumn" : "Winter" }
}
