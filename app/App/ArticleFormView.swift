import SwiftUI
import FinCalendarCore

/// Форма статьи — одна на создание и правку (МП15; spec/screens/articles.md;
/// spec/screens/entry.md, шаг 2). Меню видов нет: вид следует из заполненных
/// полей. Живая подпись говорит, что получается; живое последствие (МП11) —
/// что станет с планом, ещё до сохранения.
struct ArticleFormView: View {
    let existing: Article?
    let onSave: ((Article) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var draftId: String
    @State private var name: String
    @State private var amountText: String
    @State private var hasDate: Bool
    @State private var dueDate: Date
    @State private var monthly: Bool
    @State private var monthlyDay: Int
    @State private var prepared: Bool
    @State private var speedText: String
    @State private var isPaused: Bool

    private enum Field { case name, amount, speed }
    @FocusState private var focus: Field?

    init(existing: Article? = nil, prefillDate: CivilDate? = nil,
         onSave: ((Article) -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave

        var initialName = "", initialAmount = "", initialSpeed = ""
        var initialHasDate = false, initialMonthly = false, initialPrepared = true
        var initialDay = 1
        var initialDue = Date()

        // Новая статья с ленты: дата уже выбрана тапом по дню.
        if existing == nil, let prefillDate {
            initialHasDate = true
            initialDue = Self.date(from: prefillDate)
        }

        if let a = existing {
            initialName = a.name
            switch a.kind {
            case .payment(let amount, let date, let day, let prep):
                initialAmount = RU.money(amount)
                initialHasDate = true
                initialDue = Self.date(from: date)
                initialMonthly = day != nil
                initialDay = day ?? min(date.day, 28)
                initialPrepared = prep
            case .intent(let target, let speed):
                initialAmount = RU.money(target)
                initialSpeed = RU.money(speed)
            case .fund(let speed):
                initialSpeed = RU.money(speed)
            }
        }

        _draftId = State(initialValue: existing?.id ?? UUID().uuidString)
        _name = State(initialValue: initialName)
        _amountText = State(initialValue: initialAmount)
        _hasDate = State(initialValue: initialHasDate)
        _dueDate = State(initialValue: initialDue)
        _monthly = State(initialValue: initialMonthly)
        _monthlyDay = State(initialValue: initialDay)
        _prepared = State(initialValue: initialPrepared)
        _speedText = State(initialValue: initialSpeed)
        _isPaused = State(initialValue: existing?.paused ?? false)
    }

    var body: some View {
        let draft = draftArticle
        let preview: HorizonRecommendation? =
            onSave == nil ? draft.map { previewResult(for: $0) } : nil

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                card {
                    TextField("имя", text: $name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .focused($focus, equals: .name)
                        .padding(.horizontal, 14)
                        .tapFocuses($focus, equals: .name, minHeight: 48)
                    Divider().overlay(Theme.line)
                    numberRow("сумма", text: $amountText, field: .amount)
                }

                // Поля-развилки (МП15): дата и скорость никогда не участвуют вместе,
                // поэтому заполненная развилка прячет вторую. Введённое не стирается —
                // очистите одну развилку, и вторая вернётся.
                if hasDate || parsedSpeed == nil {
                    card { dateSection }
                }

                if !hasDate {
                    card { numberRow("скорость в месяц", text: $speedText, field: .speed) }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(kindCaption(draft: draft, preview: preview))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                    // Скорость выше цели легальна (движок режет взнос до остатка),
                    // но почти наверняка опечатка — говорим, что получится.
                    if let draft, case .intent(let target, let speed) = draft.kind,
                       speed > target {
                        Text("скорость больше цели: лишнего не отложится — замысел закроется, как только соберётся \(RU.money(target))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    if let preview {
                        consequenceLine(preview.recommendation)
                    }
                }
                .padding(.horizontal, 4)

                saveButton
                editActions
            }
            .padding(20)
        }
        .background(Theme.bg)
        .animation(.easeInOut(duration: 0.15), value: hasDate)
        .animation(.easeInOut(duration: 0.15), value: monthly)
        .animation(.easeInOut(duration: 0.15), value: isPayment)
        .animation(.easeInOut(duration: 0.15), value: parsedSpeed != nil)
        .onChange(of: monthly) { _, on in
            if on { monthlyDay = min(Self.civil(from: dueDate).day, 28) }
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(existing == nil ? "Новая статья" : "Статья")
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
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var subtitle: String {
        if existing == nil { return "заполните, что известно — вид определится сам" }
        if onSave != nil { return "правка черновика — план создастся в конце входа" }
        return isPaused ? "на паузе · правка действует от сегодня"
                        : "правка действует от сегодня"
    }

    // MARK: Поля даты (платёж: повторение и подготовка, С3)

    @ViewBuilder
    private var dateSection: some View {
        SwitchRow(isOn: $hasDate) {
            Text("к дате").font(.system(size: 15)).foregroundStyle(Theme.text)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)

        if hasDate {
            if !monthly {
                Divider().overlay(Theme.line)
                HStack {
                    Text("дата").font(.system(size: 15)).foregroundStyle(Theme.textMuted)
                    Spacer()
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .tint(Theme.accent)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
            }

            Divider().overlay(Theme.line)
            SwitchRow(isOn: $monthly) {
                Text("повторяется ежемесячно")
                    .font(.system(size: 15)).foregroundStyle(Theme.text)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)

            if monthly {
                Divider().overlay(Theme.line)
                HStack {
                    Text("число месяца")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    DayGridButton(day: $monthlyDay, suffix: "-го")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
            }

            if isPayment && !monthly {
                Divider().overlay(Theme.line)
                SwitchRow(isOn: $prepared) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("готовиться заранее")
                            .font(.system(size: 15)).foregroundStyle(Theme.text)
                        Text(prepared ? "взнос соберётся к дате"
                                      : "оплата из прихода своего спринта")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
            }
        }
    }

    // MARK: Кнопки

    private var saveButton: some View {
        Button(action: save) {
            Text("Сохранить")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(canSave ? Color.white : Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(canSave ? Theme.accent : Theme.line))
        }
        .disabled(!canSave)
        .padding(.top, 4)
    }

    /// Правка: пауза для фондов и замыслов (П8) и закрытие решением человека (С4а).
    /// Во входе (onSave) плана ещё нет — эти действия не показываются,
    /// черновик убирается свайпом в списке.
    @ViewBuilder
    private var editActions: some View {
        if let existing, onSave == nil {
            card {
                if canPause {
                    Button {
                        let newValue = !isPaused
                        model.setPaused(articleId: existing.id, paused: newValue)
                        isPaused = newValue
                    } label: {
                        actionRow(isPaused ? "Возобновить" : "Пауза",
                                  note: isPaused ? "скорость вернётся со следующей раскладки"
                                                 : "скорость временно ноль, строка останется")
                    }
                    Divider().overlay(Theme.line)
                }
                Button {
                    model.closeArticle(articleId: existing.id)
                    dismiss()
                } label: {
                    actionRow("Закрыть статью", note: "собранное выйдет из плана")
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: Живая подпись вида и последствие (МП11)

    private func kindCaption(draft: Article?, preview: HorizonRecommendation?) -> String {
        guard let draft else { return "Заполните сумму, дату или скорость" }
        switch draft.kind {
        case .payment(_, let date, let day, _):
            if let day { return "Платёж: каждый месяц, к \(day)-му числу" }
            return "Платёж: соберём к \(date.day) \(RU.monthsGen[date.month - 1])"
        case .intent(let target, let speed):
            if let finish = preview?.intentFinish[draft.id] {
                return "Замысел: накопится ~к \(monthsDative[finish.month - 1])"
            }
            return "Замысел: \(RU.money(target)), по \(RU.money(speed)) в месяц"
        case .fund(let speed):
            return "Фонд: \(RU.money(speed)) в месяц, без конца"
        }
    }

    @ViewBuilder
    private func consequenceLine(_ rec: Recommendation) -> some View {
        if rec.fits {
            Text("план помещается · неделя останется \(RU.money(model.plan.namedWeek))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
        } else if let s = rec.shortfalls.first {
            Text("не помещается: к \(s.date.day) \(RU.monthsGen[s.date.month - 1]) не хватает \(RU.money(s.amount))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: Черновик статьи

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { draftKind != nil && !trimmedName.isEmpty }

    private var isPayment: Bool {
        if case .payment = draftKind { return true }
        return false
    }

    /// Платёж не ставится на паузу — его гнут только сдвигом срока (П8).
    private var canPause: Bool {
        guard let existing else { return false }
        if case .payment = existing.kind { return false }
        return true
    }

    private var parsedAmount: Double? { Self.parse(amountText) }
    private var parsedSpeed: Double? { Self.parse(speedText) }

    /// Вид следует из заполненного (МП15): сумма и дата — платёж;
    /// сумма и скорость без даты — замысел; только скорость — фонд.
    /// Ежемесячный платёж всегда с подготовкой: движок иначе его не считает.
    private var draftKind: ArticleKind? {
        let amount = parsedAmount
        let speed = parsedSpeed
        if let amount, hasDate {
            return .payment(amount: amount,
                            date: Self.civil(from: dueDate),
                            monthlyDay: monthly ? monthlyDay : nil,
                            prepared: monthly ? true : prepared)
        }
        if let amount, let speed { return .intent(target: amount, monthlySpeed: speed) }
        if amount == nil, !hasDate, let speed { return .fund(monthlySpeed: speed) }
        return nil
    }

    private var draftArticle: Article? {
        guard let kind = draftKind else { return nil }
        return Article(id: draftId,
                       name: trimmedName.isEmpty ? "статья" : trimmedName,
                       kind: kind)
    }

    /// Последствие до сохранения (МП11). При правке существующая статья заменяется
    /// черновиком, чтобы её текущий вид не посчитался дважды; для новой — model.preview.
    private func previewResult(for article: Article) -> HorizonRecommendation {
        if existing != nil, model.plan.articles.contains(where: { $0.id == article.id }) {
            var temp = model.plan
            if let i = temp.articles.firstIndex(where: { $0.id == article.id }) {
                temp.articles[i] = article
            }
            return PlanEngine.recompute(temp, today: model.today,
                                        horizonMonths: AppModel.horizonMonths)
        }
        return model.preview(adding: article)
    }

    private func save() {
        guard let kind = draftKind, !trimmedName.isEmpty else { return }
        let article = Article(id: draftId, name: trimmedName, kind: kind, paused: isPaused)
        if let onSave {
            onSave(article)                  // вход: плана ещё нет (МП18–МП21)
        } else if existing == nil {
            model.addArticle(article)
        } else {
            model.updateArticle(article)
        }
        dismiss()
    }

    // MARK: Мелкие детали

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                .strokeBorder(Theme.line, lineWidth: 1))
    }

    private func numberRow(_ label: String, text: Binding<String>,
                           field: Field) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.textMuted)
                .fixedSize()
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused($focus, equals: field)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        // Тап по подписи и любому месту строки фокусирует поле.
        .tapFocuses($focus, equals: field, minHeight: 48)
    }

    private func actionRow(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.text)
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .tapRow()
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v
    }

    private static func civil(from date: Date) -> CivilDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return CivilDate(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    private static func date(from civil: CivilDate) -> Date {
        Calendar.current.date(from: DateComponents(year: civil.year,
                                                   month: civil.month,
                                                   day: civil.day)) ?? Date()
    }
}

/// Дательный падеж для «накопится ~к маю» (С5, articles.md).
private let monthsDative = ["январю", "февралю", "марту", "апрелю", "маю", "июню",
                            "июлю", "августу", "сентябрю", "октябрю", "ноябрю", "декабрю"]
