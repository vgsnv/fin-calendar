/// Балансировка (П6–П10): распределение приходов по статьям и финнеделям.
///
/// Модель: деньги движутся только вперёд во времени (П7). Недельные деньги —
/// константа плана: каждая финнеделя — жёсткая потребность в полную порцию на
/// её старте; взнос статьи — потребность на её сроке. У плана два состояния:
/// сходится или нет (П6). Недостача заявляется с точной цифрой и датой (П9);
/// недельные деньги не гнутся никогда — решения предлагает только П8.
/// Излишек прихода после взносов и недельных — свободные деньги (П6а),
/// и внутри месяца он выравнивается между приходами взносами статей (П6б).
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
    /// Месяц прихода — группа ровности свободных денег (П6б): год × 12 + месяц.
    /// Считается по номинальной опорной дате (СВ1), а не по факту: перенос по
    /// производственному календарю уводит факт в соседний месяц (аванс 5 января →
    /// 30 декабря), но аванс и зарплата одного месяца остаются одной группой.
    public let month: Int

    public init(id: String, factDate: CivilDate, amount: Double, nominalDate: CivilDate? = nil) {
        self.id = id
        self.factDate = factDate
        self.amount = amount
        let nominal = nominalDate ?? factDate
        self.month = nominal.year * 12 + nominal.month
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
    /// Свободные деньги по приходам (П6а): излишек после взносов и недельных.
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

    private struct Slot { let due: CivilDate; let amount: Double; let needId: String? }

    /// Кто кого кормит: каждая потребность — из последнего успевшего прихода (LIFO).
    /// Так резерв с ранних приходов возникает только по необходимости, а свободные
    /// деньги остаются у своих приходов (П6а, кейс 1). Слот, на который денег
    /// не хватило, становится недостачей своей даты (П9). Готовую раздачу взносов
    /// довыравнивает `level` — ровность свободных денег внутри месяца (П6б).
    private func fund(incomes: [BalancingIncome], weekAmounts: [(CivilDate, Double)], needs: [Need]) -> Recommendation {
        var slots: [Slot] = weekAmounts.map { Slot(due: $0.0, amount: $0.1, needId: nil) }
            + needs.map { Slot(due: $0.due, amount: $0.amount, needId: $0.id) }
        // При равном сроке первой кормится финнеделя: недельные не гнутся никогда,
        // недостачу забирает статья (П9). Дальше — по имени: расчёт однозначен.
        slots.sort { ($0.due, $0.needId ?? "") < ($1.due, $1.needId ?? "") }

        var remaining = Dictionary(uniqueKeysWithValues: incomes.map { ($0.id, $0.amount) })
        let byDate = incomes.sorted { $0.factDate < $1.factDate }
        // Взносы по слотам: у дополнительной недели один id на несколько сроков (С10),
        // поэтому раздача живёт по слотам, а не по потребностям.
        var funded = [[String: Double]](repeating: [:], count: slots.count)
        var missingByDate: [CivilDate: Double] = [:]

        for (i, slot) in slots.enumerated() {
            var toFund = slot.amount
            for income in byDate.reversed() where income.factDate <= slot.due && toFund > 1e-9 {
                let take = min(remaining[income.id] ?? 0, toFund)
                guard take > 1e-9 else { continue }
                remaining[income.id]! -= take
                toFund -= take
                if slot.needId != nil { funded[i][income.id, default: 0] += take }
            }
            if toFund > 1e-9 { missingByDate[slot.due, default: 0] += toFund }
        }

        level(slots: slots, incomes: incomes, funded: &funded, remaining: &remaining)

        let order = Dictionary(uniqueKeysWithValues: byDate.enumerated().map { ($1.id, $0) })
        var contributions: [Contribution] = []
        for (i, slot) in slots.enumerated() {
            guard let needId = slot.needId else { continue }
            for (incomeId, amount) in funded[i].sorted(by: { order[$0.key]! < order[$1.key]! })
            where amount > 1e-9 {
                contributions.append(Contribution(needId: needId, incomeId: incomeId, amount: amount))
            }
        }

        let weeks = weekAmounts.map { WeekAmount(start: $0.0, amount: $0.1) }
        let shortfalls = missingByDate
            .map { Shortfall(date: $0.key, amount: $0.value) }
            .sorted { $0.date < $1.date }
        return Recommendation(weeks: weeks, contributions: contributions,
                              freeMoney: remaining, shortfalls: shortfalls)
    }

    // MARK: Ровность свободных денег внутри месяца (П6б)

    /// Взносы статей перекладываются между приходами одного месяца так, чтобы
    /// свободные деньги приходов сравнялись: большой приход сознательно грузится
    /// статьями сильнее маленького (П6).
    ///
    /// Переносятся только взносы. Порция финнедели остаётся на приходе своего
    /// спринта: недельные — константа плана (П9), и раскладка каждого прихода
    /// сходится по арифметике. Сроки нерушимы (П7): взнос ложится только на приход,
    /// успевающий до срока потребности, — поэтому ровность достигается «насколько
    /// возможно», а не всегда. Суммарная нагрузка месяца не меняется: недостачи
    /// остаются те же (П9), и резерв с прошлых месяцев по-прежнему возникает только
    /// по необходимости — между месяцами ровности нет, свободные деньги остаются
    /// свойством прихода (П6а).
    private func level(slots: [Slot], incomes: [BalancingIncome],
                       funded: inout [[String: Double]], remaining: inout [String: Double]) {
        let groups = Dictionary(grouping: incomes, by: \.month)
        for month in groups.keys.sorted() {
            let members = groups[month]!.sorted { $0.factDate < $1.factDate }.map(\.id)
            guard members.count > 1 else { continue }
            let dateById = Dictionary(uniqueKeysWithValues: groups[month]!.map { ($0.id, $0.factDate) })

            // Снимаем с приходов месяца их взносы — раздадим заново, выравнивая остатки.
            var free = Dictionary(uniqueKeysWithValues: members.map { ($0, remaining[$0] ?? 0) })
            var burdens: [(slot: Int, due: CivilDate, amount: Double)] = []
            for i in slots.indices where slots[i].needId != nil {
                var taken = 0.0
                for id in members {
                    guard let share = funded[i][id] else { continue }
                    funded[i][id] = nil
                    free[id]! += share
                    taken += share
                }
                if taken > 1e-9 { burdens.append((i, slots[i].due, taken)) }
            }

            // Потребности — по возрастанию срока: у поздней круг кормильцев шире,
            // поэтому разливка «в самый полный приход» никогда не отнимает денег
            // у следующей — новых недостач ровность не создаёт.
            for b in burdens.sorted(by: { $0.due < $1.due }) {
                let candidates = members.filter { dateById[$0]! <= b.due }
                var left = b.amount
                while left > 1e-9 {
                    let levels = candidates.map { free[$0]! }
                    let top = levels.max() ?? 0
                    guard top > 1e-9 else { break }
                    // Самые полные приходы сливаются до уровня следующего за ними,
                    // а сравнявшись — платят дальше поровну.
                    let fullest = candidates.filter { free[$0]! > top - 1e-9 }
                    let next = levels.filter { $0 < top - 1e-9 }.max() ?? 0
                    let step = min(top - next, left / Double(fullest.count))
                    for id in fullest {
                        free[id]! -= step
                        funded[b.slot][id, default: 0] += step
                    }
                    left -= step * Double(fullest.count)
                }
                assert(left < 1e-6, "ровность не теряет денег: нагрузка месяца по построению помещается в его приходы")
            }
            for (id, value) in free { remaining[id] = value }
        }
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
    /// затем даты платежей (П8). Недельные деньги в списке не участвуют
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
