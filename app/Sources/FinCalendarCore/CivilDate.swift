/// Календарная дата без времени и часового пояса.
/// Детерминированная арифметика на номере дня — никакой Foundation-магии с зонами.
public struct CivilDate: Hashable, Comparable, Codable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Дней с 1970-01-01 (алгоритм Хиннанта, валиден для проленптического григорианского календаря).
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public init(dayNumber z0: Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(m <= 2 ? y + 1 : y, m, d)
    }

    /// ISO: 1 = понедельник … 7 = воскресенье.
    public var weekday: Int { ((dayNumber % 7) + 7 + 3) % 7 + 1 }

    public var isWeekend: Bool { weekday >= 6 }

    public static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        }
    }

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool { lhs.dayNumber < rhs.dayNumber }

    public func adding(days: Int) -> CivilDate { CivilDate(dayNumber: dayNumber + days) }

    public var description: String {
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }
}
