import Foundation
import FinCalendarCore

/// Вью-модель ленты: превращает горизонт движка в строки финнедель и спринты.
struct TapeModel {
    struct Day: Identifiable {
        let date: CivilDate
        let isToday: Bool
        let isPast: Bool
        let incomeMarker: Bool
        let paymentMarker: Bool

        var id: Int { date.dayNumber }
    }

    struct Week: Identifiable {
        let start: CivilDate
        let days: [Day]
        let isCurrent: Bool
        let isPast: Bool
        let thinAmount: Double?    // порция, если неделя тонкая (П9)
        let isExtra: Bool          // дополнительная финнеделя длинного спринта (С9)

        var id: Int { start.dayNumber }
    }

    struct SprintVM: Identifiable {
        let start: CivilDate
        let incomeName: String
        let incomeAmount: Double
        let occupancy: Double      // доля прихода, уходящая в статьи (полоска занятости)
        let weeks: [Week]
        let isLong: Bool
        let callToAction: Bool     // «Разложить»: плановая дата наступила (МП26)
        let blindNote: Bool        // спринт стартовал неразложенным — план слеп (С12)

        var id: Int { start.dayNumber }
    }

    let today: CivilDate
    let namedWeek: Double
    let sprints: [SprintVM]

    static func demo() -> TapeModel {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let today = CivilDate(c.year!, c.month!, c.day!)
        let entry = CivilDate(dayNumber: today.dayNumber - 21)

        let plan = Plan(
            namedWeek: 12_000,
            weekBoundary: 6,
            incomes: [PlannedIncome(anchor: Anchor(day: 5, name: "Аванс"), plannedAmount: 50_000),
                      PlannedIncome(anchor: Anchor(day: 20, name: "Зарплата"), plannedAmount: 55_000)],
            entryDate: entry,
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

        let horizon = PlanEngine.recompute(plan, today: today, horizonMonths: 3)
        return TapeModel(today: today, plan: plan, horizon: horizon)
    }

    init(today: CivilDate, plan: Plan, horizon: HorizonRecommendation) {
        self.today = today
        self.namedWeek = plan.namedWeek

        let rec = horizon.recommendation
        let weekByStart = Dictionary(uniqueKeysWithValues: rec.weeks.map { ($0.start, $0) })

        // Даты платежей для маркеров
        var paymentDates = Set<CivilDate>()
        for a in plan.articles {
            if case .payment(_, let date, let monthly, _) = a.kind {
                if let day = monthly {
                    var d = CivilDate(today.year, today.month, day)
                    for _ in 0..<4 {
                        paymentDates.insert(d)
                        let (ny, nm) = d.month == 12 ? (d.year + 1, 1) : (d.year, d.month + 1)
                        d = CivilDate(ny, nm, day)
                    }
                } else {
                    paymentDates.insert(date)
                }
            }
        }
        let incomeDates = Set(horizon.occurrences.map(\.factDate))

        // Спринты — по уникальным стартам
        var seen = Set<Int>()
        var sprints: [SprintVM] = []
        let sorted = horizon.occurrences.sorted { $0.sprintStart < $1.sprintStart }
        let firstDue = sorted.first { $0.factDate <= today }

        for occ in sorted where seen.insert(occ.sprintStart.dayNumber).inserted {
            var weeks: [Week] = []
            for w in 0..<occ.sprintWeeks {
                let start = occ.sprintStart.adding(days: w * 7)
                let amount = weekByStart[start]
                let days = (0..<7).map { i -> Day in
                    let d = start.adding(days: i)
                    return Day(date: d,
                               isToday: d == today,
                               isPast: d < today,
                               incomeMarker: incomeDates.contains(d),
                               paymentMarker: paymentDates.contains(d))
                }
                let isCurrent = start <= today && today <= start.adding(days: 6)
                weeks.append(Week(start: start, days: days,
                                  isCurrent: isCurrent,
                                  isPast: start.adding(days: 6) < today,
                                  thinAmount: (amount?.isThin == true) ? amount?.amount : nil,
                                  isExtra: occ.isLongSprint && w == occ.sprintWeeks - 1))
            }
            let contributed = rec.contributions
                .filter { $0.incomeId == occ.id }
                .reduce(0) { $0 + $1.amount }
            sprints.append(SprintVM(
                start: occ.sprintStart,
                incomeName: occ.anchorDay == 5 ? "Аванс" : "Зарплата",
                incomeAmount: occ.plannedAmount,
                occupancy: occ.plannedAmount > 0 ? min(1, contributed / occ.plannedAmount) : 0,
                weeks: weeks,
                isLong: occ.isLongSprint,
                callToAction: occ.id == firstDue?.id,
                blindNote: occ.id == firstDue?.id && occ.sprintStart <= today))
        }
        self.sprints = sprints
    }
}
