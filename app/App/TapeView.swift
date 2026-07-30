import SwiftUI
import FinCalendarCore

/// Лента — центр интерфейса (МП6, МП22–МП26): строка — финнеделя, спринты очерчены.
struct TapeView: View {
    @Environment(AppModel.self) private var model
    @State private var layoutTarget: SprintTarget?
    @State private var detailTarget: SprintTarget?
    @State private var dayTarget: DayTarget?
    @State private var showSettings = false
    /// Спринты, чьи карточки сейчас построены лентой: по ним видно, ушёл ли
    /// текущий спринт с экрана (для чипа возврата).
    @State private var visibleSprints: Set<Int> = []

    var body: some View {
        let tape = model.tape
        let current = tape.sprints.first { !$0.weeks.allSatisfy(\.isPast) }
        ScrollViewReader { proxy in
            // Шапка закреплена, а не лежит первым элементом прокрутки: лента уходит
            // на годы в обе стороны, и «верх ленты» с тихим входом в настройки
            // (tape.md) иначе недостижим — до него надо мотать пять лет назад.
            VStack(spacing: 0) {
                header(tape)
                ScrollView {
                // Лента длинная (5 лет в каждую сторону, МП23): спринты строятся
                // по мере подхода, иначе весь горизонт рендерился бы разом.
                LazyVStack(spacing: 10) {
                    ForEach(tape.sprints) { sprint in
                        SprintCard(sprint: sprint, tape: tape,
                                   openLayout: { layoutTarget = SprintTarget(occurrence: sprint.occurrence) },
                                   openDetail: { detailTarget = SprintTarget(occurrence: sprint.occurrence) },
                                   openDay: { dayTarget = DayTarget(date: $0) })
                            .id(sprint.id)
                            .onAppear { visibleSprints.insert(sprint.id) }
                            .onDisappear { visibleSprints.remove(sprint.id) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
            // Прошлое выше по ленте — стартуем с текущего спринта.
            .onAppear {
                if let current {
                    proxy.scrollTo(current.id, anchor: .top)
                }
            }
            // Возврат к текущей финнеделе — единственный плавающий элемент ленты
            // (tape.md): лента глубока, домотавшемуся нужен путь обратно.
            .overlay(alignment: .bottom) {
                if let current {
                    let away = !visibleSprints.isEmpty && !visibleSprints.contains(current.id)
                    TodayChip(isAbove: current.id < (visibleSprints.min() ?? current.id)) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(current.id, anchor: .top)
                        }
                    }
                    .opacity(away ? 1 : 0)
                    .offset(y: away ? 0 : 10)
                    .allowsHitTesting(away)
                    .animation(.easeInOut(duration: 0.2), value: away)
                }
            }
            }
        }
        .background(Theme.bg)
        #if DEBUG
        .overlay(alignment: .bottomTrailing) { DebugDayChip() }
        #endif
        .fullScreenCover(item: $layoutTarget) { target in
            LayoutSheetView(occurrence: target.occurrence)
        }
        .sheet(item: $detailTarget) { target in
            SprintDetailView(occurrence: target.occurrence)
        }
        .sheet(item: $dayTarget) { target in
            DayArticlesSheet(date: target.date)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func header(_ tape: TapeModel) -> some View {
        HStack {
            Text(String(tape.today.year))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.textMuted)
                    .tapTarget()
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
}

/// Чип возврата к текущей финнеделе (tape.md): виден только когда текущий спринт
/// ушёл с экрана. Тише призыва «Разложить» — тот остаётся главным действием
/// экрана (МП26): контур и бумажный фон, а не залитый акцент.
private struct TodayChip: View {
    let isAbove: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isAbove ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("сегодня")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Theme.surface)
                    .strokeBorder(Theme.line, lineWidth: 1)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
            )
            .tapPadded(visualHeight: 36)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
    }
}

private struct SprintTarget: Identifiable {
    let occurrence: IncomeOccurrence
    var id: String { occurrence.id }
}

private struct DayTarget: Identifiable {
    let date: CivilDate
    var id: Int { date.dayNumber }
}

#if DEBUG
/// Сдвиг «сегодня» — только для тестирования (DEBUG): в рабочей сборке
/// этого элемента не существует. Тап по дате — возврат к реальному дню.
private struct DebugDayChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Button { model.debugShiftDay(by: -1) } label: {
                Image(systemName: "minus")
                    .frame(width: 40, height: 36)
            }
            Button { model.debugResetDay() } label: {
                Text("\(model.today.day) \(RU.monthsGen[model.today.month - 1])")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 74)
                    .foregroundStyle(model.isTimeShifted ? Color.white : Theme.textMuted)
            }
            Button { model.debugShiftDay(by: 1) } label: {
                Image(systemName: "plus")
                    .frame(width: 40, height: 36)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(model.isTimeShifted ? .white : Theme.textMuted)
        .background(Capsule().fill(model.isTimeShifted ? Theme.accent : Theme.subtle)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2))
        .padding(.trailing, 16)
        // Выше чипа возврата: тестовый сдвиг дня не должен его перекрывать.
        .padding(.bottom, 80)
    }
}
#endif

struct SprintCard: View {
    let sprint: TapeModel.SprintVM
    let tape: TapeModel
    let openLayout: () -> Void
    let openDetail: () -> Void
    let openDay: (CivilDate) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            boundary
            // Полоска занятости — про деньги прихода; до входа денег в плане не было.
            if !sprint.isPrehistory { occupancyBand }
            // Недостача обязана быть видна без тапа (П9); цвет нейтральный (МП8).
            if let s = sprint.shortfall {
                Text("план не сходится · к \(s.date.day) \(RU.monthsGen[s.date.month - 1]) не хватает \(RU.money(s.amount))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(sprint.weeks) { week in
                // До входа открывать нечего — ни спринт, ни статьи дня.
                WeekRow(week: week, onDayTap: sprint.isPrehistory ? nil : openDay)
                if week.isExtra, !sprint.isPrehistory {
                    Text("дополнительная неделя · оплачена из плана")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                issueRow(week)
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
        .opacity((sprint.isConfirmed || sprint.isMissed || sprint.isPrehistory)
                 && sprint.weeks.allSatisfy(\.isPast) ? 0.6 : 1)
        .contentShape(Rectangle())
        // До даты входа открывать нечего: ни раскладки, ни рекомендации.
        .onTapGesture { if !sprint.isPrehistory { openDetail() } }
    }

    /// Выдача (С16, МП32): тихое действие у текущей финнедели разложенного спринта.
    @ViewBuilder
    private func issueRow(_ week: TapeModel.Week) -> some View {
        if sprint.isConfirmed, week.isCurrent, let amount = week.issueAmount {
            if model.isIssued(weekStart: week.start) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("выдано · \(RU.money(amount))")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
            } else {
                // День выдачи — самое заметное на карточке: полноширинная кнопка.
                Button {
                    model.issueWeek(weekStart: week.start)
                } label: {
                    HStack {
                        // Одно имя события на кнопке, в уведомлении и в спеке (МП12г).
                        Text("Новая неделя")
                        Spacer()
                        Text("выдать \(RU.money(amount))")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var boundary: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // До даты входа у спринта есть только границы: имени прихода и суммы
                // тогда не существовало, придумывать их задним числом нельзя (П5).
                Text(sprint.isPrehistory
                     ? "\(sprint.start.day) \(RU.monthsGen[sprint.start.month - 1])"
                     : "\(sprint.start.day) \(RU.monthsGen[sprint.start.month - 1]) · \(sprint.incomeName)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(sprint.isPrehistory ? Theme.textMuted : Theme.text)
                if !sprint.isPrehistory { subtitle }
            }
            Spacer()
            if sprint.callToAction {
                Button(action: openLayout) {
                    Text("Разложить")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if sprint.isConfirmed {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("разложено · \(RU.money(sprint.incomeAmount))")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
        } else if sprint.isMissed {
            Text("раскладки не было · план \(RU.money(sprint.incomeAmount))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        } else {
            Text(sprint.callToAction
                 ? "пришло \(RU.money(sprint.incomeAmount)) · ждёт раскладки"
                 : "план \(RU.money(sprint.incomeAmount))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
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
    var onDayTap: ((CivilDate) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(week.days) { day in
                // Тап по дате — статьи этого дня (список и добавление).
                // Рамка внутри метки, а не снаружи кнопки: снаружи тап ловили бы
                // только цифры, а ячейка визуально шире — отсюда промахи по датам.
                Button { onDayTap?(day.date) } label: {
                    DayCell(day: day, week: week)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onDayTap == nil)
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

// MARK: Статьи дня — тап по дате на ленте

/// Список статей, попадающих на дату: разовые платежи этой даты и ежемесячные
/// этого числа; отсюда же добавляется новая статья к этой дате.
struct DayArticlesSheet: View {
    let date: CivilDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editingArticle: Article?
    @State private var addingArticle = false

    private var articles: [Article] {
        model.plan.articles.filter { a in
            guard case .payment(_, let d, let monthlyDay, _) = a.kind else { return false }
            if let day = monthlyDay { return day == date.day }
            return d == date
        }
    }

    private var incomeNote: String? {
        guard let occ = model.horizon.occurrences.first(where: { $0.factDate == date })
        else { return nil }
        return "\(model.incomeName(anchorDay: occ.anchorDay)) · придёт \(RU.money(occ.plannedAmount))"
    }

    /// Дата в прошлом — только чтение: ни правки, ни добавления.
    private var isPast: Bool { date < model.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(date.day) \(RU.monthsGen[date.month - 1])")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .tapTarget()
                }
            }

            if let incomeNote {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    Text(incomeNote)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }

            if articles.isEmpty {
                Text("статей на эту дату нет")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(articles) { article in
                        Button { editingArticle = article } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(article.name)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.text)
                                    Text(note(article))
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                if !isPast {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textFaint)
                                }
                            }
                            .padding(.vertical, 11)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPast)
                        if article.id != articles.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                    .strokeBorder(Theme.line, lineWidth: 1))
            }

            if isPast {
                Text("прошлое — только чтение")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
            } else {
                Button { addingArticle = true } label: {
                    Text("+ статья к этой дате")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.bg)
        .presentationDetents([.medium, .large])
        .sheet(item: $editingArticle) { ArticleFormView(existing: $0) }
        .sheet(isPresented: $addingArticle) { ArticleFormView(prefillDate: date) }
    }

    private func note(_ article: Article) -> String {
        guard case .payment(let amount, _, let monthlyDay, _) = article.kind else { return "" }
        if monthlyDay != nil { return "\(RU.money(amount)) · ежемесячно" }
        return "\(RU.money(amount)) · платёж к дате"
    }
}
