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
            Text("шаг \(step) из 3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            if step > 1 {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("назад").font(.system(size: 15))
                        }
                        .foregroundStyle(Theme.textMuted)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Theme.accent))
        }
        .disabled(advanceDisabled)
        .opacity(advanceDisabled ? 0.4 : 1)
    }

    private var advanceDisabled: Bool {
        switch step {
        case 1:
            return !(incomes.contains { $0.amount > 0 } && !duplicateDays)
        case 2:
            return false
        default:
            let week = parsedWeek
            return !(week > 0 && model.fits(namedWeek: week, incomes: builtIncomes(),
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
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
            // Кнопка видна всегда — отказ третьему приходу честный, не молчаливый (К5).
            Button(action: addIncome) {
                Text("+ приход")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
            }
            if thirdIncomeNote {
                Text("С тремя и более приходами сетка от дат не строится — таким приходам нужен общий календарь, он появится в следующей версии.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
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
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            List {
                ForEach(articles, id: \.id) { article in
                    Button { editingArticle = article } label: { articleRow(article) }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.line)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                articles.removeAll { $0.id == article.id }
                            } label: {
                                Label("Убрать", systemImage: "xmark")
                            }
                            .tint(Theme.textMuted)
                        }
                }
                Button { showArticleForm = true } label: {
                    Text("+ статья")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .tapRow()
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.line)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func articleRow(_ article: Article) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(article.name)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                Text(articleNote(article))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 2)
        .tapRow()
    }

    /// Строка по виду статьи (articles.md): платёж · замысел · фонд.
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
        }
    }

    // MARK: Шаг 3 · Повседневные деньги (МП20)

    private var step3: some View {
        let week = parsedWeek
        let fits = week > 0 && model.fits(namedWeek: week, incomes: builtIncomes(),
                                          articles: articles, weekBoundary: weekBoundary)
        return VStack(alignment: .leading, spacing: 12) {
            titleBlock("Сколько стоит неделя вашей жизни?")

            VStack(spacing: 4) {
                TextField("0", text: $weekText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("в неделю")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                .strokeBorder(Theme.line, lineWidth: 1))

            // Живая проверка: молчаливого урезания не существует (МП20).
            if week > 0 {
                Text(fits
                     ? "Помещается. Потолок — около \(RU.money(ceiling)) в неделю."
                     : "Не помещается: потолок — около \(RU.money(ceiling)).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(fits ? Theme.accent : Theme.textMuted)
            }
            Button {
                weekText = RU.money(ceiling)
            } label: {
                Text("посчитать за меня")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("неделя начинается с")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
                Picker("граница недели", selection: $weekBoundary) {
                    ForEach(1...7, id: \.self) { d in
                        Text(RU.days[d - 1]).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("неделя начнётся с дорогих выходных при полной порции")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
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
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let d = nearestIncomeDate() {
                    Text("Ближайший приход — \(d.day) \(RU.monthsGen[d.month - 1]): с него начнётся первый спринт.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                }
                Text("Неделя: \(RU.money(parsedWeek)) ₽.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
            }
            Button {
                model.completeOnboarding(incomes: builtIncomes(), articles: articles,
                                         namedWeek: parsedWeek, weekBoundary: weekBoundary)
            } label: {
                Text("Открыть план")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Theme.accent))
            }
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
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(placeholder, text: $row.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .tapTarget()
                    }
                }
            }
            Divider().overlay(Theme.line)
            HStack {
                Text("число месяца")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                DayGridButton(day: $row.day)   // 1–28, СВ1
            }
            HStack {
                Text("сумма")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                // Поле тянется на всю оставшуюся строку — тап-зона широкая.
                TextField("0", text: $row.amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
            }
            // Раскрывашка на Button: DisclosureGroup глотает первый тап при фокусе в поле.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { row.ruleOpen.toggle() }
            } label: {
                HStack {
                    Text("если выпадает на выходной")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .rotationEffect(.degrees(row.ruleOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
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
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
            .strokeBorder(Theme.line, lineWidth: 1))
    }

    /// Вариант правила переноса — строка-кнопка с точкой выбора.
    private func ruleOption(_ title: String, _ rule: TransferRule) -> some View {
        Button {
            row.rule = rule
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(row.rule == rule ? Theme.accent : Theme.line, lineWidth: 1.5)
                    .background(Circle().fill(row.rule == rule ? Theme.accent : .clear).padding(4))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 14))
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
                        .fill(i % 4 == 0 ? Theme.accent : Color.clear)
                        .frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(i % 4 == 0 ? Theme.accentSoft : Theme.surface)
                        .strokeBorder(Theme.line, lineWidth: 1)
                        .frame(height: 36)
                }
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.94)
                .animation(.easeOut(duration: 0.4).delay(Double(i) * 0.13), value: appeared)
            }
            Text("лента строится")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
        }
        .padding(32)
        .onAppear { appeared = true }
    }
}
