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
    /// Плана ещё нет — показывается вход (МП18–МП21).
    private(set) var needsOnboarding: Bool

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
            self.needsOnboarding = false
        } else {
            loaded = Plan(namedWeek: 0, weekBoundary: 6, incomes: [], entryDate: today)
            self.needsOnboarding = true
        }
        self.plan = loaded
        self.horizon = PlanEngine.recompute(loaded, today: today, horizonMonths: 3)
        NotificationManager.reschedule(self)
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
        NotificationManager.reschedule(self)
    }

    // MARK: Вход (МП18–МП21)

    func completeOnboarding(incomes: [PlannedIncome], articles: [Article],
                            namedWeek: Double, weekBoundary: Int) {
        plan = Plan(namedWeek: namedWeek, weekBoundary: weekBoundary, incomes: incomes,
                    entryDate: today, articles: articles)
        needsOnboarding = false
        mutate { _ in }
    }

    /// Проверка «помещается» для называемой недели (МП20): временный план, не сохраняется.
    func fits(namedWeek: Double, incomes: [PlannedIncome]? = nil,
              articles: [Article]? = nil, weekBoundary: Int? = nil) -> Bool {
        var temp = plan
        temp.namedWeek = namedWeek
        if let incomes { temp.incomes = incomes }
        if let articles { temp.articles = articles }
        if let weekBoundary { temp.weekBoundary = weekBoundary }
        if temp.incomes.isEmpty { return false }
        let rec = PlanEngine.recompute(temp, today: today, horizonMonths: 6).recommendation
        return rec.fits
    }

    /// «Посчитать за меня» (МП20): максимум недели, при котором план помещается.
    func maxFittingWeek(incomes: [PlannedIncome]? = nil, articles: [Article]? = nil,
                        weekBoundary: Int? = nil) -> Double {
        var lo = 0.0, hi = 1_000_000.0
        guard fits(namedWeek: lo, incomes: incomes, articles: articles, weekBoundary: weekBoundary)
        else { return 0 }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if fits(namedWeek: mid, incomes: incomes, articles: articles, weekBoundary: weekBoundary) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo.rounded(.down)
    }

    // MARK: Статьи (С1–С8, С4а)

    func addArticle(_ article: Article) {
        mutate { $0.articles.append(article) }
    }

    func updateArticle(_ article: Article) {
        mutate {
            if let i = $0.articles.firstIndex(where: { $0.id == article.id }) {
                $0.articles[i] = article
            }
        }
    }

    /// Пауза (П8): скорость временно ноль, строка остаётся.
    func setPaused(articleId: String, paused: Bool) {
        mutate {
            if let i = $0.articles.firstIndex(where: { $0.id == articleId }) {
                $0.articles[i].paused = paused
            }
        }
    }

    /// Закрытие решением человека (С4а): собранное выдано, скорость освобождается.
    func closeArticle(articleId: String) {
        mutate { $0.articles.removeAll { $0.id == articleId } }
    }

    /// Последствие до сохранения (МП11): рекомендация с добавленной статьёй, план не меняется.
    func preview(adding article: Article) -> HorizonRecommendation {
        var temp = plan
        temp.articles.append(article)
        return PlanEngine.recompute(temp, today: today, horizonMonths: 6)
    }

    // MARK: Выдача (С16, МП32)

    func isIssued(weekStart: CivilDate) -> Bool {
        plan.issuedWeeks.contains(weekStart)
    }

    func issueWeek(weekStart: CivilDate) {
        mutate { $0.issuedWeeks.insert(weekStart) }
    }

    // MARK: Настройки (МП35–МП36)

    /// Смена недели — не перезапуск: действует со следующей раскладки (МП36).
    func setNamedWeek(_ value: Double) {
        mutate { $0.namedWeek = value }
    }

    func setIncomes(_ incomes: [PlannedIncome]) {
        mutate { $0.incomes = incomes }
    }

    func setNotifications(layout: Bool, issue: Bool) {
        mutate { $0.notifyLayout = layout; $0.notifyIssue = issue }
    }

    /// «Начать заново» (settings.md): полное стирание — не перезапуск К7, а стирание.
    func eraseEverything() {
        try? FileManager.default.removeItem(at: Self.storeURL)
        plan = Plan(namedWeek: 0, weekBoundary: 6, incomes: [], entryDate: today)
        needsOnboarding = true
        horizon = PlanEngine.recompute(plan, today: today, horizonMonths: 3)
        NotificationManager.reschedule(self)
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
                                     incomeName: incomeName(anchorDay: occurrence.anchorDay),
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

    // MARK: Имена

    func incomeName(anchorDay: Int) -> String {
        plan.incomes.first { $0.anchor.day == anchorDay }?.anchor.name ?? "приход \(anchorDay)-го"
    }

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
