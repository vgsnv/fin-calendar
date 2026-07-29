import SwiftUI
import FinCalendarCore

/// Карточка спринта (tape.md, МП24): даты и состав спринта — взносы по статьям,
/// повседневные деньги, свободные деньги, секция «на паузе».
/// До раскладки показывается живая рекомендация (П11), после — застывшие цифры (П12):
/// разложенный спринт — только чтение.
struct SprintDetailView: View {
    let occurrence: IncomeOccurrence
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var showArticleForm = false
    @State private var showLayout = false

    var body: some View {
        let confirmed = model.layout(for: occurrence.id)
        let rows = contributionRows(confirmed)
        let free = confirmed == nil ? (model.horizon.recommendation.freeMoney[occurrence.id] ?? 0) : 0
        let paused = model.plan.articles.filter(\.paused)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(confirmed)

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        SprintContributionRow(name: row.name, note: row.note, amount: row.amount)
                        if row.id != rows.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                    .strokeBorder(Theme.line, lineWidth: 1))

                if free > 0.5 {
                    Text("свободные деньги прихода · \(RU.money(free))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentSoft))
                }

                if !paused.isEmpty { pausedSection(paused) }

                actions(isConfirmed: confirmed != nil)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showArticleForm) { ArticleFormView() }
        .fullScreenCover(isPresented: $showLayout) { LayoutSheetView(occurrence: occurrence) }
    }

    // MARK: Заголовок

    private func header(_ confirmed: ConfirmedLayout?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(datesTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Text(subtitle(confirmed))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var datesTitle: String {
        let s = occurrence.sprintStart
        let e = s.adding(days: occurrence.sprintWeeks * 7 - 1)
        return "\(s.day) \(RU.monthsGen[s.month - 1]) – \(e.day) \(RU.monthsGen[e.month - 1])"
    }

    private func subtitle(_ confirmed: ConfirmedLayout?) -> String {
        var parts = ["\(occurrence.sprintWeeks) \(finweeksWord(occurrence.sprintWeeks))"]
        if occurrence.isLongSprint { parts.append("длинный спринт") }
        parts.append(model.incomeName(anchorDay: occurrence.anchorDay))
        if let confirmed {
            parts.append("факт \(RU.money(confirmed.factAmount))")
        } else {
            parts.append("план \(RU.money(occurrence.plannedAmount))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Взносы

    private struct Row: Identifiable {
        let id: String
        let name: String
        let note: String?
        let amount: Double
    }

    /// Строки карточки: застывшая раскладка (П12) либо живая рекомендация (П11);
    /// последней строкой — повседневные деньги спринта.
    private func contributionRows(_ confirmed: ConfirmedLayout?) -> [Row] {
        var byNeed: [String: Double] = [:]
        let everydayCount: Int
        let everydayTotal: Double

        if let confirmed {
            for c in confirmed.contributions { byNeed[c.needId, default: 0] += c.amount }
            everydayCount = confirmed.weekAmounts.count
            everydayTotal = confirmed.weekAmounts.reduce(0) { $0 + $1.amount }
        } else {
            let rec = model.horizon.recommendation
            for c in rec.contributions where c.incomeId == occurrence.id {
                byNeed[c.needId, default: 0] += c.amount
            }
            let starts = (0..<occurrence.sprintWeeks).map { occurrence.sprintStart.adding(days: $0 * 7) }
            let everyday = rec.weeks.filter { starts.contains($0.start) }
            everydayCount = everyday.count
            everydayTotal = everyday.reduce(0) { $0 + $1.amount }
        }

        var rows = byNeed.map { needId, amount in
            Row(id: needId, name: model.articleName(for: needId), note: nil, amount: amount)
        }
        .sorted { (model.needOrder(for: $0.id), $0.name) < (model.needOrder(for: $1.id), $1.name) }

        rows.append(Row(id: "everyday",
                        name: "повседневные деньги",
                        note: "\(everydayCount) \(weeksWord(everydayCount))",
                        amount: everydayTotal))
        return rows
    }

    // MARK: На паузе

    private func pausedSection(_ articles: [Article]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("на паузе")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(articles, id: \.id) { article in
                    pausedRow(article)
                    if article.id != articles.last?.id { Divider().overlay(Theme.line) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)
                .strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func pausedRow(_ article: Article) -> some View {
        HStack(spacing: 8) {
            (Text(article.name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
             + Text(" · \(pausedNote(article))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted))
                .lineLimit(2)
            Spacer()
            Button {
                model.setPaused(articleId: article.id, paused: false)
            } label: {
                Text("возобновить")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accentSoft))
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }

    private func pausedNote(_ article: Article) -> String {
        switch article.kind {
        case .intent(_, let speed), .fund(let speed):
            return "\(RU.money(speed)) в месяц"
        case .payment(let amount, _, _, _):
            return RU.money(amount)
        }
    }

    // MARK: Действия

    private func actions(isConfirmed: Bool) -> some View {
        HStack(spacing: 10) {
            Button { showArticleForm = true } label: {
                Text("+ статья")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.surface)
                        .strokeBorder(Theme.line, lineWidth: 1))
            }
            if isConfirmed {
                Button { showLayout = true } label: {
                    Text("Раскладка · исполнение")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().strokeBorder(Theme.accent, lineWidth: 1))
                }
            } else {
                Button { showLayout = true } label: {
                    Text("Разложить")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Theme.accent))
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: Строка взноса

private struct SprintContributionRow: View {
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
    }
}

// MARK: Склонения

private func pluralRU(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return one }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
    return many
}

private func finweeksWord(_ n: Int) -> String { pluralRU(n, "финнеделя", "финнедели", "финнедель") }
private func weeksWord(_ n: Int) -> String { pluralRU(n, "неделя", "недели", "недель") }
