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
}

extension ArticleKind: Codable {}

public struct Article: Equatable, Codable, Sendable {
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
}

public struct Plan: Codable, Sendable {
    public var namedWeek: Double
    public var weekBoundary: Int
    public var incomes: [PlannedIncome]
    public var production: ProductionCalendar
    public var entryDate: CivilDate
    public var articles: [Article]
    public var confirmed: [ConfirmedLayout]

    public init(namedWeek: Double, weekBoundary: Int, incomes: [PlannedIncome],
                production: ProductionCalendar = .none, entryDate: CivilDate,
                articles: [Article] = [], confirmed: [ConfirmedLayout] = []) {
        self.namedWeek = namedWeek
        self.weekBoundary = weekBoundary
        self.incomes = incomes
        self.production = production
        self.entryDate = entryDate
        self.articles = articles
        self.confirmed = confirmed
    }

    /// Собрано по статье из подтверждённых раскладок (взносы не возвращаются, П12, С4а).
    public func collected(articleId: String) -> Double {
        confirmed.flatMap(\.contributions)
            .filter { $0.needId == articleId || $0.needId.hasPrefix(articleId + "@") }
            .reduce(0) { $0 + $1.amount }
    }
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
        for s in grid where s.end >= plan.entryDate {
            for (day, fact) in zip(s.anchorDays, s.factDates) {
                let id = "\(day)@\(fact)"
                guard !confirmedIds.contains(id), s.end >= today else { continue }
                occurrences.append(IncomeOccurrence(id: id, anchorDay: day, factDate: fact,
                                                    sprintStart: s.start, sprintWeeks: s.weeks,
                                                    plannedAmount: factOverrides[id] ?? amountByDay[day] ?? 0,
                                                    isLongSprint: s.isLong))
            }
        }
        occurrences.sort { $0.factDate < $1.factDate }
        guard !occurrences.isEmpty else {
            return HorizonRecommendation(
                recommendation: Recommendation(weeks: [], contributions: [], freeMoney: [:], unmetNeeds: []),
                occurrences: [], intentFinish: [:])
        }
        let horizonEnd = occurrences.map { $0.sprintStart.adding(days: $0.sprintWeeks * 7) }.max()!

        // Платежи «без подготовки» уменьшают приход своего спринта до балансировки (С3).
        var unpreparedBySprint: [CivilDate: [(article: Article, amount: Double, date: CivilDate)]] = [:]
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
                unpreparedBySprint[occ.sprintStart, default: []].append((a, take, date))
            }
            balancingIncomes.append(BalancingIncome(id: occ.id, factDate: occ.factDate, amount: amount))
        }

        var weekStarts: [CivilDate] = []
        var seenSprints = Set<CivilDate>()
        for occ in occurrences where seenSprints.insert(occ.sprintStart).inserted {
            for w in 0..<occ.sprintWeeks { weekStarts.append(occ.sprintStart.adding(days: w * 7)) }
        }

        var needs: [Need] = []
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
            }
        }

        // Дополнительная финнеделя (С9–С10): системная статья, по порции на каждую
        // лишнюю финнеделю длинного спринта; окно сбора — до его старта.
        for occ in occurrences where occ.isLongSprint {
            let id = "extra@\(occ.sprintStart)"
            let remaining = plan.namedWeek - plan.confirmed.flatMap(\.contributions)
                .filter { $0.needId == id }.reduce(0) { $0 + $1.amount }
            if remaining > 1e-9 {
                needs.append(Need(id: id, name: "дополнительная неделя", kind: .payment,
                                  due: occ.sprintStart, amount: remaining))
            }
        }

        let balancer = Balancer(namedWeek: plan.namedWeek)
        var rec = balancer.recommend(incomes: balancingIncomes, weekStarts: weekStarts, needs: needs)
        rec.contributions.append(contentsOf: extraContribs)

        // С3, «без подготовки»: финнедели до даты платежа живут полной порцией,
        // утоньшение — на финнеделях от даты, и заявляется как факт (П9).
        for (sprintStart, payments) in unpreparedBySprint {
            guard let occ = occurrences.first(where: { $0.sprintStart == sprintStart }) else { continue }
            let starts = (0..<occ.sprintWeeks).map { sprintStart.adding(days: $0 * 7) }
            let idxs = rec.weeks.indices.filter { starts.contains(rec.weeks[$0].start) }
            let budget = idxs.reduce(0) { $0 + rec.weeks[$1].amount }
            let firstPaymentDate = payments.map(\.date).min()!
            let before = idxs.filter { rec.weeks[$0].start < firstPaymentDate }
            let after = idxs.filter { rec.weeks[$0].start >= firstPaymentDate }
            var left = budget
            var newAmounts: [Int: Double] = [:]
            for i in before {
                let a = min(plan.namedWeek, left)
                newAmounts[i] = a
                left -= a
            }
            for i in after { newAmounts[i] = after.isEmpty ? 0 : left / Double(after.count) }
            for (i, a) in newAmounts {
                rec.weeks[i] = WeekAmount(start: rec.weeks[i].start, amount: a,
                                          isThin: a < plan.namedWeek - 1e-9)
            }
        }

        return HorizonRecommendation(recommendation: rec, occurrences: occurrences,
                                     intentFinish: intentFinish)
    }
}
