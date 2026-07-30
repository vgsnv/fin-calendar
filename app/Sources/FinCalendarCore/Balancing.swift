/// Балансировка (П6–П10): распределение приходов по статьям и финнеделям.
///
/// Модель: деньги движутся только вперёд во времени (П7). Повседневные деньги —
/// константа плана: каждая финнеделя — жёсткая потребность в полную порцию на
/// её старте; взнос статьи — потребность на её сроке. У плана два состояния:
/// сходится или нет (П6). Недостача заявляется с точной цифрой и датой (П9);
/// повседневные деньги не гнутся никогда — решения предлагает только П8.
/// Излишек прихода после взносов и повседневных — свободные деньги (П6а).
/// Точные цифры — П10.

public enum NeedKind: Equatable, Sendable {
    case payment       // платёж с датой, подготовка заранее
    case fundSpeed     // взнос фонда со своего прихода
    case intentSpeed   // взнос замысла со своего прихода
}

/// Потребность плана: сумма, которая должна быть собрана к сроку.
public struct Need: Sendable {
    public let id: String
    public let name: String
    public let kind: NeedKind
    public let due: CivilDate
    public let amount: Double

    public init(id: String, name: String, kind: NeedKind, due: CivilDate, amount: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.due = due
        self.amount = amount
    }
}

public struct BalancingIncome: Sendable {
    public let id: String
    public let factDate: CivilDate
    public let amount: Double

    public init(id: String, factDate: CivilDate, amount: Double) {
        self.id = id
        self.factDate = factDate
        self.amount = amount
    }
}

/// Финнеделя рекомендации: всегда полная порция (П1, П9).
public struct WeekAmount: Equatable, Sendable {
    public let start: CivilDate
    public let amount: Double
}

/// Недостача: к этой дате плану не хватает этой суммы (П9).
public struct Shortfall: Equatable, Sendable {
    public let date: CivilDate
    public let amount: Double
}

public struct Contribution: Equatable, Codable, Sendable {
    public let needId: String
    public let incomeId: String
    public let amount: Double
}

public struct Recommendation: Sendable {
    public var weeks: [WeekAmount]
    public var contributions: [Contribution]
    /// Свободные деньги по приходам (П6а): излишек после взносов и повседневных.
    public var freeMoney: [String: Double]
    /// Недостачи по датам (П9): пусто — план сходится.
    public var shortfalls: [Shortfall]

    public var fits: Bool { shortfalls.isEmpty }
}

public struct Balancer: Sendable {
    public let namedWeek: Double

    public init(namedWeek: Double) {
        precondition(namedWeek >= 0)
        self.namedWeek = namedWeek
    }

    // MARK: Проверка сходимости и назначение источников

    /// Рекомендация: каждая финнеделя — полная порция, статьи — по срокам.
    /// Не помещается — недостача с цифрой и датой (П9), решения — П8.
    public func recommend(incomes: [BalancingIncome], weekStarts: [CivilDate], needs: [Need]) -> Recommendation {
        let weekAmounts = weekStarts.sorted().map { ($0, namedWeek) }
        return fund(incomes: incomes, weekAmounts: weekAmounts, needs: needs)
    }

    /// Кто кого кормит: каждая потребность — из последнего успевшего прихода (LIFO).
    /// Так резерв с ранних приходов возникает только по необходимости, а свободные
    /// деньги остаются у своих приходов (П6а, кейс 1). Слот, на который денег
    /// не хватило, становится недостачей своей даты (П9).
    private func fund(incomes: [BalancingIncome], weekAmounts: [(CivilDate, Double)], needs: [Need]) -> Recommendation {
        struct Slot { let due: CivilDate; let amount: Double; let needId: String? }
        var slots: [Slot] = weekAmounts.map { Slot(due: $0.0, amount: $0.1, needId: nil) }
            + needs.map { Slot(due: $0.due, amount: $0.amount, needId: $0.id) }
        slots.sort { $0.due < $1.due }

        var remaining = Dictionary(uniqueKeysWithValues: incomes.map { ($0.id, $0.amount) })
        let byDate = incomes.sorted { $0.factDate < $1.factDate }
        var contributions: [Contribution] = []
        var missingByDate: [CivilDate: Double] = [:]

        for slot in slots {
            var toFund = slot.amount
            for income in byDate.reversed() where income.factDate <= slot.due && toFund > 1e-9 {
                let take = min(remaining[income.id] ?? 0, toFund)
                guard take > 1e-9 else { continue }
                remaining[income.id]! -= take
                toFund -= take
                if let needId = slot.needId {
                    contributions.append(Contribution(needId: needId, incomeId: income.id, amount: take))
                }
            }
            if toFund > 1e-9 { missingByDate[slot.due, default: 0] += toFund }
        }

        let weeks = weekAmounts.map { WeekAmount(start: $0.0, amount: $0.1) }
        let shortfalls = missingByDate
            .map { Shortfall(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
        return Recommendation(weeks: weeks, contributions: contributions,
                              freeMoney: remaining, shortfalls: shortfalls)
    }

    // MARK: Порядок уступчивости (П8)

    public enum Bending: Equatable, Sendable {
        case pauseFund(needName: String)
        case pauseIntent(needName: String)
        case shiftPaymentDate(needName: String, days: Int)
    }

    public struct BendingOption: Sendable {
        public let bending: Bending
        public let recomputed: Recommendation
    }

    /// Варианты, когда план не сходится: сначала гнутся фонды, затем замыслы,
    /// затем даты платежей (П8). Повседневные деньги в списке не участвуют
    /// никогда (П9): урезания недели среди вариантов не существует по построению.
    public func bendingOptions(incomes: [BalancingIncome], weekStarts: [CivilDate],
                               needs: [Need], paymentShiftDays: Int = 14) -> [BendingOption] {
        let base = recommend(incomes: incomes, weekStarts: weekStarts, needs: needs)
        guard !base.fits else { return [] }

        var options: [BendingOption] = []
        let names = { (kind: NeedKind) in
            var seen = Set<String>()
            return needs.filter { $0.kind == kind && seen.insert($0.name).inserted }
        }
        for n in names(.fundSpeed) {
            let rec = recommend(incomes: incomes, weekStarts: weekStarts,
                                needs: needs.filter { $0.name != n.name })
            options.append(BendingOption(bending: .pauseFund(needName: n.name), recomputed: rec))
        }
        for n in names(.intentSpeed) {
            let rec = recommend(incomes: incomes, weekStarts: weekStarts,
                                needs: needs.filter { $0.name != n.name })
            options.append(BendingOption(bending: .pauseIntent(needName: n.name), recomputed: rec))
        }
        // Платёж, живущий несколькими потребностями (ежемесячный — по одной на месяц,
        // дополнительная неделя — по одной на приход окна), даёт один вариант, а не
        // по варианту на потребность: человеку предлагается сдвинуть статью.
        for n in names(.payment) {
            let shifted = needs.map { need in
                need.kind == .payment && need.name == n.name
                    ? Need(id: need.id, name: need.name, kind: .payment,
                           due: need.due.adding(days: paymentShiftDays), amount: need.amount)
                    : need
            }
            let rec = recommend(incomes: incomes, weekStarts: weekStarts, needs: shifted)
            options.append(BendingOption(bending: .shiftPaymentDate(needName: n.name, days: paymentShiftDays),
                                         recomputed: rec))
        }
        return options
    }
}
