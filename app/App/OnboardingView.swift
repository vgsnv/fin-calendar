import SwiftUI
import FinCalendarCore

/// Вход (МП18–МП21, spec/screens/entry.md): три шага, цель — меньше пяти минут.
/// Плана ещё нет — всё состояние локальное (@State); план создаётся одним вызовом
/// `completeOnboarding` в самом конце. Возврат назад свободный, введённое не теряется.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var step = 1
    @State private var phase = EntryPhase.steps

    // Шаг 1 — приходы (черновики строк, МП5).
    @State private var incomes: [EntryIncomeDraft] = [EntryIncomeDraft(day: 10)]
    @State private var thirdIncomeNote = false

    // Шаг 2 — статьи (черновой список, в план попадёт при завершении).
    @State private var articles: [Article] = []
    @State private var showArticleForm = false
    @State private var editingArticle: Article?

    // Шаг 3 — неделя и граница финнедели.
    @State private var weekText = ""
    @State private var weekBoundary = 6   // суббота — рекомендация С13
    @State private var ceiling = 0.0
    @FocusState private var weekFocused: Bool

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch phase {
            case .steps:
                steps.transition(.opacity)
            case .computing:
                EntryComputingView().transition(.opacity)
            case .done:
                summary.transition(.opacity)
            }
        }
    }

    // MARK: Каркас шагов

    private var steps: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Group {
                switch step {
                case 1:
                    ScrollView { step1.padding(20) }
                case 2:
                    step2
                default:
                    ScrollView { step3.padding(20) }
                }
            }
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .sheet(isPresented: $showArticleForm) {
            ArticleFormView(onSave: { articles.append($0) })
        }
        .sheet(item: $editingArticle) { article in
            // Правка черновика: статья заменяется в локальном списке, плана ещё нет.
            ArticleFormView(existing: article, onSave: { updated in
                if let i = articles.firstIndex(where: { $0.id == updated.id }) {
                    articles[i] = updated
                }
            })
        }
    }

    private var header: some View {
        ZStack {
            Cap("шаг \(step) из 3")
            if step > 1 {
                HStack {
                    Button {
                        withAnimation(Theme.ease(0.24)) { step -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("назад").font(.sans(15))
                        }
                        .foregroundStyle(Theme.text2)
                        .padding(.trailing, 12)
                        .tapPadded(visualHeight: 20)
                    }
                    Spacer()
                }
            }
        }
    }

    private var footer: some View {
        Button(action: advance) {
            Text(step == 3 ? "Посчитать" : "Дальше")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.caliper(.primary))
        .disabled(advanceDisabled)
    }

    private var advanceDisabled: Bool {
        switch step {
        case 1:
            return !(incomes.contains { $0.amount > 0 } && !duplicateDays)
        case 2:
            return false
        default:
            let week = parsedWeek
            return !(week > 0 && model.fits(weekPortion: week, incomes: builtIncomes(),
                                            articles: articles, weekBoundary: weekBoundary))
        }
    }

    private func advance() {
        if step < 3 {
            withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
        } else {
            startComputing()
        }
    }

    // MARK: Шаг 1 · Приходы (МП18)

    private var step1: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleBlock("Когда приходят деньги?",
                       "Суммы примерные. Вносить весь доход не нужно — только то, из чего живёте.")
            ForEach($incomes) { $row in
                EntryIncomeCard(row: $row,
                                placeholder: namePlaceholder(id: row.id),
                                canDelete: incomes.count > 1,
                                onDelete: { removeIncome(id: row.id) })
            }
            if duplicateDays {
                Text("Приходы в одно число месяца сетка не различает — поставьте разные числа.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.text3)
            }
            // Кнопка видна всегда — отказ третьему приходу честный, не молчаливый (К5).
            Button(action: addIncome) {
                Text("+ приход")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.caliper(.secondary))
            if thirdIncomeNote {
                Text("С тремя и более приходами сетка от дат не строится — таким приходам нужен общий календарь, он появится в следующей версии.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.text3)
            }
        }
    }

    private var duplicateDays: Bool {
        let days = incomes.filter { $0.amount > 0 }.map(\.day)
        return Set(days).count != days.count
    }

    private func addIncome() {
        if incomes.count >= 2 {
            withAnimation { thirdIncomeNote = true }
        } else {
            withAnimation {
                incomes.append(EntryIncomeDraft(day: incomes.first?.day == 25 ? 10 : 25))
                thirdIncomeNote = false
            }
        }
    }

    private func removeIncome(id: UUID) {
        guard incomes.count > 1 else { return }   // без приходов метода нет
        withAnimation {
            incomes.removeAll { $0.id == id }
            thirdIncomeNote = false
        }
    }

    private func namePlaceholder(id: UUID) -> String {
        guard incomes.count >= 2 else { return "Зарплата" }
        return incomes.firstIndex { $0.id == id } == 0 ? "Аванс" : "Зарплата"
    }

    private func builtIncomes() -> [PlannedIncome] {
        incomes.filter { $0.amount > 0 }.map { row in
            let trimmed = row.name.trimmingCharacters(in: .whitespaces)
            let name = trimmed.isEmpty ? namePlaceholder(id: row.id) : trimmed
            return PlannedIncome(anchor: Anchor(day: row.day, rule: row.rule, name: name),
                                 plannedAmount: row.amount)
        }
    }

    // MARK: Шаг 2 · Статьи (МП19)

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock("Что вы уже знаете о будущих тратах?",
                       "Страховка, кредит, подарки, техника — всё, что уже известно. Суммы можно примерные.")
                .padding(.horizontal, 20)
                .padding(.top, 20)
            if articles.isEmpty {
                Text("Можно пропустить: план без статей тоже считается.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            List {
                ForEach(articles, id: \.id) { article in
                    Button { editingArticle = article } label: { articleRow(article) }
                        .listRowBackground(Theme.surfaceRaised)
                        .listRowSeparatorTint(Theme.lineSoft)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                articles.removeAll { $0.id == article.id }
                            } label: {
                                Label("Убрать", systemImage: "xmark")
                            }
                            .tint(Theme.text3)
                        }
                }
                Button { showArticleForm = true } label: {
                    Text("+ статья")
                        .font(.sans(15, .medium))
                        .foregroundStyle(Theme.text)
                        .tapRow()
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surfaceRaised)
                .listRowSeparatorTint(Theme.lineSoft)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func articleRow(_ article: Article) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(article.name)
                    .font(.sans(16))
                    .foregroundStyle(Theme.text)
                Text(articleNote(article))
                    .font(.mono(12))
                    .foregroundStyle(Theme.text3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.iconMuted)
        }
        .padding(.vertical, 2)
        .tapRow()
    }

    /// Строка по виду статьи (articles.md): платёж · замысел · фонд · еженедельные.
    private func articleNote(_ article: Article) -> String {
        switch article.kind {
        case .payment(let amount, let date, let monthlyDay, _):
            if let day = monthlyDay {
                return "\(RU.money(amount)) · к \(day)-му ежемесячно"
            }
            return "\(RU.money(amount)) · к \(date.day) \(RU.monthsGen[date.month - 1])"
        case .intent(let target, let monthlySpeed):
            return "\(RU.money(target)) · по \(RU.money(monthlySpeed)) в месяц"
        case .fund(let monthlySpeed):
            return "\(RU.money(monthlySpeed)) в месяц"
        case .weekly(let portion):
            return "\(RU.money(portion)) в неделю"
        }
    }

    // MARK: Шаг 3 · Недельные деньги (МП20)

    private var step3: some View {
        let week = parsedWeek
        let fits = week > 0 && model.fits(weekPortion: week, incomes: builtIncomes(),
                                          articles: articles, weekBoundary: weekBoundary)
        return VStack(alignment: .leading, spacing: 12) {
            titleBlock("Сколько стоит неделя вашей жизни?")

            // Крупный readout Caliper: гротеск с табличными цифрами, капс-подпись.
            VStack(spacing: 6) {
                TextField("0", text: $weekText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.sans(34, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .focused($weekFocused)
                Cap("в неделю")
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .caliperCard()
            // Тап по любому месту карточки открывает клавиатуру.
            .tapFocuses($weekFocused)

            // Живая проверка: молчаливого урезания не существует (МП20);
            // «не помещается» — критичное, signal.
            if week > 0 {
                Text(fits
                     ? "помещается · потолок около \(RU.money(ceiling)) в неделю"
                     : "не помещается · потолок около \(RU.money(ceiling))")
                    .font(.mono(12, medium: true))
                    .foregroundStyle(fits ? Theme.text2 : Theme.signal)
            }
            Button {
                weekText = RU.money(ceiling)
            } label: {
                Text("посчитать за меня")
                    .font(.sans(13, .semibold))
                    .foregroundStyle(Theme.text2)
                    .tapPadded(visualHeight: 16)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Cap("неделя начинается с")
                CaliperSegmented(selection: $weekBoundary,
                                 options: (1...7).map { ($0, RU.days[$0 - 1]) })
                Text("неделя начнётся с дорогих выходных при полной порции")
                    .font(.sans(12))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.top, 8)
        }
        .onAppear(perform: recalcCeiling)
        .onChange(of: weekBoundary) { recalcCeiling() }
    }

    private var parsedWeek: Double {
        Double(weekText.replacingOccurrences(of: " ", with: "")) ?? 0
    }

    private func recalcCeiling() {
        ceiling = model.maxFittingWeek(incomes: builtIncomes(), articles: articles,
                                       weekBoundary: weekBoundary)
    }

    // MARK: Завершение (МП21)

    private func startComputing() {
        withAnimation(.easeOut(duration: 0.3)) { phase = .computing }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.4)) { phase = .done }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Посчитано.")
                    .font(.sans(28, .semibold))
                    .tracking(-0.28)
                    .foregroundStyle(Theme.text)
                if let d = nearestIncomeDate() {
                    Text("Ближайший приход — \(d.day) \(RU.monthsGen[d.month - 1]): с него начнётся первый спринт.")
                        .font(.sans(16))
                        .foregroundStyle(Theme.text2)
                }
                Text("Неделя: \(RU.money(parsedWeek)) ₽.")
                    .font(.sans(16))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text2)
            }
            Button {
                model.completeOnboarding(incomes: builtIncomes(), articles: articles,
                                         weekPortion: parsedWeek, weekBoundary: weekBoundary)
            } label: {
                Text("Открыть план")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.caliper(.primary))
        }
        .padding(24)
    }

    /// Простая оценка ближайшего прихода: минимальная дата не раньше сегодня
    /// среди номинальных дней приходов текущего и следующего месяца (дни 1–28
    /// существуют в любом месяце, перенос СВ2 здесь не учитывается).
    private func nearestIncomeDate() -> CivilDate? {
        let today = model.today
        let days = incomes.filter { $0.amount > 0 }.map(\.day)
        return days.map { d -> CivilDate in
            let sameMonth = CivilDate(today.year, today.month, d)
            if sameMonth >= today { return sameMonth }
            let (y, m) = today.month == 12 ? (today.year + 1, 1) : (today.year, today.month + 1)
            return CivilDate(y, m, d)
        }
        .min()
    }

    // MARK: Общие куски

    private func titleBlock(_ title: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.sans(22, .semibold))
                .tracking(-0.22)
                .foregroundStyle(Theme.text)
            if let caption {
                Text(caption)
                    .font(.sans(13))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: Фаза входа

private enum EntryPhase {
    case steps, computing, done
}

// MARK: Черновик строки прихода

private struct EntryIncomeDraft: Identifiable {
    let id = UUID()
    var name = ""
    var day: Int
    var amountText = ""
    var rule = TransferRule.lastWorkingDayBefore   // умолчание СВ2
    var ruleOpen = false

    var amount: Double {
        Double(amountText.replacingOccurrences(of: " ", with: "")) ?? 0
    }
}

// MARK: Карточка прихода

private struct EntryIncomeCard: View {
    @Binding var row: EntryIncomeDraft
    let placeholder: String
    let canDelete: Bool
    let onDelete: () -> Void

    private enum Field { case name, amount }
    @FocusState private var focus: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(placeholder, text: $row.name)
                    .font(.sans(16, .medium))
                    .foregroundStyle(Theme.text)
                    .focused($focus, equals: .name)
                    .tapFocuses($focus, equals: .name)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.iconMuted)
                            .tapTarget()
                    }
                }
            }
            Divider().overlay(Theme.lineSoft)
            HStack {
                Text("число месяца")
                    .font(.sans(15))
                    .foregroundStyle(Theme.text3)
                Spacer()
                DayGridButton(day: $row.day)   // 1–28, СВ1
            }
            HStack {
                Text("сумма")
                    .font(.sans(15))
                    .foregroundStyle(Theme.text3)
                    .fixedSize()
                TextField("0", text: $row.amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.mono(17, medium: true))
                    .foregroundStyle(Theme.text)
                    .focused($focus, equals: .amount)
                    .frame(maxWidth: .infinity)
            }
            // Тап по подписи «сумма» и пустому месту строки тоже фокусирует поле.
            .tapFocuses($focus, equals: .amount)
            // Раскрывашка на Button: DisclosureGroup глотает первый тап при фокусе в поле.
            Button {
                withAnimation(Theme.ease()) { row.ruleOpen.toggle() }
            } label: {
                HStack {
                    Text("если выпадает на выходной")
                        .font(.sans(13))
                        .foregroundStyle(Theme.text3)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.iconMuted)
                        .rotationEffect(.degrees(row.ruleOpen ? 180 : 0))
                }
                .tapRow(minHeight: 36)
            }
            .buttonStyle(.plain)
            if row.ruleOpen {
                VStack(spacing: 0) {
                    ruleOption("последний рабочий день до", .lastWorkingDayBefore)
                    ruleOption("первый рабочий день после", .firstWorkingDayAfter)
                    ruleOption("не переносится", TransferRule.none)
                }
            }
        }
        .padding(16)
        .caliperCard()
    }

    /// Вариант правила переноса — строка-кнопка с точкой выбора.
    private func ruleOption(_ title: String, _ rule: TransferRule) -> some View {
        Button {
            row.rule = rule
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(row.rule == rule ? Theme.fill : Theme.lineStrong,
                                  lineWidth: 1.5)
                    .background(Circle().fill(row.rule == rule ? Theme.fill : .clear).padding(4))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.sans(14))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Анимация расчёта (~1,5 с): полоски ленты проступают каскадом

private struct EntryComputingView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                HStack(spacing: 8) {
                    Circle()
                        .fill(i % 4 == 0 ? Theme.text : Color.clear)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surfaceRaised)
                        .strokeBorder(i % 4 == 0 ? Theme.lineStrong : Theme.line,
                                      lineWidth: 1)
                        .frame(height: 36)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(Theme.ease(0.4).delay(Double(i) * 0.13), value: appeared)
            }
            Cap("лента строится")
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
                .animation(Theme.ease(0.4).delay(0.3), value: appeared)
        }
        .padding(32)
        .onAppear { appeared = true }
    }
}
