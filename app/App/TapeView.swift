import SwiftUI
import FinCalendarCore

/// Лента — центр интерфейса (МП6, МП22–МП26): строка — финнеделя, спринты очерчены.
struct TapeView: View {
    let model: TapeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                ForEach(model.sprints) { sprint in
                    SprintCard(sprint: sprint, model: model)
                        .id(sprint.id)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            Text(String(model.today.year))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 17))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
}

struct SprintCard: View {
    let sprint: TapeModel.SprintVM
    let model: TapeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            boundary
            occupancyBand
            ForEach(sprint.weeks) { week in
                WeekRow(week: week, model: model)
                if let thin = week.thinAmount {
                    Text("тонкая неделя · \(RU.money(thin)) вместо \(RU.money(model.namedWeek))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                if week.isExtra {
                    Text("дополнительная неделя · оплачена из плана")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            if sprint.blindNote {
                Text("спринт идёт без раскладки — план слеп: выдач нет, взносы не собраны")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .strokeBorder(sprint.callToAction ? Theme.accent : Theme.line, lineWidth: 1)
        )
    }

    private var boundary: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(sprint.start.day) \(RU.monthsGen[sprint.start.month - 1]) · \(sprint.incomeName)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(sprint.callToAction
                     ? "пришло \(RU.money(sprint.incomeAmount)) · ждёт раскладки"
                     : "план \(RU.money(sprint.incomeAmount))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if sprint.callToAction {
                Text("Разложить")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accent))
            }
        }
    }

    private var occupancyBand: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accentSoft)
                Capsule().fill(Theme.accent)
                    .frame(width: max(4, geo.size.width * sprint.occupancy))
            }
        }
        .frame(height: 4)
        .padding(.bottom, 4)
    }
}

struct WeekRow: View {
    let week: TapeModel.Week
    let model: TapeModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                DayCell(day: day, week: week)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct DayCell: View {
    let day: TapeModel.Day
    let week: TapeModel.Week

    private var numberColor: Color {
        if day.isToday { return Theme.accent }
        if day.isPast || week.isPast { return Theme.textFaint }
        return Theme.text
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(RU.days[day.date.weekday - 1])
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
            Text(String(day.date.day))
                .font(.system(size: 15))
                .foregroundStyle(numberColor)
            ZStack {
                Circle().fill(.clear).frame(width: 5, height: 5)
                if day.incomeMarker {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                } else if day.paymentMarker {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.2)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(day.isToday ? Theme.accentSoft : .clear)
        )
    }
}

#Preview {
    TapeView(model: .demo())
}
