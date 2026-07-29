/// Балансировка (П6–П10): распределение приходов по статьям и финнеделям.
///
/// Модель: деньги движутся только вперёд во времени (П7). Повседневные деньги
/// каждой финнедели — потребность на её старте; взнос статьи — потребность на её
/// сроке. Балансировка ищет лексикографический максимин остатка по финнеделям:
/// первым отдаётся вариант с самым высоким минимальным остатком (П6).
/// Тонкие финнедели заявляются с точной цифрой (П9). Излишек прихода после
/// взносов и повседневных — свободные деньги (П6а). Точные цифры — П10.

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

public struct WeekAmount: Equatable, Sendable {
    public let start: CivilDate
    public let amount: Double
    /// Остаток ниже названной порции — тонкая финнеделя (П9).
    public let isThin: Bool
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
    /// Потребности, не собираемые даже при нулевых неделях, — план не сходится (П9).
    public var unmetNeeds: [String]

    public var thinWeeks: [WeekAmount] { weeks.filter(\.isThin) }
    public var fits: Bool { thinWeeks.isEmpty && unmetNeeds.isEmpty }
}

public struct Balancer: Sendable {
    public let namedWeek: Double

    public init(namedWeek: Double) {
        precondition(namedWeek >= 0)
        self.namedWeek = namedWeek
    }

    // MARK: Максимин

    /// Главный вариант рекомендации: лексикографический максимин остатка (П6).
    public func recommend(incomes: [BalancingIncome], weekStarts: [CivilDate], needs: [Need]) -> Recommendation {
        let weekAmounts = maximinWeeks(incomes: incomes, weekStarts: weekStarts, needs: needs)
        return fund(incomes: incomes, weekAmounts: weekAmounts, needs: needs)
    }

    /// Пофиннедельные суммы: сегментный максимин.
    /// Для каждой точки-кандидата t (старт недели или срок потребности) считается
    /// потолок prefix-остатка; узкое место фиксирует свой сегмент, дальше — рекурсия.
    private func maximinWeeks(incomes: [BalancingIncome], weekStarts: [CivilDate], needs: [Need]) -> [(CivilDate, Double)] {
        var result: [(CivilDate, Double)] = []
        var incomes = incomes.sorted { $0.factDate < $1.factDate }
        var needs = needs.sorted { $0.due < $1.due }
        var weeks = weekStarts.sorted()

        while !weeks.isEmpty {
            let cuts = Set(weeks + needs.map(\.due)).sorted()
            var best: (cut: CivilDate, ratio: Double)? = nil
            for t in cuts {
                let weeksK = weeks.filter { $0 <= t }.count
                guard weeksK > 0 else { continue }
                let money = incomes.filter { $0.factDate <= t }.reduce(0) { $0 + $1.amount }
                let fixed = needs.filter { $0.due <= t }.reduce(0) { $0 + $1.amount }
                let ratio = (money - fixed) / Double(weeksK)
                if best == nil || ratio < best!.ratio { best = (t, ratio) }
            }
            guard let (cut, ratio) = best else { break }

            if ratio >= namedWeek {
                // Всё оставшееся помещается: недели живут полной порцией.
                result.append(contentsOf: weeks.map { ($0, namedWeek) })
                break
            }
            // Узкое место: сегмент до cut живёт на ratio (не ниже нуля).
            let seg = max(0, ratio)
            let segWeeks = weeks.filter { $0 <= cut }
            result.append(contentsOf: segWeeks.map { ($0, seg) })
            weeks.removeAll { $0 <= cut }
            incomes.removeAll { $0.factDate <= cut }
            needs.removeAll { $0.due <= cut }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    // MARK: Назначение источников

    /// Кто кого кормит: каждая потребность — из последнего успевшего прихода (LIFO).
    /// Так резерв с ранних приходов возникает только по необходимости, а свободные
    /// деньги остаются у своих приходов (П6а, кейс 1).
    private func fund(incomes: [BalancingIncome], weekAmounts: [(CivilDate, Double)], needs: [Need]) -> Recommendation {
        struct Slot { let due: CivilDate; let amount: Double; let needId: String? ; let weekStart: CivilDate? }
        var slots: [Slot] = weekAmounts.map { Slot(due: $0.0, amount: $0.1, needId: nil, weekStart: $0.0) }
            + needs.map { Slot(due: $0.due, amount: $0.amount, needId: $0.id, weekStart: nil) }
        slots.sort { $0.due < $1.due }

        var remaining = Dictionary(uniqueKeysWithValues: incomes.map { ($0.id, $0.amount) })
        let byDate = incomes.sorted { $0.factDate < $1.factDate }
        var contributions: [Contribution] = []
        var unmet: Set<String> = []

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
            if toFund > 1e-9, let needId = slot.needId { unmet.insert(needId) }
        }

        let weeks = weekAmounts.map { WeekAmount(start: $0.0, amount: $0.1, isThin: $0.1 < namedWeek - 1e-9) }
        return Recommendation(weeks: weeks, contributions: contributions,
                              freeMoney: remaining, unmetNeeds: unmet.sorted())
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
        func recompute(without id: String) -> Recommendation {
            recommend(incomes: incomes, weekStarts: weekStarts, needs: needs.filter { $0.id != id })
        }
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
        for n in needs where n.kind == .payment {
            var shifted = needs.filter { $0.id != n.id }
            shifted.append(Need(id: n.id, name: n.name, kind: .payment,
                                due: n.due.adding(days: paymentShiftDays), amount: n.amount))
            let rec = recommend(incomes: incomes, weekStarts: weekStarts, needs: shifted)
            options.append(BendingOption(bending: .shiftPaymentDate(needName: n.name, days: paymentShiftDays),
                                         recomputed: rec))
        }
        return options
    }
}
