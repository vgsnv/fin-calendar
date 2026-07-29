import Foundation
import FinCalendarCore

/// Вью-модель ленты: застывшие спринты из подтверждённых раскладок (П12, МП16)
/// плюс неразложенное будущее из горизонта пересчёта.
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
        let isConfirmed: Bool      // раскладка подтверждена — числа застыли (П12)
        let callToAction: Bool     // «Разложить»: плановая дата наступила (МП26)
        let blindNote: Bool        // спринт стартовал неразложенным — план слеп (С12)
        let occurrence: IncomeOccurrence

        var id: Int { start.dayNumber }
    }

    let today: CivilDate
    let namedWeek: Double
    let sprints: [SprintVM]

    init(model: AppModel) {
        let plan = model.plan
        let horizon = model.horizon
        let today = model.today
        self.today = today
        self.namedWeek = plan.namedWeek

        let rec = horizon.recommendation
        let weekByStart = Dictionary(uniqueKeysWithValues: rec.weeks.map { ($0.start, $0) })

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
        var incomeDates = Set(horizon.occurrences.map(\.factDate))
        for l in plan.confirmed { if let d = l.factDate { incomeDates.insert(d) } }

        func makeDays(_ start: CivilDate) -> [Day] {
            (0..<7).map { i in
                let d = start.adding(days: i)
                return Day(date: d, isToday: d == today, isPast: d < today,
                           incomeMarker: incomeDates.contains(d),
                           paymentMarker: paymentDates.contains(d))
            }
        }
        func makeWeek(start: CivilDate, thin: Double?, isExtra: Bool) -> Week {
            Week(start: start, days: makeDays(start),
                 isCurrent: start <= today && today <= start.adding(days: 6),
                 isPast: start.adding(days: 6) < today,
                 thinAmount: thin, isExtra: isExtra)
        }

        var sprints: [SprintVM] = []

        // Застывшие спринты — из подтверждённых раскладок (МП16)
        for layout in plan.confirmed {
            guard let start = layout.sprintStart, let weeksCount = layout.sprintWeeks,
                  let factDate = layout.factDate else { continue }
            let weeks = (0..<weeksCount).map { w -> Week in
                let ws = start.adding(days: w * 7)
                let amount = layout.weekAmounts.first { $0.start == ws }?.amount
                let thin = (amount != nil && amount! < plan.namedWeek - 0.5) ? amount : nil
                return makeWeek(start: ws, thin: thin,
                                isExtra: layout.isLong && w == weeksCount - 1)
            }
            let contributed = layout.contributions.reduce(0) { $0 + $1.amount }
            let anchorDay = Int(layout.incomeId.split(separator: "@").first ?? "") ?? 0
            let occ = IncomeOccurrence(id: layout.incomeId, anchorDay: anchorDay,
                                       factDate: factDate, sprintStart: start,
                                       sprintWeeks: weeksCount, plannedAmount: layout.factAmount,
                                       isLongSprint: layout.isLong)
            sprints.append(SprintVM(start: start,
                                    incomeName: layout.incomeName,
                                    incomeAmount: layout.factAmount,
                                    occupancy: layout.factAmount > 0
                                        ? min(1, contributed / layout.factAmount) : 0,
                                    weeks: weeks, isLong: layout.isLong,
                                    isConfirmed: true, callToAction: false, blindNote: false,
                                    occurrence: occ))
        }

        // Неразложенное будущее — из горизонта
        var seen = Set<Int>(sprints.map(\.id))
        let sorted = horizon.occurrences.sorted { $0.sprintStart < $1.sprintStart }
        let firstDue = sorted.first { $0.factDate <= today }

        for occ in sorted where seen.insert(occ.sprintStart.dayNumber).inserted {
            let weeks = (0..<occ.sprintWeeks).map { w -> Week in
                let ws = occ.sprintStart.adding(days: w * 7)
                let amount = weekByStart[ws]
                return makeWeek(start: ws,
                                thin: (amount?.isThin == true) ? amount?.amount : nil,
                                isExtra: occ.isLongSprint && w == occ.sprintWeeks - 1)
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
                isConfirmed: false,
                callToAction: occ.id == firstDue?.id,
                blindNote: occ.id == firstDue?.id && occ.sprintStart <= today,
                occurrence: occ))
        }
        self.sprints = sprints.sorted { $0.start < $1.start }
    }
}
