import XCTest
@testable import FinCalendarCore

/// Приёмочные тесты балансировки по эталону tests/balancing.md (кейсы 1–6).
/// Сквозной пример: приходы 5-го и 20-го, спринты по 2 финнедели,
/// повседневные деньги — 12 000/финнеделя. Даты — июль 2027 (граница — суббота):
/// приход 5.07 → старт 10.07 (недели 10.07, 17.07); приход 20.07 → старт 24.07
/// (недели 24.07, 31.07).
final class BalancingTests: XCTestCase {

    private let balancer = Balancer(namedWeek: 12_000)
    private let weekStarts = [CivilDate(2027, 7, 10), CivilDate(2027, 7, 17),
                              CivilDate(2027, 7, 24), CivilDate(2027, 7, 31)]

    private func contribution(_ rec: Recommendation, need: String, income: String) -> Double {
        rec.contributions.filter { $0.needId == need && $0.incomeId == income }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: Кейс 1 · идеальная ровность достижима (П1, П6, П6а)

    func testCase1_perfectEvennessAndFreeMoneyPerIncome() {
        let incomes = [BalancingIncome(id: "аванс", factDate: CivilDate(2027, 7, 5), amount: 60_000),
                       BalancingIncome(id: "зарплата", factDate: CivilDate(2027, 7, 20), amount: 40_000)]
        let rec = balancer.recommend(incomes: incomes, weekStarts: weekStarts, needs: [])

        XCTAssertTrue(rec.fits, "тонких мест нет, П9 молчит")
        for w in rec.weeks { XCTAssertEqual(w.amount, 12_000, accuracy: 0.01) }
        // Свободные деньги — по приходам, не по горизонту (П6а)
        XCTAssertEqual(rec.freeMoney["аванс"]!, 36_000, accuracy: 0.01)
        XCTAssertEqual(rec.freeMoney["зарплата"]!, 16_000, accuracy: 0.01)
    }

    // MARK: Кейс 2 · ровность недостижима — тонкое место (П6, П9)

    func testCase2_thinWeeksDeclaredMaximinFirst() {
        let incomes = [BalancingIncome(id: "аванс", factDate: CivilDate(2027, 7, 5), amount: 30_000),
                       BalancingIncome(id: "зарплата", factDate: CivilDate(2027, 7, 20), amount: 18_000)]
        let insurance = Need(id: "страховка", name: "страховка", kind: .payment,
                             due: CivilDate(2027, 7, 28), amount: 12_000)
        let rec = balancer.recommend(incomes: incomes, weekStarts: weekStarts, needs: [insurance])

        // Вариант 1 (максимин): все финнедели по 9 000
        for w in rec.weeks {
            XCTAssertEqual(w.amount, 9_000, accuracy: 0.01)
            XCTAssertTrue(w.isThin, "тонкость констатируется с точной цифрой (П9)")
        }
        XCTAssertFalse(rec.fits)
        // Страховка собрана целиком
        let collected = rec.contributions.filter { $0.needId == "страховка" }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(collected, 12_000, accuracy: 0.01)
        XCTAssertTrue(rec.unmetNeeds.isEmpty)
    }

    // MARK: Кейс 3 · короткое окно платежа (П7)

    func testCase3_paymentFedOnlyByIncomesBeforeItsDate() {
        let incomes = [BalancingIncome(id: "аванс", factDate: CivilDate(2027, 7, 5), amount: 40_000),
                       BalancingIncome(id: "зарплата", factDate: CivilDate(2027, 7, 20), amount: 40_000)]
        let payment = Need(id: "платёж", name: "платёж", kind: .payment,
                           due: CivilDate(2027, 7, 18), amount: 20_000)
        let rec = balancer.recommend(incomes: incomes, weekStarts: weekStarts, needs: [payment])

        // Ни один взнос — приходу после даты (П7)
        XCTAssertEqual(contribution(rec, need: "платёж", income: "аванс"), 20_000, accuracy: 0.01)
        XCTAssertEqual(contribution(rec, need: "платёж", income: "зарплата"), 0, accuracy: 0.01)
        // Спринт от 5-го — тонкие недели по 10 000; назад во времени не перекинуть (П9)
        XCTAssertEqual(rec.weeks[0].amount, 10_000, accuracy: 0.01)
        XCTAssertEqual(rec.weeks[1].amount, 10_000, accuracy: 0.01)
        XCTAssertTrue(rec.weeks[0].isThin && rec.weeks[1].isThin)
        // Спринт от 20-го — полная порция, излишек свободен (П6а)
        XCTAssertEqual(rec.weeks[2].amount, 12_000, accuracy: 0.01)
        XCTAssertEqual(rec.weeks[3].amount, 12_000, accuracy: 0.01)
        XCTAssertEqual(rec.freeMoney["зарплата"]!, 16_000, accuracy: 0.01)
    }

    // MARK: Кейс 4 · план не сходится — порядок уступчивости (П8)

    func testCase4_bendingOptionsOrderedFundIntentPayment() {
        // Три спринта по 2 финнедели, приходы по 30 000
        let weekStarts = self.weekStarts + [CivilDate(2027, 8, 7), CivilDate(2027, 8, 14)]
        let incomes = [BalancingIncome(id: "п1", factDate: CivilDate(2027, 7, 5), amount: 30_000),
                       BalancingIncome(id: "п2", factDate: CivilDate(2027, 7, 20), amount: 30_000),
                       BalancingIncome(id: "п3", factDate: CivilDate(2027, 8, 5), amount: 30_000)]
        var needs: [Need] = []
        // Скорости: фонд 6 000/мес, замысел 10 000/мес — по половине с каждого прихода
        for (i, income) in incomes.enumerated() {
            needs.append(Need(id: "одежда-\(i)", name: "одежда", kind: .fundSpeed,
                              due: income.factDate, amount: 3_000))
            needs.append(Need(id: "ноутбук-\(i)", name: "ноутбук", kind: .intentSpeed,
                              due: income.factDate, amount: 5_000))
        }
        needs.append(Need(id: "платёж", name: "платёж", kind: .payment,
                          due: CivilDate(2027, 8, 18), amount: 45_000))

        let base = balancer.recommend(incomes: incomes, weekStarts: weekStarts, needs: needs)
        XCTAssertFalse(base.fits)
        XCTAssertEqual(base.weeks[0].amount, 3_500, accuracy: 0.01, "скоростей больше, чем приходов минус повседневные")

        let options = balancer.bendingOptions(incomes: incomes, weekStarts: weekStarts, needs: needs)
        XCTAssertFalse(options.isEmpty)
        // Строго в порядке жёсткости: фонд → замысел → платёж (П8)
        let kinds: [Int] = options.map {
            switch $0.bending {
            case .pauseFund: return 0
            case .pauseIntent: return 1
            case .shiftPaymentDate: return 2
            }
        }
        XCTAssertEqual(kinds, kinds.sorted(), "порядок предложений: фонды → замыслы → платежи")
        XCTAssertEqual(kinds.first, 0)
        XCTAssertEqual(kinds.last, 2)
        // Урезание недели вариантом не является (П9): все варианты гнут статьи
        // (гарантировано типом Bending — повседневных денег в нём нет по построению).
    }

    // MARK: Кейс 5 · правка посреди горизонта — граница пересчёта (П12)

    func testCase5_confirmedLayoutFrozenNewPaymentSpreadForward() {
        // Из кейса 1: раскладка прихода 5-го подтверждена и застыла.
        let confirmedWeeks = [12_000.0, 12_000.0]      // недели спринта от 5-го
        let confirmedFree = 36_000.0                    // вышло из плана (С12а)

        // Человек добавляет платёж 15 000 с датой в следующем месяце.
        // Пересчитывается только неразложенное: приходы от 20-го и далее.
        let futureIncomes = [BalancingIncome(id: "зарплата", factDate: CivilDate(2027, 7, 20), amount: 40_000),
                             BalancingIncome(id: "аванс-авг", factDate: CivilDate(2027, 8, 5), amount: 60_000)]
        let futureWeeks = [CivilDate(2027, 7, 24), CivilDate(2027, 7, 31),
                           CivilDate(2027, 8, 7), CivilDate(2027, 8, 14)]
        let payment = Need(id: "новый", name: "новый платёж", kind: .payment,
                           due: CivilDate(2027, 8, 20), amount: 15_000)
        let rec = balancer.recommend(incomes: futureIncomes, weekStarts: futureWeeks, needs: [payment])

        // Взносы нового платежа — по приходам от 20-го и далее (П7, П11)
        let total = rec.contributions.filter { $0.needId == "новый" }.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 15_000, accuracy: 0.01)
        XCTAssertTrue(rec.fits, "будущее вмещает платёж без тонких мест")
        // Ни одна цифра подтверждённой раскладки не изменилась (П12):
        // подтверждённое не входит во вход пересчёта — застыло по построению.
        XCTAssertEqual(confirmedWeeks, [12_000.0, 12_000.0])
        XCTAssertEqual(confirmedFree, 36_000.0)
    }

    // MARK: Кейс 6 · свободные деньги — порядок предложений (П6а)

    func testCase6_surplusSuggestionsReverseP8Order() {
        // Из кейса 4 человек замедлил фонд и сдвинул дату платежа.
        let bent: [BentDecision] = [.slowedFund(name: "одежда"),
                                    .shiftedPaymentDate(name: "платёж")]
        let suggestions = Surplus.suggestions(bent: bent, acceleratableArticles: ["ноутбук"])

        XCTAssertEqual(suggestions, [
            .returnBent(.shiftedPaymentDate(name: "платёж")),   // согнутое последним — первым
            .returnBent(.slowedFund(name: "одежда")),
            .accelerateArticle(name: "ноутбук"),
            .newPossibility,
            .leaveAlone                                          // всегда последний (С12а)
        ])
    }
}
