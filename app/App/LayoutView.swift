import SwiftUI
import FinCalendarCore

/// Раскладка (МП27–МП30): два состояния — черновик с подтверждением
/// и чек-лист исполнения с отметками «перечислено».
struct LayoutSheetView: View {
    let occurrence: IncomeOccurrence
    /// Шаблон: приход ещё не наступил — раскладка только просматривается,
    /// подтверждение появится в день прихода.
    var template = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        if let confirmed = model.layout(for: occurrence.id) {
            ChecklistView(occurrence: occurrence, layout: confirmed, dismiss: { dismiss() })
        } else {
            DraftView(occurrence: occurrence, isTemplate: template, dismiss: { dismiss() })
        }
    }
}

// MARK: Черновик

private struct DraftView: View {
    let occurrence: IncomeOccurrence
    var isTemplate = false
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    @State private var factText: String = ""
    @State private var showSurplus = false

    private var factAmount: Double {
        Double(factText.replacingOccurrences(of: " ", with: "")) ?? occurrence.plannedAmount
    }

    private var draft: HorizonRecommendation {
        model.draft(for: occurrence.id, factAmount: factAmount)
    }

    var body: some View {
        let rec = draft.recommendation
        let rows = draftRows(rec)
        let free = rec.freeMoney[occurrence.id] ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if isTemplate { plannedRow } else { factField }
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        LayoutRow(name: row.name, note: row.note, amount: row.amount)
                        if row.id != rows.last?.id { Divider().overlay(Theme.lineSoft) }
                    }
                }
                .caliperCard()

                if free > 0.5 {
                    // Свободные деньги — тёмная «инструментальная» панель.
                    Button { showSurplus = true } label: {
                        HStack(spacing: 8) {
                            Text("свободные деньги")
                                .font(.sans(14, .medium))
                                .foregroundStyle(Theme.inkFg)
                            Spacer()
                            Text(RU.money(free))
                                .font(.mono(14, medium: true))
                                .foregroundStyle(Theme.inkFg)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(16)
                        .inkPanel()
                    }
                }

                shortfallNotes(rec)

                if isTemplate {
                    Text("Это шаблон: суммы пересчитаются от факта. Подтвердить раскладку можно в день прихода — \(occurrence.factDate.day) \(RU.monthsGen[occurrence.factDate.month - 1]).")
                        .font(.sans(13))
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 4)
                } else {
                    Button {
                        model.confirmLayout(occurrence: occurrence, factAmount: factAmount,
                                            recommendation: rec)
                    } label: {
                        Text("Подтвердить раскладку")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.caliper(.primary))
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear { factText = RU.money(occurrence.plannedAmount) }
        .sheet(isPresented: $showSurplus) { SurplusSheet(amount: free) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Раскладка")
                    .font(.sans(22, .semibold))
                    .tracking(-0.22)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.icon)
                        .tapTarget()
                }
            }
            Text("\(model.incomeName(anchorDay: occurrence.anchorDay)) · \(occurrence.factDate.day) \(RU.monthsGen[occurrence.factDate.month - 1]) · \(isTemplate ? "шаблон" : "черновик")")
                .font(.mono(12)).foregroundStyle(Theme.text3)
        }
    }

    /// Шаблон: суммы плановые, факт появится в день прихода. Крупный readout —
    /// гротеск с табличными цифрами (сигнатура Caliper).
    private var plannedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Cap("придёт по плану")
            Text(RU.money(occurrence.plannedAmount))
                .font(.sans(28, .semibold))
                .monospacedDigit()
                .tracking(-0.56)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .caliperCard(radius: 12)
    }

    private var factField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Cap("пришло")
            TextField("", text: $factText)
                .keyboardType(.numberPad)
                .font(.sans(28, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .caliperCard(radius: 12)
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let note: String?
        let amount: Double
    }

    private func draftRows(_ rec: Recommendation) -> [Row] {
        // Статья лишней финнедели этого же спринта — отдельной строкой ниже:
        // её собирали приходы окна, а не этот приход (С9).
        let ownExtra = "extra@\(occurrence.sprintStart)"
        // Строка — статья, не потребность: балансировка вправе раздать статью
        // несколькими взносами (порции финнедель, помесячные сроки, доли окна,
        // перенос ровностью П6б) — статья не задваивается, взносы складываются.
        var byArticle: [String: Double] = [:]
        for c in rec.contributions where c.incomeId == occurrence.id && c.needId != ownExtra {
            byArticle[c.articleId, default: 0] += c.amount
        }
        var rows: [Row] = byArticle.map { articleId, amount in
            Row(id: articleId, name: model.articleName(for: articleId),
                note: model.portionNote(articleId: articleId, amount: amount), amount: amount)
        }
        .sorted { (model.needOrder(for: $0.id), $0.name) < (model.needOrder(for: $1.id), $1.name) }

        // Длинный спринт: лишняя финнеделя оплачена собранным заранее (С9) —
        // перед еженедельными (МП28).
        if occurrence.isLongSprint {
            let collected = model.extraWeekCollected(sprintStart: occurrence.sprintStart, in: rec)
            let own = rec.contributions
                .filter { $0.needId == ownExtra && $0.incomeId == occurrence.id }
                .reduce(0) { $0 + $1.amount }
            let weeklyIndex = rows.firstIndex { model.needOrder(for: $0.id) >= 3 } ?? rows.endIndex
            rows.insert(Row(id: ownExtra, name: "дополнительная неделя",
                            note: own > 0.01 ? "в том числе с этого прихода \(RU.money(own))"
                                             : "собрано ранее",
                            amount: collected),
                        at: weeklyIndex)
        }
        return rows
    }

    /// Недостача заявляется с цифрой и датой (П9); недельные не гнутся —
    /// решения человек принимает правкой статей (П8).
    @ViewBuilder
    private func shortfallNotes(_ rec: Recommendation) -> some View {
        let sprintEnd = occurrence.sprintStart.adding(days: occurrence.sprintWeeks * 7)
        let local = rec.shortfalls.filter { $0.date >= occurrence.sprintStart && $0.date < sprintEnd }
        if let s = local.first {
            Text("план не сходится · к \(s.date.day) \(RU.monthsGen[s.date.month - 1]) не хватает \(RU.money(s.amount))")
                .font(.mono(12, medium: true))
                .foregroundStyle(Theme.signal)
        }
    }
}

// MARK: Чек-лист исполнения

private struct ChecklistView: View {
    let occurrence: IncomeOccurrence
    let layout: ConfirmedLayout
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    private var rows: [(key: String, name: String, note: String?, amount: Double)] {
        let ownExtra = "extra@\(occurrence.sprintStart)"
        // Строка чек-листа — статья: перевод по статье один, сколькими бы
        // потребностями балансировка её ни раздала (см. draftRows).
        var byArticle: [String: Double] = [:]
        for c in layout.contributions where c.needId != ownExtra {
            byArticle[c.articleId, default: 0] += c.amount
        }
        var result = byArticle.map { articleId, amount in
            (key: articleId, name: model.articleName(for: articleId),
             note: model.portionNote(articleId: articleId, amount: amount), amount: amount)
        }
        .sorted { (model.needOrder(for: $0.key), $0.name) < (model.needOrder(for: $1.key), $1.name) }

        // Порядок исполнения (МП28): дополнительная неделя — перед еженедельными.
        if occurrence.isLongSprint {
            let weeklyIndex = result.firstIndex { model.needOrder(for: $0.key) >= 3 } ?? result.endIndex
            result.insert((key: ownExtra, name: "дополнительная неделя", note: "собрано ранее",
                           amount: model.extraWeekCollected(sprintStart: occurrence.sprintStart)),
                          at: weeklyIndex)
        }
        // Раскладка, застывшая до еженедельных статей: порций среди её взносов
        // нет — прежняя строка недельных из застывших порций финнедель (П12).
        if !layout.weekAmounts.isEmpty, !result.contains(where: { model.isWeeklyArticle(key: $0.key) }) {
            let total = layout.weekAmounts.reduce(0) { $0 + $1.amount }
            result.append((key: "weekly", name: "недельные деньги",
                           note: "\(layout.weekAmounts.count) недели", amount: total))
        }
        return result
    }

    var body: some View {
        let rows = self.rows
        let done = rows.filter { layout.executed.contains($0.key) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Раскладка · исполнение")
                            .font(.sans(22, .semibold))
                            .tracking(-0.22)
                            .foregroundStyle(Theme.text)
                        Text("подтверждена · переводы \(done) из \(rows.count)")
                            .font(.mono(12)).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.icon)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(rows, id: \.key) { row in
                        Button {
                            model.setExecuted(incomeId: layout.incomeId, key: row.key,
                                              done: !layout.executed.contains(row.key))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: layout.executed.contains(row.key)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(layout.executed.contains(row.key)
                                                     ? Theme.fill : Theme.lineStrong)
                                LayoutRow(name: row.name, note: row.note, amount: row.amount)
                            }
                            .padding(.leading, 16)
                            .tapRow()
                        }
                        .buttonStyle(.plain)
                        if row.key != rows.last?.key { Divider().overlay(Theme.lineSoft) }
                    }
                }
                .caliperCard()

                Button {
                    model.executeAll(incomeId: layout.incomeId, keys: rows.map(\.key))
                    dismiss()
                } label: {
                    Text("Всё проделано")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.caliper(.secondary))
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}

private struct LayoutRow: View {
    let name: String
    let note: String?
    let amount: Double

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.sans(16)).foregroundStyle(Theme.text)
                if let note {
                    Text(note).font(.mono(12)).foregroundStyle(Theme.text3)
                }
            }
            Spacer()
            Text(RU.money(amount))
                .font(.mono(14, medium: true)).foregroundStyle(Theme.text)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

// MARK: Попап свободных денег (МП29)

private struct SurplusSheet: View {
    let amount: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Свободные деньги")
                    .font(.sans(17, .semibold)).foregroundStyle(Theme.text)
                Text(RU.money(amount))
                    .font(.mono(14, medium: true)).foregroundStyle(Theme.text2)
            }
            .padding(.bottom, 8)
            row("ускорить статью", "появится в следующей версии", disabled: true)
            row("новый замысел или поднять неделю", "появится в следующей версии", disabled: true)
            Button { dismiss() } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ничего не трогать")
                        .font(.sans(16)).foregroundStyle(Theme.text)
                    Text("\(RU.money(amount)) выйдут из плана и не вернутся")
                        .font(.mono(12)).foregroundStyle(Theme.text3)
                }
                .padding(.vertical, 14)
                .tapRow()
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .presentationBackground(Theme.surfaceRaised)
        .presentationCornerRadius(22)
    }

    private func row(_ title: String, _ note: String, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.sans(16))
                .foregroundStyle(disabled ? Theme.textDisabled : Theme.text)
            Text(note).font(.sans(12)).foregroundStyle(Theme.textDisabled)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

