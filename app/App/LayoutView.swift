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
                        if row.id != rows.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                    .strokeBorder(Theme.line, lineWidth: 1))

                if free > 0.5 {
                    Button { showSurplus = true } label: {
                        HStack {
                            Text("свободные деньги · \(RU.money(free))")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentSoft))
                    }
                }

                shortfallNotes(rec)

                if isTemplate {
                    Text("Это шаблон: суммы пересчитаются от факта. Подтвердить раскладку можно в день прихода — \(occurrence.factDate.day) \(RU.monthsGen[occurrence.factDate.month - 1]).")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 4)
                } else {
                    Button {
                        model.confirmLayout(occurrence: occurrence, factAmount: factAmount,
                                            recommendation: rec)
                    } label: {
                        Text("Подтвердить раскладку")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Theme.accent))
                    }
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Раскладка").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                        .tapTarget()
                }
            }
            Text("\(model.incomeName(anchorDay: occurrence.anchorDay)) · \(occurrence.factDate.day) \(RU.monthsGen[occurrence.factDate.month - 1]) · \(isTemplate ? "шаблон" : "черновик")")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        }
    }

    /// Шаблон: суммы плановые, факт появится в день прихода.
    private var plannedRow: some View {
        HStack {
            Text("придёт по плану").font(.system(size: 15)).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(RU.money(occurrence.plannedAmount))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
            .strokeBorder(Theme.line, lineWidth: 1))
    }

    private var factField: some View {
        HStack {
            Text("пришло").font(.system(size: 15)).foregroundStyle(Theme.textMuted)
                .fixedSize()
            TextField("", text: $factText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
            .strokeBorder(Theme.line, lineWidth: 1))
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
        // несколькими взносами (помесячные сроки, доли окна, перенос ровностью
        // П6б) — статья не задваивается, взносы складываются.
        var byArticle: [String: Double] = [:]
        for c in rec.contributions where c.incomeId == occurrence.id && c.needId != ownExtra {
            byArticle[c.articleId, default: 0] += c.amount
        }
        var rows: [Row] = byArticle.map { articleId, amount in
            Row(id: articleId, name: model.articleName(for: articleId), note: nil, amount: amount)
        }
        .sorted { (model.needOrder(for: $0.id), $0.name) < (model.needOrder(for: $1.id), $1.name) }

        // Длинный спринт: лишняя финнеделя оплачена собранным заранее (С9, layout.md).
        if occurrence.isLongSprint {
            let collected = model.extraWeekCollected(sprintStart: occurrence.sprintStart, in: rec)
            let own = rec.contributions
                .filter { $0.needId == ownExtra && $0.incomeId == occurrence.id }
                .reduce(0) { $0 + $1.amount }
            rows.append(Row(id: ownExtra, name: "дополнительная неделя",
                            note: own > 0.01 ? "в том числе с этого прихода \(RU.money(own))"
                                             : "собрано ранее",
                            amount: collected))
        }

        let weekStarts = (0..<occurrence.sprintWeeks).map { occurrence.sprintStart.adding(days: $0 * 7) }
        let weekly = rec.weeks.filter { weekStarts.contains($0.start) }
        let total = weekly.reduce(0) { $0 + $1.amount }
        rows.append(Row(id: "weekly",
                        name: "недельные деньги",
                        note: "\(weekly.count) × \(RU.money(model.plan.namedWeek))",
                        amount: total))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
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
            (key: articleId, name: model.articleName(for: articleId), note: String?.none, amount: amount)
        }
        .sorted { (model.needOrder(for: $0.key), $0.name) < (model.needOrder(for: $1.key), $1.name) }

        // Порядок исполнения (МП28): дополнительная неделя — перед недельными.
        if occurrence.isLongSprint {
            result.append((key: ownExtra, name: "дополнительная неделя", note: "собрано ранее",
                           amount: model.extraWeekCollected(sprintStart: occurrence.sprintStart)))
        }
        let total = layout.weekAmounts.reduce(0) { $0 + $1.amount }
        result.append((key: "weekly", name: "недельные деньги",
                       note: "\(layout.weekAmounts.count) недели", amount: total))
        return result
    }

    var body: some View {
        let rows = self.rows
        let done = rows.filter { layout.executed.contains($0.key) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Раскладка · исполнение")
                            .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("подтверждена · переводы \(done) из \(rows.count)")
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
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
                                                     ? Theme.accent : Theme.line)
                                LayoutRow(name: row.name, note: row.note, amount: row.amount)
                            }
                            .padding(.leading, 14)
                            .tapRow()
                        }
                        .buttonStyle(.plain)
                        if row.key != rows.last?.key { Divider().overlay(Theme.line) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                    .strokeBorder(Theme.line, lineWidth: 1))

                Button {
                    model.executeAll(incomeId: layout.incomeId, keys: rows.map(\.key))
                    dismiss()
                } label: {
                    Text("Всё проделано")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15)).foregroundStyle(Theme.text)
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                }
            }
            Spacer()
            Text(RU.money(amount))
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }
}

// MARK: Попап свободных денег (МП29)

private struct SurplusSheet: View {
    let amount: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Свободные деньги · \(RU.money(amount))")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                .padding(.bottom, 8)
            row("ускорить статью", "появится в следующей версии", disabled: true)
            row("новый замысел или поднять неделю", "появится в следующей версии", disabled: true)
            Button { dismiss() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ничего не трогать")
                        .font(.system(size: 15)).foregroundStyle(Theme.text)
                    Text("\(RU.money(amount)) выйдут из плана и не вернутся")
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                }
                .padding(.vertical, 14)
                .tapRow()
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .presentationBackground(Theme.surface)
    }

    private func row(_ title: String, _ note: String, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15))
                .foregroundStyle(disabled ? Theme.textFaint : Theme.text)
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

