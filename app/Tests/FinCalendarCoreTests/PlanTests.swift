import XCTest
@testable import FinCalendarCore

/// Слой плана: живой пересчёт (П11–П12), жизненный цикл статей (С3–С10),
/// дополнительная финнеделя (С9), недостача (П9), пропущенная раскладка (С15а).
/// Сквозной пример: приходы 5-го («Аванс» 50 000) и 20-го («Зарплата» 55 000),
/// неделя 12 000, граница — суббота, июль 2027-го.
final class PlanTests: XCTestCase {

    private func makePlan(articles: [Article] = [], confirmed: [ConfirmedLayout] = [],
                          entryDate: CivilDate = CivilDate(2027, 7, 1)) -> Plan {
        Plan(namedWeek: 12_000, weekBoundary: 6,
             incomes: [PlannedIncome(anchor: Anchor(day: 5, name: "Аванс"), plannedAmount: 50_000),
                       PlannedIncome(anchor: Anchor(day: 20, name: "Зарплата"), plannedAmount: 55_000)],
             entryDate: entryDate,
             articles: articles, confirmed: confirmed)
    }

    private let today = CivilDate(2027, 7, 1)

    // MARK: Живой пересчёт и граница (П11, П12)

    func testConfirmedLayoutExcludedFromRecompute() {
        var plan = makePlan()
        let r1 = PlanEngine.recompute(plan, today: today, horizonMonths: 2)
        let first = r1.occurrences.first { $0.id == "5@2027-07-05" }!
        XCTAssertEqual(first.factDate, CivilDate(2027, 7, 5))

        // Подтверждаем раскладку первого прихода — она застывает (П12).
        plan.confirmed.append(ConfirmedLayout(
            incomeId: first.id, factAmount: 50_000,
            weekAmounts: [WeekAllotment(start: first.sprintStart, amount: 12_000),
                          WeekAllotment(start: first.sprintStart.adding(days: 7), amount: 12_000)],
            contributions: []))

        let r2 = PlanEngine.recompute(plan, today: CivilDate(2027, 7, 12), horizonMonths: 2)
        XCTAssertFalse(r2.occurrences.contains { $0.id == first.id },
                       "подтверждённый приход не входит в пересчёт")
        XCTAssertFalse(r2.recommendation.weeks.contains { $0.start == first.sprintStart },
                       "недели разложенного спринта не пересчитываются")
    }

    // MARK: Ежемесячный платёж возрождается (С3)

    func testMonthlyPaymentRebornEachMonth() {
        let credit = Article(id: "кредит", name: "кредит",
                             kind: .payment(amount: 15_000, date: CivilDate(2027, 7, 5),
                                            monthlyDay: 5, prepared: true))
        let plan = makePlan(articles: [credit])
        let r = PlanEngine.recompute(plan, today: today, horizonMonths: 2)
        let creditContribs = Set(r.recommendation.contributions
            .filter { $0.needId.hasPrefix("кредит@") }.map(\.needId))
        XCTAssertGreaterThanOrEqual(creditContribs.count, 2, "платёж возрождается каждый месяц")
    }

    // MARK: Замысел: финиш вычисляется, собранное приближает его (С5, С6)

    func testIntentFinishMovesWithCollected() {
        let laptop = Article(id: "ноутбук", name: "ноутбук",
                             kind: .intent(target: 30_000, monthlySpeed: 10_000))
        let plan = makePlan(articles: [laptop])
        let r = PlanEngine.recompute(plan, today: today, horizonMonths: 5)
        // 5 000 с прихода: 30 000 соберутся на шестом приходе горизонта
        XCTAssertNotNil(r.intentFinish["ноутбук"])

        // Собранные взносы не возвращаются и приближают финиш (П12, С4а)
        let collected = ConfirmedLayout(
            incomeId: "5@2027-07-05", factAmount: 50_000, weekAmounts: [],
            contributions: [Contribution(needId: "ноутбук@2027-07-05", incomeId: "5@2027-07-05", amount: 20_000)])
        let plan2 = makePlan(articles: [laptop], confirmed: [collected])
        let r2 = PlanEngine.recompute(plan2, today: CivilDate(2027, 7, 12), horizonMonths: 5)
        XCTAssertEqual(plan2.collected(articleId: "ноутбук"), 20_000, accuracy: 0.01)
        XCTAssertLessThan(r2.intentFinish["ноутбук"]!, r.intentFinish["ноутбук"]!,
                          "финиш приблизился")
    }

    // MARK: Фонд занижает свободные деньги, пауза освобождает (С7, П8, С4а)

    func testFundLowersFreeMoneyPauseReleases() {
        let clothes = Article(id: "одежда", name: "одежда", kind: .fund(monthlySpeed: 6_000))
        let plan = makePlan(articles: [clothes])
        let r = PlanEngine.recompute(plan, today: today, horizonMonths: 1)
        let firstIncome = r.occurrences.first!.id
        let free = r.recommendation.freeMoney[firstIncome]!

        var paused = clothes
        paused.paused = true
        let r2 = PlanEngine.recompute(makePlan(articles: [paused]), today: today, horizonMonths: 1)
        let free2 = r2.recommendation.freeMoney[firstIncome]!
        XCTAssertEqual(free2 - free, 3_000, accuracy: 0.01,
                       "пауза фонда возвращает его взнос в свободные деньги со следующей раскладки")
    }

    // MARK: Дополнительная финнеделя (С9, С10)

    func testExtraWeekCollectedBeforeLongSprint() {
        let plan = makePlan()
        let r = PlanEngine.recompute(plan, today: today, horizonMonths: 6)
        // Длинный спринт впереди: его окно сбора (С10) ещё не пройдено.
        guard let long = r.occurrences.first(where: { $0.isLongSprint && $0.sprintStart > today })
        else {
            return XCTFail("в горизонте нет будущего длинного спринта")
        }
        let extraId = "extra@\(long.sprintStart)"
        let collected = r.recommendation.contributions
            .filter { $0.needId == extraId }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(collected, 12_000, accuracy: 0.01,
                       "порция недельных денег собрана к старту длинного спринта")

        let extraContribs = r.recommendation.contributions.filter { $0.needId == extraId }
        let sources = extraContribs.map { c in r.occurrences.first { $0.id == c.incomeId }! }
        let extraWeekStart = long.sprintStart.adding(days: (long.sprintWeeks - 1) * 7)

        // Окно сбора (С10): взносы — приходами обычных спринтов до лишней финнедели.
        for occ in sources {
            XCTAssertLessThan(occ.factDate, extraWeekStart, "взнос позже лишней финнедели (П7)")
            XCTAssertNotEqual(occ.sprintStart, long.sprintStart,
                              "приход длинного спринта оплачивает свою же лишнюю неделю (С9)")
        }
        // Размазано по приходам окна равными долями (МП21), а не куском на один приход.
        XCTAssertGreaterThan(sources.count, 1, "сбор не размазан по окну")
        let share = 12_000 / Double(sources.count)
        for c in extraContribs {
            XCTAssertEqual(c.amount, share, accuracy: 0.01, "доли приходов окна не равны")
        }
        // Лишняя неделя в балансировку не входит: её порция — статья,
        // двойного счёта не существует (С9).
        let extraStart = long.sprintStart.adding(days: (long.sprintWeeks - 1) * 7)
        XCTAssertFalse(r.recommendation.weeks.contains { $0.start == extraStart },
                       "дополнительная неделя оплачена из плана, не из прихода спринта повторно")
    }

    /// Вход рядом с длинным спринтом (МП21): окно сбора пусто — собирать не с чего,
    /// потребность заявляется на старт лишней финнедели и живёт приходом спринта.
    func testExtraWeekWithEmptyWindowFallsOnOwnIncome() {
        let plan = makePlan()
        let r = PlanEngine.recompute(plan, today: today, horizonMonths: 3)
        // Длинный спринт, уже идущий на момент входа: приходов до его лишней недели нет.
        guard let long = r.occurrences.first(where: { $0.isLongSprint && $0.sprintStart <= today })
        else {
            return XCTFail("в горизонте нет идущего длинного спринта")
        }
        let extraId = "extra@\(long.sprintStart)"
        let contribs = r.recommendation.contributions.filter { $0.needId == extraId }
        XCTAssertEqual(contribs.reduce(0) { $0 + $1.amount }, 12_000, accuracy: 0.01,
                       "порция всё равно собрана — иначе лишняя неделя не оплачена")
        XCTAssertEqual(contribs.map(\.incomeId), [long.id],
                       "собирать больше не с чего: приход своего спринта")
    }

    // MARK: Платёж «без подготовки» (С3): недостача заявляется, недели не гнутся

    func testUnpreparedPaymentDeclaresShortfall() {
        // Платёж 30 000 в спринте от 5-го: приход 50 000 − 30 000 = 20 000
        // на две полные порции по 12 000 не хватает — недостача 4 000 (П9).
        let school = Article(id: "школа", name: "школа",
                             kind: .payment(amount: 30_000, date: CivilDate(2027, 7, 19),
                                            monthlyDay: nil, prepared: false))
        // Вход 10 июля: июньский спринт вне плана, излишки прошлых приходов
        // не резервируются — платёж живёт только из прихода своего спринта (С3).
        let plan = makePlan(articles: [school], entryDate: CivilDate(2027, 7, 10))
        let r = PlanEngine.recompute(plan, today: CivilDate(2027, 7, 10), horizonMonths: 1)

        let sprintStart = CivilDate(2027, 7, 10)
        // Недельные не гнутся никогда (П9): обе финнедели — полная порция
        let w1 = r.recommendation.weeks.first { $0.start == sprintStart }!
        let w2 = r.recommendation.weeks.first { $0.start == sprintStart.adding(days: 7) }!
        XCTAssertEqual(w1.amount, 12_000, accuracy: 0.01)
        XCTAssertEqual(w2.amount, 12_000, accuracy: 0.01)
        // Недостача заявлена с точной цифрой и датой (П9). Цифра — 7 000: 4 000
        // от платежа без подготовки (С3) и 3 000 — доля дополнительной финнедели
        // сентябрьского длинного спринта, которую этот приход собирает заранее (С9).
        let shortfall = r.recommendation.shortfalls.first
        XCTAssertEqual(shortfall?.date, sprintStart.adding(days: 7))
        XCTAssertEqual(shortfall?.amount ?? 0, 7_000, accuracy: 0.01)
        // Платёж оплачен из прихода своего спринта
        let paid = r.recommendation.contributions.filter { $0.needId == "школа" }
        XCTAssertEqual(paid.reduce(0) { $0 + $1.amount }, 30_000, accuracy: 0.01)
        XCTAssertEqual(paid.first?.incomeId, "5@2027-07-05")
    }

    // MARK: Пропущенная раскладка (С15а)

    func testMissedLayoutKeepsOnlyDeclaredContributions() {
        let insurance = Article(id: "страховка", name: "страховка",
                                kind: .payment(amount: 24_000, date: CivilDate(2027, 8, 25),
                                               monthlyDay: nil, prepared: true))
        // Раскладка прихода 5 июля пропущена; человек подтвердил, что взнос страховки
        // 8 000 был отложен. Недобор уходит в общую балансировку будущих приходов.
        let missed = ConfirmedLayout.missed(
            incomeId: "5@2027-07-05",
            keptContributions: [Contribution(needId: "страховка", incomeId: "5@2027-07-05", amount: 8_000)])
        let plan = makePlan(articles: [insurance], confirmed: [missed])
        let r = PlanEngine.recompute(plan, today: CivilDate(2027, 7, 21), horizonMonths: 2)

        XCTAssertEqual(plan.collected(articleId: "страховка"), 8_000, accuracy: 0.01,
                       "отложенное засчитано как собранное")
        let future = r.recommendation.contributions
            .filter { $0.needId == "страховка" }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(future, 16_000, accuracy: 0.01,
                       "недобор перераспределён по оставшимся приходам (П6–П8)")
        XCTAssertFalse(r.occurrences.contains { $0.id == "5@2027-07-05" },
                       "пропущенный приход не восстанавливается задним числом")
    }
}
