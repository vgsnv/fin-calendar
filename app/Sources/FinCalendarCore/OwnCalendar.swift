/// Свой календарь: сетка спринтов по опорным датам (СВ1–СВ5).
/// Правила: canon/calendar — К1–К3, СВ2. Эталон: tests/own-calendar-2027.md.

/// Правило переноса опорной даты, попавшей на нерабочий день (СВ2, шаг 2).
public enum TransferRule: String, Codable, Sendable {
    case lastWorkingDayBefore   // умолчание
    case firstWorkingDayAfter
    case none
}

/// Опорная дата: номинальный день месяца 1–28 (СВ1) и правило переноса.
public struct Anchor: Codable, Sendable {
    public let day: Int
    public let rule: TransferRule
    public let name: String

    public init(day: Int, rule: TransferRule = .lastWorkingDayBefore, name: String = "") {
        precondition((1...28).contains(day), "СВ1: опорная дата — от 1-го до 28-го")
        self.day = day
        self.rule = rule
        self.name = name
    }
}

/// Производственный календарь (СВ5): дополнительные нерабочие дни и рабочие выходные.
/// Пустой справочник — «чистый» режим: нерабочие только суббота и воскресенье.
public struct ProductionCalendar: Codable, Sendable {
    public var holidays: Set<CivilDate>
    public var workingWeekends: Set<CivilDate>

    public static let none = ProductionCalendar(holidays: [], workingWeekends: [])

    public init(holidays: Set<CivilDate>, workingWeekends: Set<CivilDate>) {
        self.holidays = holidays
        self.workingWeekends = workingWeekends
    }

    public func isWorkingDay(_ d: CivilDate) -> Bool {
        if workingWeekends.contains(d) { return true }
        if d.isWeekend { return false }
        return !holidays.contains(d)
    }
}

/// Спринт: старт (граница финнедели), длина в финнеделях, приходы на границе.
public struct Sprint: Equatable, Sendable {
    public let start: CivilDate
    public let weeks: Int
    /// Опорные даты (номинальные дни месяца), породившие этот старт; совпавшие сложены (СВ2, шаг 3).
    public let anchorDays: [Int]
    /// Фактические даты приходов после переноса.
    public let factDates: [CivilDate]
    /// Длиннее обычной длины своей опорной даты (СВ4). Определено при 1–2 опорных датах.
    public var isLong: Bool = false

    public var end: CivilDate { start.adding(days: weeks * 7 - 1) }
}

public struct OwnCalendar: Sendable {
    /// Граница финнедели: день недели ISO (1 пн … 7 вс). Рекомендация — суббота (6).
    public let weekBoundary: Int
    public let anchors: [Anchor]
    public let production: ProductionCalendar

    public init(weekBoundary: Int, anchors: [Anchor], production: ProductionCalendar = .none) {
        precondition((1...7).contains(weekBoundary))
        precondition(!anchors.isEmpty)
        self.weekBoundary = weekBoundary
        self.anchors = anchors
        self.production = production
    }

    /// Фактическая дата опорной даты после правила переноса (СВ2, шаг 2).
    public func factDate(nominal: CivilDate, rule: TransferRule) -> CivilDate {
        guard rule != .none, !production.isWorkingDay(nominal) else { return nominal }
        var d = nominal
        switch rule {
        case .lastWorkingDayBefore:
            while !production.isWorkingDay(d) { d = d.adding(days: -1) }
        case .firstWorkingDayAfter:
            while !production.isWorkingDay(d) { d = d.adding(days: 1) }
        case .none:
            break
        }
        return d
    }

    /// Сдвиг вперёд до ближайшей границы финнедели, включая сам день (К2).
    public func sprintStart(for fact: CivilDate) -> CivilDate {
        var d = fact
        while d.weekday != weekBoundary { d = d.adding(days: 1) }
        return d
    }

    /// Сетка спринтов на горизонте (СВ2). Последняя граница горизонта закрывает
    /// предпоследний спринт; спринт от последней границы не возвращается — его длина неизвестна.
    public func sprints(fromYear: Int, fromMonth: Int, toYear: Int, toMonth: Int) -> [Sprint] {
        struct Origin { let anchorDay: Int; let fact: CivilDate }
        var byStart: [CivilDate: [Origin]] = [:]

        var y = fromYear, m = fromMonth
        while (y, m) <= (toYear, toMonth) {
            for anchor in anchors {
                let nominal = CivilDate(y, m, anchor.day)
                let fact = factDate(nominal: nominal, rule: anchor.rule)
                let start = sprintStart(for: fact)
                byStart[start, default: []].append(Origin(anchorDay: anchor.day, fact: fact))
            }
            m += 1
            if m > 12 { m = 1; y += 1 }
        }

        let starts = byStart.keys.sorted()
        var result: [Sprint] = []
        for (i, start) in starts.enumerated() where i + 1 < starts.count {
            let next = starts[i + 1]
            let days = next.dayNumber - start.dayNumber
            assert(days % 7 == 0, "К3: длина спринта — целое число финнедель")
            let origins = byStart[start]!
            result.append(Sprint(
                start: start,
                weeks: days / 7,
                anchorDays: origins.map(\.anchorDay),
                factDates: origins.map(\.fact)
            ))
        }
        return markLong(result)
    }

    /// СВ4: длинный — спринт длиннее обычной длины своей опорной даты.
    /// Обычная длина — мода длин спринтов этой даты; осмысленно при 1–2 датах.
    private func markLong(_ sprints: [Sprint]) -> [Sprint] {
        guard anchors.count <= 2 else { return sprints }
        var lengthsByAnchor: [Int: [Int]] = [:]
        for s in sprints {
            guard let a = s.anchorDays.first else { continue }
            lengthsByAnchor[a, default: []].append(s.weeks)
        }
        var normal: [Int: Int] = [:]
        for (a, lens) in lengthsByAnchor {
            var freq: [Int: Int] = [:]
            for l in lens { freq[l, default: 0] += 1 }
            normal[a] = freq.max { ($0.value, -$0.key) < ($1.value, -$1.key) }!.key
        }
        return sprints.map { s in
            var s = s
            if let a = s.anchorDays.first, let n = normal[a] { s.isLong = s.weeks > n }
            return s
        }
    }
}

private func <= (lhs: (Int, Int), rhs: (Int, Int)) -> Bool {
    lhs.0 < rhs.0 || (lhs.0 == rhs.0 && lhs.1 <= rhs.1)
}
