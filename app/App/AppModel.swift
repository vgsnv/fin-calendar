import Foundation
import Observation
import FinCalendarCore

/// Состояние приложения: план + горизонт. План хранится локально (МП3),
/// каждая правка пересчитывает неразложенное будущее (П11).
@Observable
final class AppModel {
    private(set) var plan: Plan
    let today: CivilDate
    private(set) var horizon: HorizonRecommendation

    private static var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plan.json")
    }

    init() {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = CivilDate(c.year!, c.month!, c.day!)
        self.today = today

        let loaded: Plan
        if let data = try? Data(contentsOf: Self.storeURL),
           let saved = try? JSONDecoder().decode(Plan.self, from: data) {
            loaded = saved
        } else {
            loaded = Self.demoPlan(today: today)
        }
        self.plan = loaded
        self.horizon = PlanEngine.recompute(loaded, today: today, horizonMonths: 3)
    }

    private static func demoPlan(today: CivilDate) -> Plan {
        Plan(namedWeek: 12_000,
             weekBoundary: 6,
             incomes: [PlannedIncome(anchor: Anchor(day: 5, name: "Аванс"), plannedAmount: 50_000),
                       PlannedIncome(anchor: Anchor(day: 20, name: "Зарплата"), plannedAmount: 55_000)],
             entryDate: CivilDate(dayNumber: today.dayNumber - 21),
             articles: [
                 Article(id: "кредит", name: "кредит",
                         kind: .payment(amount: 15_000, date: CivilDate(today.year, today.month, 5),
                                        monthlyDay: 5, prepared: true)),
                 Article(id: "страховка", name: "страховка",
                         kind: .payment(amount: 24_000,
                                        date: CivilDate(dayNumber: today.dayNumber + 58),
                                        monthlyDay: nil, prepared: true)),
                 Article(id: "ноутбук", name: "ноутбук",
                         kind: .intent(target: 120_000, monthlySpeed: 10_000)),
                 Article(id: "одежда", name: "одежда", kind: .fund(monthlySpeed: 6_000))
             ])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(plan) {
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }

    private func mutate(_ change: (inout Plan) -> Void) {
        change(&plan)
        save()
        horizon = PlanEngine.recompute(plan, today: today, horizonMonths: 3)  // П11
    }

    // MARK: Раскладка

    /// Черновик с фактической суммой прихода (МП27): план не меняет.
    func draft(for occurrenceId: String, factAmount: Double) -> HorizonRecommendation {
        PlanEngine.recompute(plan, today: today, horizonMonths: 3,
                             factOverrides: [occurrenceId: factAmount])
    }

    /// Подтверждение раскладки: числа застывают, граница пересчёта сдвигается (П12, МП30).
    func confirmLayout(occurrence: IncomeOccurrence, factAmount: Double,
                       recommendation: Recommendation) {
        let weekStarts = (0..<occurrence.sprintWeeks).map { occurrence.sprintStart.adding(days: $0 * 7) }
        let weeks = recommendation.weeks
            .filter { weekStarts.contains($0.start) }
            .map { WeekAllotment(start: $0.start, amount: $0.amount) }
        let contribs = recommendation.contributions.filter { $0.incomeId == occurrence.id }
        let layout = ConfirmedLayout(incomeId: occurrence.id,
                                     incomeName: occurrence.anchorDay == 5 ? "Аванс" : "Зарплата",
                                     factDate: occurrence.factDate,
                                     factAmount: factAmount,
                                     sprintStart: occurrence.sprintStart,
                                     sprintWeeks: occurrence.sprintWeeks,
                                     isLong: occurrence.isLongSprint,
                                     weekAmounts: weeks,
                                     contributions: contribs)
        mutate { $0.confirmed.append(layout) }
    }

    func layout(for incomeId: String) -> ConfirmedLayout? {
        plan.confirmed.first { $0.incomeId == incomeId }
    }

    // MARK: Чек-лист исполнения (отметки — память, не факты: С12, П3)

    func setExecuted(incomeId: String, key: String, done: Bool) {
        mutateExecuted(incomeId: incomeId) {
            if done { $0.insert(key) } else { $0.remove(key) }
        }
    }

    func executeAll(incomeId: String, keys: [String]) {
        mutateExecuted(incomeId: incomeId) { $0.formUnion(keys) }
    }

    private func mutateExecuted(incomeId: String, _ change: (inout Set<String>) -> Void) {
        guard let i = plan.confirmed.firstIndex(where: { $0.incomeId == incomeId }) else { return }
        // Отметки не меняют план — без пересчёта, только сохранение.
        change(&plan.confirmed[i].executed)
        save()
    }

    // MARK: Имена статей для строк раскладки

    func articleName(for needId: String) -> String {
        if needId.hasPrefix("extra@") { return "дополнительная неделя" }
        let articleId = needId.split(separator: "@").first.map(String.init) ?? needId
        return plan.articles.first { $0.id == articleId }?.name ?? articleId
    }

    func needOrder(for needId: String) -> Int {
        if needId.hasPrefix("extra@") { return 2 }
        let articleId = needId.split(separator: "@").first.map(String.init) ?? needId
        guard let a = plan.articles.first(where: { $0.id == articleId }) else { return 3 }
        switch a.kind {
        case .payment: return 0
        case .intent, .fund: return 1
        }
    }
}
