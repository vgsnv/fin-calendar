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
        let isExtra: Bool          // дополнительная финнеделя длинного спринта (С9)
        var issueAmount: Double? = nil  // порция выдачи — только в разложенном спринте (С16)

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
        var isMissed: Bool = false // прошёл без раскладки (С15а) — прошлое, только чтение
        // Раньше даты входа: спринт на сетке есть, в нём ничего — ни сумм, ни маркеров.
        var isPrehistory: Bool = false
        var shortfall: Shortfall? = nil // план не сходится в этом спринте (П9)
        let occurrence: IncomeOccurrence

        var id: Int { start.dayNumber }
    }

    let today: CivilDate
    let sprints: [SprintVM]

    /// `pastMonths` — глубина прошлого на сетке; будущее задаёт горизонт пересчёта.
    init(plan: Plan, horizon: HorizonRecommendation, today: CivilDate, pastMonths: Int) {
        self.today = today

        let rec = horizon.recommendation

        /// Имя прихода по опорной дате — как AppModel.incomeName, но от снимка плана.
        func incomeName(anchorDay: Int) -> String {
            plan.incomes.first { $0.anchor.day == anchorDay }?.anchor.name
                ?? "приход \(anchorDay)-го"
        }

        // Конец ленты — дальний край горизонта: разметка обязана доходить до него,
        // пустот и дат-заглушек на ленте не существует (МП23).
        let tapeEnd = horizon.occurrences
            .map { $0.sprintStart.adding(days: $0.sprintWeeks * 7) }
            .max() ?? today

        var paymentDates = Set<CivilDate>()
        for a in plan.articles {
            if case .payment(_, let date, let monthly, _) = a.kind {
                if let day = monthly {
                    var d = CivilDate(today.year, today.month, day)
                    while d <= tapeEnd {
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
        func makeWeek(start: CivilDate, isExtra: Bool) -> Week {
            Week(start: start, days: makeDays(start),
                 isCurrent: start <= today && today <= start.adding(days: 6),
                 isPast: start.adding(days: 6) < today,
                 isExtra: isExtra)
        }

        var sprints: [SprintVM] = []

        // Застывшие спринты — из подтверждённых раскладок (МП16)
        for layout in plan.confirmed {
            guard let start = layout.sprintStart, let weeksCount = layout.sprintWeeks,
                  let factDate = layout.factDate else { continue }
            let weeks = (0..<weeksCount).map { w -> Week in
                let ws = start.adding(days: w * 7)
                let isExtra = layout.isLong && w == weeksCount - 1
                var week = makeWeek(start: ws, isExtra: isExtra)
                // Дополнительная неделя оплачена из плана (С9): выдача — полные порции.
                // Раскладки, застывшие до еженедельных статей, лишнюю неделю не
                // замораживали — фолбэк на текущую сумму порций.
                week.issueAmount = layout.weekAmounts.first { $0.start == ws }?.amount
                    ?? (isExtra ? plan.weeklySum : nil)
                return week
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
                makeWeek(start: occ.sprintStart.adding(days: w * 7),
                         isExtra: occ.isLongSprint && w == occ.sprintWeeks - 1)
            }
            let contributed = rec.contributions
                .filter { $0.incomeId == occ.id }
                .reduce(0) { $0 + $1.amount }
            let sprintEnd = occ.sprintStart.adding(days: occ.sprintWeeks * 7)
            sprints.append(SprintVM(
                start: occ.sprintStart,
                incomeName: incomeName(anchorDay: occ.anchorDay),
                incomeAmount: occ.plannedAmount,
                occupancy: occ.plannedAmount > 0 ? min(1, contributed / occ.plannedAmount) : 0,
                weeks: weeks,
                isLong: occ.isLongSprint,
                isConfirmed: false,
                callToAction: occ.id == firstDue?.id,
                blindNote: occ.id == firstDue?.id && occ.sprintStart <= today,
                shortfall: rec.shortfalls.first { $0.date >= occ.sprintStart && $0.date < sprintEnd },
                occurrence: occ))
        }

        // Прошлое ленты: сетка уходит вглубь на ту же глубину, что и будущее (МП23) —
        // мотать можно куда угодно. Спринты после даты входа, прошедшие без раскладки,
        // остаются видимыми (С15а): менять там нечего, восстановления задним числом нет.
        // Раньше даты входа плана не существовало: спринт на сетке есть, в нём ничего.
        if !plan.incomes.isEmpty {
            let calendar = OwnCalendar(weekBoundary: plan.weekBoundary,
                                       anchors: plan.incomes.map(\.anchor),
                                       production: plan.production)
            let entry = plan.entryDate
            var fromY = today.year, fromMo = today.month - pastMonths - 1
            while fromMo < 1 { fromMo += 12; fromY -= 1 }
            let toM = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
            let amountByDay = Dictionary(uniqueKeysWithValues:
                plan.incomes.map { ($0.anchor.day, $0.plannedAmount) })
            let grid = calendar.sprints(fromYear: fromY, fromMonth: fromMo,
                                        toYear: toM.0, toMonth: toM.1)
            for s in grid where s.end < today {
                guard seen.insert(s.start.dayNumber).inserted,
                      let day = s.anchorDays.first, let fact = s.factDates.first else { continue }
                let weeks = (0..<s.weeks).map { w in
                    makeWeek(start: s.start.adding(days: w * 7),
                             isExtra: s.isLong && w == s.weeks - 1)
                }
                let occ = IncomeOccurrence(id: "\(day)@\(fact)", anchorDay: day, factDate: fact,
                                           sprintStart: s.start, sprintWeeks: s.weeks,
                                           plannedAmount: amountByDay[day] ?? 0,
                                           isLongSprint: s.isLong)
                let prehistory = s.end < entry
                sprints.append(SprintVM(start: s.start,
                                        incomeName: prehistory ? "" : incomeName(anchorDay: day),
                                        incomeAmount: prehistory ? 0 : (amountByDay[day] ?? 0),
                                        occupancy: 0, weeks: weeks, isLong: s.isLong,
                                        isConfirmed: false, callToAction: false,
                                        blindNote: false, isMissed: !prehistory,
                                        isPrehistory: prehistory,
                                        occurrence: occ))
            }
        }
        self.sprints = sprints.sorted { $0.start < $1.start }
    }
}
