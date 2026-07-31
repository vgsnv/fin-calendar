import XCTest
@testable import FinCalendarCore

/// Инварианты балансировки на случайных планах: ровность свободных денег (П6б)
/// перекладывает взносы, поэтому деньги обязаны сходиться до рубля, сроки —
/// соблюдаться (П7), свободные деньги — не уходить в минус (П6а), а порции
/// еженедельных — оставаться полными и неподвижными (С9, П9).
final class BalancingInvariantsTests: XCTestCase {

    /// Воспроизводимый генератор: расчёт должен быть честен на любом плане, а падение —
    /// повторяемо.
    private struct Rng {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    func testMoneyAddsUpDatesHoldFreeMoneyStaysPositive() {
        var rng = Rng(state: 20_270_705)
        let balancer = Balancer()

        for _ in 0..<300 {
            // Три месяца по два прихода: 5-го и 20-го, суммы вразнобой.
            var incomes: [BalancingIncome] = []
            for month in 7...9 {
                for day in [5, 20] {
                    incomes.append(BalancingIncome(
                        id: "\(day)@\(month)", factDate: CivilDate(2027, month, day),
                        amount: Double(10_000 + rng.next(50) * 1_000),
                        nominalDate: CivilDate(2027, month, day)))
                }
            }
            // Финнедели — полные порции еженедельной статьи (С9), прочие статьи —
            // со случайными сроками и суммами.
            let weekStarts = (0..<12).map { CivilDate(2027, 7, 3).adding(days: $0 * 7) }
            var needs: [Need] = weekStarts.map {
                Need(id: "неделя@\($0)", name: "неделя", kind: .weeklyPortion,
                     due: $0, amount: 12_000)
            }
            for i in 0..<rng.next(8) {
                let due = CivilDate(2027, 7, 1).adding(days: 5 + rng.next(85))
                let kind: NeedKind = [.payment, .fundSpeed, .intentSpeed][rng.next(3)]
                needs.append(Need(id: "статья-\(i)", name: "статья-\(i)", kind: kind,
                                  due: due, amount: Double(1_000 + rng.next(30) * 1_000)))
            }

            let rec = balancer.recommend(incomes: incomes, needs: needs)

            // Деньги не появляются и не пропадают: приходы + недостачи = потребности + свободные.
            let income = incomes.reduce(0) { $0 + $1.amount }
            let missing = rec.shortfalls.reduce(0) { $0 + $1.amount }
            let demand = needs.reduce(0) { $0 + $1.amount }
            let free = rec.freeMoney.values.reduce(0, +)
            XCTAssertEqual(income + missing, demand + free, accuracy: 0.01)

            // Финнедели рекомендации — полные порции всегда (П9), как бы ни кормились.
            for w in rec.weeks { XCTAssertEqual(w.amount, 12_000, accuracy: 0.01) }

            // Взнос назначен только приходу, успевающему до срока (П7).
            let dueById = Dictionary(uniqueKeysWithValues: needs.map { ($0.id, $0.due) })
            let kindById = Dictionary(uniqueKeysWithValues: needs.map { ($0.id, $0.kind) })
            let dateById = Dictionary(uniqueKeysWithValues: incomes.map { ($0.id, $0.factDate) })
            for c in rec.contributions {
                XCTAssertLessThanOrEqual(dateById[c.incomeId]!, dueById[c.needId]!,
                                         "взнос ушёл назад во времени (П7)")
            }
            // Свободные деньги — излишек, а не долг (П6а).
            for (id, value) in rec.freeMoney {
                XCTAssertGreaterThan(value, -0.01, "\(id) ушёл в минус")
            }
            // Статья собрана целиком либо ровно на величину своей недостачи (П9).
            for need in needs {
                let paid = rec.contributions.filter { $0.needId == need.id }.reduce(0) { $0 + $1.amount }
                XCTAssertLessThanOrEqual(paid, need.amount + 0.01)
            }
            // Ровность внутри месяца доведена до упора (П6б): если у соседа по месяцу
            // свободных денег больше, значит переносить на него уже нечего — все
            // подвижные взносы бедного приход-богач не успевает по срокам (П7).
            // Порции еженедельных неподвижны по построению (С9) и не считаются.
            for rich in incomes {
                for poor in incomes where poor.month == rich.month
                    && rec.freeMoney[rich.id]! > rec.freeMoney[poor.id]! + 0.01 {
                    let movable = rec.contributions.filter {
                        $0.incomeId == poor.id && kindById[$0.needId] != .weeklyPortion
                            && dueById[$0.needId]! >= rich.factDate
                    }.reduce(0) { $0 + $1.amount }
                    XCTAssertLessThan(movable, 0.01,
                                      "взнос \(poor.id) успевал перейти на \(rich.id) — ровность не доведена")
                }
            }
        }
    }
}
