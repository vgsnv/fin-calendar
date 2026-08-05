import SwiftUI
import FinCalendarCore

/// Карточка спринта (tape.md, МП24): даты и состав спринта — взносы по статьям,
/// недельные деньги, свободные деньги, секция «на паузе».
/// До раскладки показывается живая рекомендация (П11), после — застывшие цифры (П12):
/// разложенный спринт — только чтение.
struct SprintDetailView: View {
    let occurrence: IncomeOccurrence
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var showArticleForm = false
    @State private var showLayout = false
    @State private var editingArticle: Article?

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
                        // Тап по строке статьи — правка (С1–С8): системные строки
                        // («недельные», доп. неделя) не статьи, их не открыть.
                        // В прошлом спринте строки не открываются — только чтение.
                        if !isPast, let article = article(for: row.id) {
                            Button { editingArticle = article } label: {
                                SprintContributionRow(name: row.name, note: row.note,
                                                      amount: row.amount, editable: true)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            SprintContributionRow(name: row.name, note: row.note, amount: row.amount)
                        }
                        if row.id != rows.last?.id { Divider().overlay(Theme.lineSoft) }
                    }
                }
                .caliperCard()

                if free > 0.5 {
                    // Свободные деньги — тёмная «инструментальная» панель.
                    HStack(spacing: 8) {
                        Text("свободные деньги прихода")
                            .font(.sans(14, .medium))
                            .foregroundStyle(Theme.inkFg)
                        Spacer()
                        Text(RU.money(free))
                            .font(.mono(14, medium: true))
                            .foregroundStyle(Theme.inkFg)
                    }
                    .padding(16)
                    .inkPanel()
                }

                if !paused.isEmpty { pausedSection(paused) }

                actions(isConfirmed: confirmed != nil)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .presentationCornerRadius(22)
        .sheet(isPresented: $showArticleForm) { ArticleFormView() }
        .sheet(item: $editingArticle) { ArticleFormView(existing: $0) }
        .fullScreenCover(isPresented: $showLayout) {
            LayoutSheetView(occurrence: occurrence, template: isFuture)
        }
    }

    /// Приход ещё не наступил — раскладка открывается шаблоном, без подтверждения.
    private var isFuture: Bool { occurrence.factDate > model.today }

    /// Спринт закончился — прошлое, только чтение: раскладки задним числом нет (С15а).
    private var isPast: Bool {
        occurrence.sprintStart.adding(days: occurrence.sprintWeeks * 7 - 1) < model.today
    }

    private func article(for key: String) -> Article? {
        model.plan.articles.first { $0.id == Plan.articleId(of: key) }
    }

    // MARK: Заголовок

    private func header(_ confirmed: ConfirmedLayout?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(datesTitle)
                    .font(.sans(22, .semibold))
                    .monospacedDigit()
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
            Text(subtitle(confirmed))
                .font(.mono(12))
                .foregroundStyle(Theme.text3)
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
    /// еженедельные статьи — последними (МП28).
    private func contributionRows(_ confirmed: ConfirmedLayout?) -> [Row] {
        // Строка — статья, не потребность: взносы статьи складываются,
        // сколькими бы потребностями балансировка её ни раздала (П6б, layout.md).
        var byArticle: [String: Double] = [:]

        // Статья лишней финнедели своего спринта — отдельной строкой ниже (С9).
        let ownExtra = "extra@\(occurrence.sprintStart)"

        if let confirmed {
            for c in confirmed.contributions where c.needId != ownExtra {
                byArticle[c.articleId, default: 0] += c.amount
            }
        } else {
            let rec = model.horizon.recommendation
            for c in rec.contributions where c.incomeId == occurrence.id && c.needId != ownExtra {
                byArticle[c.articleId, default: 0] += c.amount
            }
        }

        var rows = byArticle.map { articleId, amount in
            Row(id: articleId, name: model.articleName(for: articleId),
                note: model.portionNote(articleId: articleId, amount: amount), amount: amount)
        }
        .sorted { (model.needOrder(for: $0.id), $0.name) < (model.needOrder(for: $1.id), $1.name) }

        if occurrence.isLongSprint {
            let weeklyIndex = rows.firstIndex { model.needOrder(for: $0.id) >= 3 } ?? rows.endIndex
            rows.insert(Row(id: ownExtra, name: "дополнительная неделя", note: "собрано ранее",
                            amount: model.extraWeekCollected(sprintStart: occurrence.sprintStart)),
                        at: weeklyIndex)
        }

        // Раскладка, застывшая до еженедельных статей: порций среди взносов нет —
        // прежняя строка недельных из застывших порций финнедель (П12).
        if let confirmed, !confirmed.weekAmounts.isEmpty,
           !rows.contains(where: { model.isWeeklyArticle(key: $0.id) }) {
            let count = confirmed.weekAmounts.count
            rows.append(Row(id: "weekly",
                            name: "недельные деньги",
                            note: "\(count) \(weeksWord(count))",
                            amount: confirmed.weekAmounts.reduce(0) { $0 + $1.amount }))
        }
        return rows
    }

    // MARK: На паузе

    private func pausedSection(_ articles: [Article]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Cap("на паузе")
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(articles, id: \.id) { article in
                    pausedRow(article)
                    if article.id != articles.last?.id { Divider().overlay(Theme.lineSoft) }
                }
            }
            .caliperCard()
        }
        .padding(.top, 8)
    }

    private func pausedRow(_ article: Article) -> some View {
        HStack(spacing: 8) {
            Button { editingArticle = article } label: {
                (Text(article.name)
                    .font(.sans(16))
                    .foregroundStyle(Theme.text)
                 + Text(" · \(pausedNote(article))")
                    .font(.mono(12))
                    .foregroundStyle(Theme.text3))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                model.setPaused(articleId: article.id, paused: false)
            } label: {
                Text("возобновить")
                    .font(.sans(12, .semibold))
                    .tracking(0.24)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.lineStrong, lineWidth: 1.5)))
                    .tapPadded(visualHeight: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func pausedNote(_ article: Article) -> String {
        switch article.kind {
        case .intent(_, let speed), .fund(let speed):
            return "\(RU.money(speed)) в месяц"
        case .payment(let amount, _, _, _):
            return RU.money(amount)
        case .weekly(let portion):
            // Еженедельная паузы не имеет (П9) — ветка для полноты типа.
            return "\(RU.money(portion)) в неделю"
        }
    }

    // MARK: Действия

    private func actions(isConfirmed: Bool) -> some View {
        HStack(spacing: 12) {
            if !isPast {
                Button { showArticleForm = true } label: {
                    Text("+ статья")
                }
                .buttonStyle(.caliper(.secondary))
            }
            if isConfirmed {
                Button { showLayout = true } label: {
                    Text("Раскладка · исполнение")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.caliper(.secondary))
            } else if isPast {
                // Прошёл без раскладки: восстановления задним числом нет (С15а).
                Text("спринт прошёл без раскладки — числа не застыли")
                    .font(.sans(13))
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else if isFuture {
                // Приход впереди: раскладку можно посмотреть шаблоном, но не подтвердить.
                Button { showLayout = true } label: {
                    Text("Шаблон раскладки")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.caliper(.secondary))
            } else {
                Button { showLayout = true } label: {
                    Text("Разложить")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.caliper(.primary))
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
    var editable = false

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
                .font(.mono(14, medium: true))
                .foregroundStyle(Theme.text)
            if editable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.iconMuted)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
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
