import Foundation

/// What falls on the desktop. Winter is the original snow; fall swaps in leaves on the same
/// supports, heights, and window handling.
public enum Season: String, CaseIterable, Sendable {
    case winter = "Winter"
    case fall = "Fall"

    private static let daysBeforeMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
    private static let equinox = 265   // 22 September
    private static let solstice = 355  // 21 December

    static func dayOfYear(month: Int, day: Int) -> Int {
        daysBeforeMonth[max(1, min(12, month)) - 1] + max(1, min(31, day))
    }

    /// The season the calendar picks: leaves from the September equinox up to the December
    /// solstice, snow for the rest of the year.
    public static func current(month: Int, day: Int) -> Season {
        let today = dayOfYear(month: month, day: day)
        return today >= equinox && today < solstice ? .fall : .winter
    }

    /// 0 on the first day of autumn, 1 on the last. Outside autumn it reports mid-season, so a
    /// hand-picked Fall still gets a full spread of colour.
    public static func fallProgress(month: Int, day: Int) -> Float {
        let today = dayOfYear(month: month, day: day)
        guard today >= equinox, today <= solstice else { return 0.5 }
        return Float(today - equinox) / Float(solstice - equinox)
    }
}
