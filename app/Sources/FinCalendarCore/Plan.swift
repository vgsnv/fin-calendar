/// План и живой пересчёт (П11–П12): статьи, подтверждённые раскладки,
/// генерация потребностей и пересчёт неразложенного будущего.
///
/// Граница пересчёта — факт раскладки (П12): подтверждённое не входит во вход
/// пересчёта и застыло по построению; собранные взносы уменьшают остатки статей.

public enum ArticleKind: Equatable, Sendable {
    /// Платёж с датой (С2–С4). `monthlyDay` непустой — ежемесячный (даты 1–28, С3);
    /// `prepared` — готовиться заранее / без подготовки (С3).
    case payment(amount: Double, date: CivilDate, monthlyDay: Int?, prepared: Bool)
    /// Замысел (С5–С6): сумма и скорость в месяц.
    case intent(target: Double, monthlySpeed: Double)
    /// Фонд (С7–С8): только скорость в месяц.
    case fund(monthlySpeed: Double)
    /// Еженедельные деньги (С9): полная порция на каждую финнеделю, без конца.
    /// Не гнутся и паузы не имеют (П9); статей вида может быть несколько.
    case weekly(portion: Double)
}

extension ArticleKind: Codable {}

extension Article {
    /// Еженедельная статья (С9).
    public var isWeekly: Bool {
        if case .weekly = kind { return true }
        return false
    }
}

public struct Article: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public var kind: ArticleKind
    /// Пауза (П8): скорость временно ноль, статья остаётся в плане.
    public var paused: Bool

    public init(id: String, name: String, kind: ArticleKind, paused: Bool = false) {
        if case .payment(_, _, let day?, _) = kind {
            precondition((1...28).contains(day), "С3: номинальная дата ежемесячного платежа — 1–28")
        }
        self.id = id
        self.name = name
        self.kind = kind
        self.paused = paused
    }
}

public struct PlannedIncome: Codable, Sendable {
    public let anchor: Anchor
    public let plannedAmount: Double

    public init(anchor: Anchor, plannedAmount: Double) {
        self.anchor = anchor
        self.plannedAmount = plannedAmount
    }
}

/// Порция финнедели в застывшей раскладке.
public struct WeekAllotment: Equatable, Codable, Sendable {
    public let start: CivilDate
    public let amount: Double

    public init(start: CivilDate, amount: Double) {
        self.start = start
        self.amount = amount
    }
}

/// Подтверждённая раскладка — застывший факт (П5, П12).
public struct ConfirmedLayout: Codable, Sendable {
    /// Идентификатор прихода: "\(anchorDay)@\(factDate)".
    public let incomeId: String
    public var incomeName: String
    public var factDate: CivilDate?
    public let factAmount: Double
    public var sprintStart: CivilDate?
    public var sprintWeeks: Int?
    public var isLong: Bool
    public let weekAmounts: [WeekAllotment]
    public let contributions: [Contribution]
    /// Отметки исполнения чек-листа — память человека, не учёт фактов (С12, П3):
    /// на план не влияют никогда.
    public var executed: Set<String>

    public init(incomeId: String, incomeName: String = "", factDate: CivilDate? = nil,
                factAmount: Double, sprintStart: CivilDate? = nil, sprintWeeks: Int? = nil,
                isLong: Bool = false, weekAmounts: [WeekAllotment],
                contributions: [Contribution], executed: Set<String> = []) {
        self.incomeId = incomeId
        self.incomeName = incomeName
        self.factDate = factDate
        self.factAmount = factAmount
        self.sprintStart = sprintStart
        self.sprintWeeks = sprintWeeks
        self.isLong = isLong
        self.weekAmounts = weekAmounts
        self.contributions = contributions
        self.executed = executed
    }

    /// Пропущенная раскладка (С15а): восстановления задним числом нет — фиксируются
    /// только фактически отложенные взносы; выдач (недель) у неё не бывает.
    public static func missed(incomeId: String, keptContributions: [Contribution]) -> ConfirmedLayout {
        ConfirmedLayout(incomeId: incomeId,
                        factAmount: keptContributions.reduce(0) { $0 + $1.amount },
                        weekAmounts: [], contributions: keptContributions)
    }

    /// Подтверждение раскладки (П12, МП30): порции финнедель спринта и взносы
    /// прихода застывают. У длинного спринта замораживается и лишняя финнеделя:
    /// она оплачена сбором (С9), её порция — цель сбора на момент подтверждения;
    /// правка еженедельных дальше действует на будущее, текущий спринт доживает
    /// на прежних порциях (МП36).
    public static func frozen(occurrence: IncomeOccurrence, factAmount: Double,
                              incomeName: String, recommendation: Recommendation,
                              weeklySum: Double) -> ConfirmedLayout {
        let starts = (0..<occurrence.sprintWeeks).map { occurrence.sprintStart.adding(days: $0 * 7) }
        var weeks = recommendation.weeks
            .filter { starts.contains($0.start) }
            .map { WeekAllotment(start: $0.start, amount: $0.amount) }
        if occurrence.isLongSprint {
            let extraStart = occurrence.sprintStart.adding(days: (occurrence.sprintWeeks - 1) * 7)
            weeks.append(WeekAllotment(start: extraStart, amount: weeklySum))
        }
        return ConfirmedLayout(incomeId: occurrence.id,
                               incomeName: incomeName,
                               factDate: occurrence.factDate,
                               factAmount: factAmount,
                               sprintStart: occurrence.sprintStart,
                               sprintWeeks: occurrence.sprintWeeks,
                               isLong: occurrence.isLongSprint,
                               weekAmounts: weeks,
                               contributions: recommendation.contributions.filter {
                                   $0.incomeId == occurrence.id
                               })
    }
}

public struct Plan: Codable, Sendable {
    public var weekBoundary: Int
    public var incomes: [PlannedIncome]
    public var production: ProductionCalendar
    public var entryDate: CivilDate
    public var articles: [Article]
    public var confirmed: [ConfirmedLayout]
    /// Отметки выдач (С16): старт финнедели → порция выдана. Память, не факты (П3).
    public var issuedWeeks: Set<CivilDate>
    /// Переключатели двух уведомлений (МП33), каждое отдельно.
    public var notifyLayout: Bool
    public var notifyIssue: Bool

    public init(weekBoundary: Int, incomes: [PlannedIncome],
                production: ProductionCalendar = .none, entryDate: CivilDate,
                articles: [Article] = [], confirmed: [ConfirmedLayout] = [],
                issuedWeeks: Set<CivilDate> = [], notifyLayout: Bool = true,
                notifyIssue: Bool = true) {
        self.weekBoundary = weekBoundary
        self.incomes = incomes
        self.production = production
        self.entryDate = entryDate
        self.articles = articles
        self.confirmed = confirmed
        self.issuedWeeks = issuedWeeks
        self.notifyLayout = notifyLayout
        self.notifyIssue = notifyIssue
    }

    private enum CodingKeys: String, CodingKey {
        case namedWeek   // наследие: неделя-константа до еженедельных статей (С9)
        case weekBoundary, incomes, production, entryDate, articles, confirmed
        case issuedWeeks, notifyLayout, notifyIssue
    }

    // Новые поля читаются с умолчаниями — старые файлы хранилища остаются валидными.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekBoundary = try c.decode(Int.self, forKey: .weekBoundary)
        incomes = try c.decode([PlannedIncome].self, forKey: .incomes)
        production = try c.decode(ProductionCalendar.self, forKey: .production)
        entryDate = try c.decode(CivilDate.self, forKey: .entryDate)
        articles = try c.decode([Article].self, forKey: .articles)
        confirmed = try c.decode([ConfirmedLayout].self, forKey: .confirmed)
        issuedWeeks = try c.decodeIfPresent(Set<CivilDate>.self, forKey: .issuedWeeks) ?? []
        notifyLayout = try c.decodeIfPresent(Bool.self, forKey: .notifyLayout) ?? true
        notifyIssue = try c.decodeIfPresent(Bool.self, forKey: .notifyIssue) ?? true
        // Неделя-константа старого хранилища становится первой еженедельной
        // статьёй (С9): порция — данные плана, не конфигурация.
        let legacyWeek = try c.decodeIfPresent(Double.self, forKey: .namedWeek) ?? 0
        if legacyWeek > 1e-9, !articles.contains(where: \.isWeekly) {
            articles.append(Article(id: "неделя", name: "Неделя",
                                    kind: .weekly(portion: legacyWeek)))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekBoundary, forKey: .weekBoundary)
        try c.encode(incomes, forKey: .incomes)
        try c.encode(production, forKey: .production)
        try c.encode(entryDate, forKey: .entryDate)
        try c.encode(articles, forKey: .articles)
        try c.encode(confirmed, forKey: .confirmed)
        try c.encode(issuedWeeks, forKey: .issuedWeeks)
        try c.encode(notifyLayout, forKey: .notifyLayout)
        try c.encode(notifyIssue, forKey: .notifyIssue)
    }

    /// Деньги одной финнедели — сумма порций активных еженедельных статей (С9, П1).
    public var weeklySum: Double {
        articles.reduce(0) {
            if case .weekly(let portion) = $1.kind, !$1.paused { return $0 + portion }
            return $0
        }
    }

    /// Собрано по статье из подтверждённых раскладок (взносы не возвращаются, П12, С4а).
    public func collected(articleId: String) -> Double {
        confirmed.flatMap(\.contributions)
            .filter { $0.articleId == articleId }
            .reduce(0) { $0 + $1.amount }
    }

    /// Статья потребности: id потребности — «статья» либо «статья@суффикс».
    public static func articleId(of needId: String) -> String {
        needId.split(separator: "@").first.map(String.init) ?? needId
    }
}

extension Contribution {
    /// Статья взноса: потребности статьи различаются суффиксом за «@» — помесячный
    /// срок (С3), приход замысла или фонда (С5, С7), доля окна лишней финнедели (С10).
    /// Балансировка вправе раздать их по приходам врозь (LIFO, П6б), но статья
    /// у прихода одна: строки раскладки складываются по этому ключу.
    public var articleId: String { Plan.articleId(of: needId) }
}

/// Приход горизонта.
public struct IncomeOccurrence: Sendable {
    public let id: String
    public let anchorDay: Int
    public let factDate: CivilDate
    public let sprintStart: CivilDate
    public let sprintWeeks: Int
    public let plannedAmount: Double
    public let isLongSprint: Bool

    public init(id: String, anchorDay: Int, factDate: CivilDate, sprintStart: CivilDate,
                sprintWeeks: Int, plannedAmount: Double, isLongSprint: Bool) {
        self.id = id
        self.anchorDay = anchorDay
        self.factDate = factDate
        self.sprintStart = sprintStart
        self.sprintWeeks = sprintWeeks
        self.plannedAmount = plannedAmount
        self.isLongSprint = isLongSprint
    }
}

public struct HorizonRecommendation: Sendable {
    public var recommendation: Recommendation
    public var occurrences: [IncomeOccurrence]
    /// Расчётные финиши замыслов (С5): id статьи → дата прихода, на котором соберётся.
    public var intentFinish: [String: CivilDate]
}

public enum PlanEngine {

    /// Живой пересчёт (П11): рекомендация на неразложенное будущее.
    /// Подтверждённые приходы исключены из входа — их цифры застыли (П12).
    /// `factOverrides` — фактические суммы приходов, названные в черновике раскладки
    /// (МП27): план они не меняют, черновик пересчитывают.
    public static func recompute(_ plan: Plan, today: CivilDate,
                                 horizonMonths: Int = 12,
                                 factOverrides: [String: Double] = [:]) -> HorizonRecommendation {
        guard !plan.incomes.isEmpty else {
            return HorizonRecommendation(
                recommendation: Recommendation(weeks: [], contributions: [], freeMoney: [:], shortfalls: []),
                occurrences: [], intentFinish: [:])
        }
        let calendar = OwnCalendar(weekBoundary: plan.weekBoundary,
                                   anchors: plan.incomes.map(\.anchor),
                                   production: plan.production)
        let fromM = today.month == 1 ? (today.year - 1, 12) : (today.year, today.month - 1)
        var toY = today.year, toM = today.month + horizonMonths + 1
        while toM > 12 { toM -= 12; toY += 1 }
        let grid = calendar.sprints(fromYear: fromM.0, fromMonth: fromM.1, toYear: toY, toMonth: toM)

        let amountByDay = Dictionary(uniqueKeysWithValues: plan.incomes.map { ($0.anchor.day, $0.plannedAmount) })
        let confirmedIds = Set(plan.confirmed.map(\.incomeId))

        var occurrences: [IncomeOccurrence] = []
        // Номинальный месяц опорной даты (СВ1) — группа ровности свободных денег (П6б):
        // перенос может увести факт в соседний месяц, месяц самого прихода не меняя.
        var nominalById: [String: CivilDate] = [:]
        for s in grid where s.end >= plan.entryDate {
            for (i, day) in s.anchorDays.enumerated() {
                let fact = s.factDates[i]
                let id = "\(day)@\(fact)"
                guard !confirmedIds.contains(id), s.end >= today else { continue }
                nominalById[id] = s.nominalDates[i]
                occurrences.append(IncomeOccurrence(id: id, anchorDay: day, factDate: fact,
                                                    sprintStart: s.start, sprintWeeks: s.weeks,
                                                    plannedAmount: factOverrides[id] ?? amountByDay[day] ?? 0,
                                                    isLongSprint: s.isLong))
            }
        }
        occurrences.sort { $0.factDate < $1.factDate }
        guard !occurrences.isEmpty else {
            return HorizonRecommendation(
                recommendation: Recommendation(weeks: [], contributions: [], freeMoney: [:], shortfalls: []),
                occurrences: [], intentFinish: [:])
        }
        let horizonEnd = occurrences.map { $0.sprintStart.adding(days: $0.sprintWeeks * 7) }.max()!

        // Платежи «без подготовки» уменьшают приход своего спринта до балансировки (С3).
        // Если остатка не хватает на полные порции финнедель — недостача (П9).
        var balancingIncomes: [BalancingIncome] = []
        var extraContribs: [Contribution] = []
        for occ in occurrences {
            var amount = occ.plannedAmount
            for a in plan.articles where !a.paused {
                guard case .payment(let p, let date, nil, false) = a.kind,
                      occ.sprintStart <= date,
                      date < occ.sprintStart.adding(days: occ.sprintWeeks * 7),
                      plan.collected(articleId: a.id) == 0 else { continue }
                let take = min(amount, p)
                amount -= take
                extraContribs.append(Contribution(needId: a.id, incomeId: occ.id, amount: take))
            }
            balancingIncomes.append(BalancingIncome(id: occ.id, factDate: occ.factDate, amount: amount,
                                                   nominalDate: nominalById[occ.id]))
        }

        // Порции еженедельных статей — потребности финнедель своих спринтов (С9,
        // С12): такие же взносы, а не остаток. Лишняя финнеделя длинного спринта
        // порций здесь не имеет: их собирает заранее системная статья (С9, С10).
        var needs: [Need] = []
        let weeklies = plan.articles.filter { !$0.paused && $0.isWeekly }
        var seenSprints = Set<CivilDate>()
        for occ in occurrences where seenSprints.insert(occ.sprintStart).inserted {
            let paidWeeks = occ.sprintWeeks - (occ.isLongSprint ? 1 : 0)
            for w in 0..<paidWeeks {
                let weekStart = occ.sprintStart.adding(days: w * 7)
                for a in weeklies {
                    guard case .weekly(let portion) = a.kind, portion > 1e-9 else { continue }
                    needs.append(Need(id: "\(a.id)@\(weekStart)", name: a.name,
                                      kind: .weeklyPortion, due: weekStart, amount: portion))
                }
            }
        }

        var intentFinish: [String: CivilDate] = [:]
        let perMonth = Double(plan.incomes.count)

        for a in plan.articles where !a.paused {
            switch a.kind {
            case .payment(let amount, let date, nil, true):
                // Разовый платёж с подготовкой: живёт до раскладки своего спринта (С4).
                let remaining = amount - plan.collected(articleId: a.id)
                if remaining > 1e-9, date >= today {
                    needs.append(Need(id: a.id, name: a.name, kind: .payment, due: date, amount: remaining))
                }
            case .payment(let amount, let date, let day?, true):
                // Ежемесячный: возрождается каждый месяц с той же суммой и датой (С3).
                var d = CivilDate(date.year, date.month, day)
                while d < horizonEnd {
                    if d >= today {
                        let id = "\(a.id)@\(d)"
                        let remaining = amount - plan.confirmed.flatMap(\.contributions)
                            .filter { $0.needId == id }.reduce(0) { $0 + $1.amount }
                        if remaining > 1e-9 {
                            needs.append(Need(id: id, name: a.name, kind: .payment, due: d, amount: remaining))
                        }
                    }
                    let (ny, nm) = d.month == 12 ? (d.year + 1, 1) : (d.year, d.month + 1)
                    d = CivilDate(ny, nm, day)
                }
            case .payment:
                break // «без подготовки» обработан выше
            case .intent(let target, let speed):
                var remaining = target - plan.collected(articleId: a.id)
                let per = speed / perMonth
                for occ in occurrences where remaining > 1e-9 {
                    let take = min(per, remaining)
                    needs.append(Need(id: "\(a.id)@\(occ.factDate)", name: a.name,
                                      kind: .intentSpeed, due: occ.factDate, amount: take))
                    remaining -= take
                    if remaining <= 1e-9 { intentFinish[a.id] = occ.factDate } // финиш (С6)
                }
            case .fund(let speed):
                // Фонд постоянно занижает свободные деньги на свою скорость (С7).
                for occ in occurrences {
                    needs.append(Need(id: "\(a.id)@\(occ.factDate)", name: a.name,
                                      kind: .fundSpeed, due: occ.factDate, amount: speed / perMonth))
                }
            case .weekly:
                break // порции — потребности финнедель, собраны выше (С9)
            }
        }

        // Дополнительная финнеделя (С9–С10): системная статья с порцией недельных
        // на каждую лишнюю финнеделю длинного спринта. Собирается заранее, взносами
        // по приходам окна сбора — от предыдущего длинного спринта (или входа) до
        // старта самой лишней финнедели. Приходы длинного спринта в окно не входят:
        // лишняя неделя оплачена собранным, а не приходом своего же спринта — в этом
        // смысл С9. Взнос — со сроком в дату своего прихода: так поздние приходы
        // потребность не кормят по построению (П7), а недостача заявляется датой того
        // прихода, на котором деньги кончились (П9).
        let longStarts = occurrences.filter(\.isLongSprint).map(\.sprintStart).sorted()
        for occ in occurrences where occ.isLongSprint {
            let id = "extra@\(occ.sprintStart)"
            let collected = plan.confirmed.flatMap(\.contributions)
                .filter { $0.needId == id }.reduce(0) { $0 + $1.amount }
            // Цель сбора — полные порции всех еженедельных статей на лишнюю
            // финнеделю (С9, С10); правка порций в окне меняет остаток (П11).
            let remaining = plan.weeklySum - collected
            guard remaining > 1e-9 else { continue }
            let extraStart = occ.sprintStart.adding(days: (occ.sprintWeeks - 1) * 7)
            let windowStart = longStarts.last { $0 < occ.sprintStart }
            let window = occurrences.filter {
                $0.sprintStart != occ.sprintStart && $0.factDate < extraStart
                    && (windowStart == nil || $0.factDate >= windowStart!)
            }
            if window.isEmpty {
                // Вход рядом с длинным спринтом (МП21): собирать не с чего — потребность
                // заявляется на старт лишней финнедели, не поместится — недостача (П9).
                needs.append(Need(id: id, name: "дополнительная неделя", kind: .payment,
                                  due: extraStart, amount: remaining))
            } else {
                // Остаток делится по приходам окна равными долями (МП21): пропущенный
                // сбор увеличивает доли оставшихся приходов, а не исчезает (П11, П12).
                let share = remaining / Double(window.count)
                for w in window {
                    needs.append(Need(id: id, name: "дополнительная неделя", kind: .payment,
                                      due: w.factDate, amount: share))
                }
            }
        }

        var rec = Balancer().recommend(incomes: balancingIncomes, needs: needs)
        rec.contributions.append(contentsOf: extraContribs)

        return HorizonRecommendation(recommendation: rec, occurrences: occurrences,
                                     intentFinish: intentFinish)
    }
}
