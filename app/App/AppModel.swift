import Foundation
import Observation
import FinCalendarCore

/// Состояние приложения: план + горизонт. План хранится локально (МП3),
/// каждая правка пересчитывает неразложенное будущее (П11).
@Observable
final class AppModel {
    private(set) var plan: Plan
    private(set) var today: CivilDate
    private(set) var horizon: HorizonRecommendation
    /// Лента — готовая вью-модель горизонта: считается при правках плана, не в рендере.
    private(set) var tape: TapeModel
    /// Плана ещё нет — показывается вход (МП18–МП21).
    private(set) var needsOnboarding: Bool

    /// Глубина ленты — 5 лет в каждую сторону (МП23). Вниз это ещё и глубина
    /// пересчёта: числа плана не должны зависеть от того, как далеко человек
    /// домотал ленту, поэтому горизонт один и на всю глубину — иначе занятость
    /// спринта на ленте и свободные деньги в раскладке расходились бы.
    /// Вверх сетка та же, но раньше даты входа в спринтах ничего нет.
    static let horizonMonths = 60

    private static var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plan.json")
    }

    static var realToday: CivilDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return CivilDate(c.year!, c.month!, c.day!)
    }

    init() {
        var today = Self.realToday
        #if DEBUG
        today = today.adding(days: UserDefaults.standard.integer(forKey: "debugDayOffset"))
        #endif
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
        let horizon = PlanEngine.recompute(loaded, today: today,
                                           horizonMonths: Self.horizonMonths)
        self.horizon = horizon
        self.tape = TapeModel(plan: loaded, horizon: horizon, today: today,
                              pastMonths: Self.horizonMonths)
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
        recompute()
    }

    /// Пересчёт неразложенного будущего (П11) и ленты по нему.
    private func recompute() {
        horizon = PlanEngine.recompute(plan, today: today, horizonMonths: Self.horizonMonths)
        tape = TapeModel(plan: plan, horizon: horizon, today: today,
                         pastMonths: Self.horizonMonths)
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
        let rec = PlanEngine.recompute(temp, today: today,
                                       horizonMonths: Self.horizonMonths).recommendation
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
        return PlanEngine.recompute(temp, today: today, horizonMonths: Self.horizonMonths)
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

    #if DEBUG
    // MARK: Сдвиг дня — только для тестирования, в рабочей сборке не существует.

    var isTimeShifted: Bool { today != Self.realToday }

    func debugShiftDay(by days: Int) {
        today = today.adding(days: days)
        UserDefaults.standard.set(today.dayNumber - Self.realToday.dayNumber,
                                  forKey: "debugDayOffset")
        recompute()
    }

    func debugResetDay() {
        debugShiftDay(by: Self.realToday.dayNumber - today.dayNumber)
    }
    #endif

    /// «Начать заново» (settings.md): полное стирание — не перезапуск К7, а стирание.
    func eraseEverything() {
        try? FileManager.default.removeItem(at: Self.storeURL)
        plan = Plan(namedWeek: 0, weekBoundary: 6, incomes: [], entryDate: today)
        needsOnboarding = true
        recompute()
    }

    // MARK: Раскладка

    /// Черновик с фактической суммой прихода (МП27): план не меняет.
    func draft(for occurrenceId: String, factAmount: Double) -> HorizonRecommendation {
        PlanEngine.recompute(plan, today: today, horizonMonths: Self.horizonMonths,
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

    /// Собранное статьёй «дополнительная неделя» длинного спринта (С9–С10): взносы
    /// приходов окна — застывшие в подтверждённых раскладках (П12) плюс ещё только
    /// рекомендованные. Приход самого спринта в сборе не участвует, пока в окне есть
    /// другие, поэтому в его раскладке эта сумма — «собрано ранее» (layout.md).
    func extraWeekCollected(sprintStart: CivilDate, in rec: Recommendation? = nil) -> Double {
        let id = "extra@\(sprintStart)"
        let frozen = plan.confirmed.flatMap(\.contributions)
            .filter { $0.needId == id }.reduce(0) { $0 + $1.amount }
        let planned = (rec ?? horizon.recommendation).contributions
            .filter { $0.needId == id }.reduce(0) { $0 + $1.amount }
        return frozen + planned
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
