import SwiftUI
import FinCalendarCore

/// Настройки (МП35–МП36, spec/screens/settings.md): редактируются только исходные
/// параметры плана — производное не настраивается. Открывается шторкой с ленты.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    // Повседневные деньги
    @State private var weekText = ""
    // Приходы: правки живут локально до «Сохранить приходы»
    @State private var incomeDrafts: [IncomeDraft] = []
    @State private var thirdIncomeRefused = false
    // Начать заново
    @State private var showEraseDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                sectionTitle("Повседневные деньги")
                namedWeekCard
                sectionTitle("Приходы")
                incomesSection
                sectionTitle("Граница финнедели")
                boundaryCard
                sectionTitle("Производственный календарь")
                productionCard
                sectionTitle("Уведомления")
                notificationsCard
                sectionTitle("Начать заново")
                eraseCard
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .onAppear {
            weekText = RU.money(model.plan.namedWeek)
            incomeDrafts = model.plan.incomes.map(IncomeDraft.init)
        }
        .confirmationDialog("Начать заново", isPresented: $showEraseDialog,
                            titleVisibility: .visible) {
            Button("Стереть всё", role: .destructive) {
                model.eraseEverything()
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("План, история раскладок и настройки будут удалены безвозвратно. Это не перезапуск, а стирание.")
        }
    }

    // MARK: Шапка и каркас

    private var header: some View {
        HStack {
            Text("Настройки")
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
        .padding(.bottom, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 10)
            .padding(.horizontal, 4)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                .strokeBorder(Theme.line, lineWidth: 1))
    }

    private func primaryButton(_ title: String, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(disabled ? Theme.textFaint : Theme.accent))
        }
        .disabled(disabled)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
    }

    // MARK: Повседневные деньги (МП36)

    private var parsedWeek: Double? {
        Double(weekText.replacingOccurrences(of: " ", with: ""))
    }

    private var weekSaveDisabled: Bool {
        guard let value = parsedWeek, value > 0 else { return true }
        return abs(value - model.plan.namedWeek) < 0.5
    }

    private var namedWeekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("на финнеделю")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize()
                        TextField("", text: $weekText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                    }
                    if let value = parsedWeek {
                        let fits = model.fits(namedWeek: value)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(fits ? Theme.accent : Theme.textFaint)
                                .frame(width: 6, height: 6)
                            Text(fits ? "помещается" : "не помещается")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(fits ? Theme.accent : Theme.textMuted)
                        }
                    }
                }
                .padding(14)
            }
            primaryButton("Сохранить", disabled: weekSaveDisabled) {
                guard let value = parsedWeek else { return }
                model.setNamedWeek(value)
                weekText = RU.money(value)
            }
            footnote("действует со следующей раскладки, текущий спринт доживает на прежней порции")
        }
    }

    // MARK: Приходы (П5, П11, К5)

    private var duplicateDays: Bool {
        Set(incomeDrafts.map(\.day)).count != incomeDrafts.count
    }

    private var incomesChanged: Bool {
        model.plan.incomes.map(IncomeDraft.init).map(\.signature) != incomeDrafts.map(\.signature)
    }

    private var incomesSaveDisabled: Bool {
        incomeDrafts.isEmpty
            || incomeDrafts.contains { $0.planned == nil }
            || duplicateDays
            || !incomesChanged
    }

    private var incomesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            card {
                ForEach($incomeDrafts) { $draft in
                    IncomeEditor(draft: $draft,
                                 removable: incomeDrafts.count > 1,
                                 remove: { removeIncome(draft.id) })
                    Divider().overlay(Theme.line)
                }
                addIncomeRow
            }
            if duplicateDays {
                footnote("два прихода в одно число не различить — выберите разные числа")
            }
            primaryButton("Сохранить приходы", disabled: incomesSaveDisabled) { saveIncomes() }
            footnote("сетка перестроится от сегодня; прошлое неизменно")
        }
    }

    private var addIncomeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if incomeDrafts.count >= 2 {
                    thirdIncomeRefused = true
                } else {
                    incomeDrafts.append(IncomeDraft(day: freeDay()))
                    thirdIncomeRefused = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Добавить приход")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .tapRow()
            }
            .buttonStyle(.plain)
            if thirdIncomeRefused {
                footnote("Больше двух приходов — это уже общий календарь. В этой версии календарь только свой.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func freeDay() -> Int {
        let taken = Set(incomeDrafts.map(\.day))
        for d in [25, 10, 5, 20, 15] where !taken.contains(d) { return d }
        return (1...28).first { !taken.contains($0) } ?? 1
    }

    private func removeIncome(_ id: UUID) {
        guard incomeDrafts.count > 1 else { return }  // последний приход не удаляется
        incomeDrafts.removeAll { $0.id == id }
        thirdIncomeRefused = false
    }

    private func saveIncomes() {
        let planned = incomeDrafts.compactMap(\.planned)
        guard !planned.isEmpty, planned.count == incomeDrafts.count, !duplicateDays else { return }
        model.setIncomes(planned)
        incomeDrafts = model.plan.incomes.map(IncomeDraft.init)
        thirdIncomeRefused = false
    }

    // MARK: Граница финнедели (К7, МП36) — в этой версии не меняется

    private var boundaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("день границы")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text(weekdayFullNames[model.plan.weekBoundary - 1])
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                }
                footnote("смена границы — перезапуск системы; появится в следующей версии")
            }
            .padding(14)
        }
    }

    // MARK: Производственный календарь (СВ5) — заглушка

    private var productionCard: some View {
        card {
            Text("встроенный справочник · появится в следующей версии")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    // MARK: Уведомления (МП33) — сохраняются сразу

    private var notificationsCard: some View {
        card {
            toggleRow("пора раскладка", note: "приход пришёл и ждёт раскладки",
                      isOn: Binding(
                        get: { model.plan.notifyLayout },
                        set: { model.setNotifications(layout: $0, issue: model.plan.notifyIssue) }))
            Divider().overlay(Theme.line)
            toggleRow("выдача", note: "началась финнеделя — пора выдать порцию",
                      isOn: Binding(
                        get: { model.plan.notifyIssue },
                        set: { model.setNotifications(layout: model.plan.notifyLayout, issue: $0) }))
        }
    }

    private func toggleRow(_ title: String, note: String, isOn: Binding<Bool>) -> some View {
        SwitchRow(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    // MARK: Начать заново — единственная деструктивная операция

    private var eraseCard: some View {
        card {
            Button { showEraseDialog = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Начать заново")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("полное стирание локальных данных")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

// MARK: Черновик прихода

private struct IncomeDraft: Identifiable {
    let id = UUID()
    var name: String
    var day: Int
    var rule: TransferRule
    var amountText: String

    init(_ income: PlannedIncome) {
        name = income.anchor.name
        day = income.anchor.day
        rule = income.anchor.rule
        amountText = RU.money(income.plannedAmount)
    }

    init(day: Int) {
        name = ""
        self.day = day
        rule = .lastWorkingDayBefore
        amountText = ""
    }

    var amount: Double? {
        Double(amountText.replacingOccurrences(of: " ", with: ""))
    }

    /// Готовый приход; nil — сумма ещё не названа.
    var planned: PlannedIncome? {
        guard (1...28).contains(day), let amount, amount > 0 else { return nil }
        return PlannedIncome(anchor: Anchor(day: day, rule: rule, name: name),
                             plannedAmount: amount)
    }

    /// Для сравнения «есть ли несохранённые правки».
    var signature: String {
        "\(day)|\(rule.rawValue)|\(name)|\(Int((amount ?? -1).rounded()))"
    }
}

private struct IncomeEditor: View {
    @Binding var draft: IncomeDraft
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("имя прихода", text: $draft.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                if removable {
                    Button(action: remove) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textMuted)
                            .tapTarget()
                    }
                }
            }
            HStack(spacing: 10) {
                Text("число месяца")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                DayGridButton(day: $draft.day, suffix: "-го")
            }
            HStack {
                Text("ожидаемая сумма")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                TextField("0", text: $draft.amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Полные имена дней недели, ISO: 1 = понедельник … 7 = воскресенье.
private let weekdayFullNames = ["понедельник", "вторник", "среда", "четверг",
                                "пятница", "суббота", "воскресенье"]
