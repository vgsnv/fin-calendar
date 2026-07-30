import Foundation
import UserNotifications
import FinCalendarCore

/// Голос системы — ровно два локальных уведомления (МП33), сервера нет (МП3):
/// «пора раскладка» в плановую дату прихода и «новая неделя» утром старта финнедели.
/// Расписание строится заранее из данных плана и перестраивается при каждой его
/// правке (П11): полная очистка и новый набор — так отметка выдачи или правка
/// плана сами снимают лишние уведомления. Ничего другого голос не делает (МП34):
/// ни напоминаний о незаконченной раскладке, ни новостей, ни похвал.
enum NotificationManager {

    /// Полное перестроение расписания. Снимки состояния берутся синхронно,
    /// дальше задача работает только с ними (Plan и IncomeOccurrence — Sendable).
    static func reschedule(_ model: AppModel) {
        let plan = model.plan
        let occurrences = model.horizon.occurrences
        let today = model.today

        Task {
            let center = UNUserNotificationCenter.current()

            // Пустой план — только очистка: планировать нечего,
            // и разрешения спрашивать не о чем (вход ещё впереди).
            guard !plan.incomes.isEmpty else {
                center.removeAllPendingNotificationRequests()
                return
            }

            // Разрешение: системный диалог показывается один раз,
            // отказ просто принимается — без ошибок и уговоров.
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            center.removeAllPendingNotificationRequests()

            // 1. «Пора раскладка» — плановая дата прихода, один раз на приход (МП33).
            // Горизонт плана — годы (МП23), а очередь локальных уведомлений
            // у системы короткая: планируются только ближние приходы,
            // расписание всё равно перестраивается при каждой правке.
            if plan.notifyLayout {
                let window = today.adding(days: 120)
                for occ in occurrences where occ.factDate >= today && occ.factDate <= window {
                    let content = UNMutableNotificationContent()
                    content.title = "Пора раскладка"
                    content.body = "По плану сегодня приход „\(incomeName(anchorDay: occ.anchorDay, in: plan))“ — когда деньги придут, разложите их."
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: "layout-\(occ.id)",
                        content: content,
                        trigger: trigger(on: occ.factDate, hour: 9))
                    try? await center.add(request)
                }
            }

            // 2. «Новая неделя» — утро старта финнедели разложенного спринта (МП33, С16).
            //    Выданные недели пропускаются: отметка выдачи меняет план, план вызывает
            //    reschedule — запланированное уведомление снимается само.
            if plan.notifyIssue {
                for layout in plan.confirmed {
                    for week in layout.weekAmounts
                    where week.start >= today && !plan.issuedWeeks.contains(week.start) {
                        let content = UNMutableNotificationContent()
                        content.title = "Новая неделя"
                        content.body = "Выдать \(RU.money(week.amount)) — полная порция, как всегда."
                        content.sound = .default
                        let request = UNNotificationRequest(
                            identifier: "issue-\(week.start)",
                            content: content,
                            trigger: trigger(on: week.start, hour: 8))
                        try? await center.add(request)
                    }
                }
            }
        }
    }

    /// Календарный триггер: конкретный день в конкретный час, без повторов.
    private static func trigger(on date: CivilDate, hour: Int) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(
            dateMatching: DateComponents(year: date.year, month: date.month, day: date.day,
                                         hour: hour, minute: 0),
            repeats: false)
    }

    /// Имя прихода по опорной дате — как в AppModel.incomeName, но от снимка плана.
    private static func incomeName(anchorDay: Int, in plan: Plan) -> String {
        let name = plan.incomes.first { $0.anchor.day == anchorDay }?.anchor.name ?? ""
        return name.isEmpty ? "приход \(anchorDay)-го" : name
    }
}
