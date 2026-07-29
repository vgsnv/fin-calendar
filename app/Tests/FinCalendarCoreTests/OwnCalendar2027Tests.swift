import XCTest
@testable import FinCalendarCore

/// Приёмочные тесты сетки своего календаря по эталону tests/own-calendar-2027.md.
/// Параметры эталона: граница финнедели — суббота (6), правило переноса — последний рабочий день до.
final class OwnCalendar2027Tests: XCTestCase {

    private let saturday = 6

    /// Окно показа эталона: спринты, начинающиеся в 2027-м, плюс спринт, накрывающий 1 января 2027.
    private func window(_ sprints: [Sprint]) -> [Sprint] {
        sprints.filter { s in
            (s.start.year == 2027) ||
            (s.start <= CivilDate(2027, 1, 1) && CivilDate(2027, 1, 1) <= s.end)
        }
    }

    private func assertGrid(_ got: [Sprint], _ expected: [(CivilDate, Int)],
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, expected.count, "число спринтов", file: file, line: line)
        for (s, e) in zip(got, expected) {
            XCTAssertEqual(s.start, e.0, "старт", file: file, line: line)
            XCTAssertEqual(s.weeks, e.1, "длина спринта от \(s.start)", file: file, line: line)
        }
    }

    /// СВ3: сумма длин всех спринтов между любыми двумя границами равна числу финнедель между ними.
    private func assertInvariant(_ sprints: [Sprint], file: StaticString = #filePath, line: UInt = #line) {
        guard let first = sprints.first, let last = sprints.last else { return XCTFail(file: file, line: line) }
        let total = sprints.reduce(0) { $0 + $1.weeks }
        let span = (last.end.dayNumber + 1 - first.start.dayNumber) / 7
        XCTAssertEqual(total, span, "СВ3: финнедели потеряны или посчитаны дважды", file: file, line: line)
        for (a, b) in zip(sprints, sprints.dropFirst()) {
            XCTAssertEqual(a.end.adding(days: 1), b.start, "спринты не стыкуются", file: file, line: line)
        }
    }

    // MARK: Кейс 1 · один приход: 25-го

    func testCase1_singleAnchor25() {
        let cal = OwnCalendar(weekBoundary: saturday, anchors: [Anchor(day: 25)])
        let grid = window(cal.sprints(fromYear: 2026, fromMonth: 11, toYear: 2028, toMonth: 3))

        let expected: [(CivilDate, Int)] = [
            (CivilDate(2026, 12, 26), 5), (CivilDate(2027, 1, 30), 4), (CivilDate(2027, 2, 27), 4),
            (CivilDate(2027, 3, 27), 4),  (CivilDate(2027, 4, 24), 5), (CivilDate(2027, 5, 29), 4),
            (CivilDate(2027, 6, 26), 4),  (CivilDate(2027, 7, 24), 5), (CivilDate(2027, 8, 28), 4),
            (CivilDate(2027, 9, 25), 5),  (CivilDate(2027, 10, 30), 4), (CivilDate(2027, 11, 27), 4),
            (CivilDate(2027, 12, 25), 5)
        ]
        assertGrid(grid, expected)
        assertInvariant(grid)
        XCTAssertEqual(grid.reduce(0) { $0 + $1.weeks }, 57, "итого финнедель")
        XCTAssertEqual(grid.filter(\.isLong).map(\.start),
                       [CivilDate(2026, 12, 26), CivilDate(2027, 4, 24), CivilDate(2027, 7, 24),
                        CivilDate(2027, 9, 25), CivilDate(2027, 12, 25)],
                       "длинные спринты (доп)")
    }

    // MARK: Кейс 2 · два прихода: 5-го и 20-го

    func testCase2_twoAnchors5and20() {
        let cal = OwnCalendar(weekBoundary: saturday, anchors: [Anchor(day: 5), Anchor(day: 20)])
        let grid = window(cal.sprints(fromYear: 2026, fromMonth: 11, toYear: 2028, toMonth: 2))

        let expected: [(CivilDate, Int)] = [
            (CivilDate(2026, 12, 19), 3), (CivilDate(2027, 1, 9), 2),  (CivilDate(2027, 1, 23), 2),
            (CivilDate(2027, 2, 6), 2),   (CivilDate(2027, 2, 20), 2), (CivilDate(2027, 3, 6), 2),
            (CivilDate(2027, 3, 20), 3),  (CivilDate(2027, 4, 10), 2), (CivilDate(2027, 4, 24), 2),
            (CivilDate(2027, 5, 8), 2),   (CivilDate(2027, 5, 22), 2), (CivilDate(2027, 6, 5), 2),
            (CivilDate(2027, 6, 19), 3),  (CivilDate(2027, 7, 10), 2), (CivilDate(2027, 7, 24), 2),
            (CivilDate(2027, 8, 7), 2),   (CivilDate(2027, 8, 21), 2), (CivilDate(2027, 9, 4), 3),
            (CivilDate(2027, 9, 25), 2),  (CivilDate(2027, 10, 9), 2), (CivilDate(2027, 10, 23), 2),
            (CivilDate(2027, 11, 6), 2),  (CivilDate(2027, 11, 20), 2), (CivilDate(2027, 12, 4), 3),
            (CivilDate(2027, 12, 25), 2)
        ]
        assertGrid(grid, expected)
        assertInvariant(grid)
        XCTAssertEqual(grid.reduce(0) { $0 + $1.weeks }, 55, "итого финнедель")
        XCTAssertEqual(grid.filter(\.isLong).count, 5, "длинных спринтов за окно")
    }

    // MARK: Кейс 3 · три прихода — контрпример К5: алгоритм обязан считать корректно

    func testCase3_threeAnchorsCountsCorrectly() {
        let cal = OwnCalendar(weekBoundary: saturday,
                              anchors: [Anchor(day: 1), Anchor(day: 10), Anchor(day: 20)])
        let grid = window(cal.sprints(fromYear: 2026, fromMonth: 11, toYear: 2028, toMonth: 2))

        XCTAssertEqual(grid.count, 37, "итого спринтов")
        XCTAssertEqual(grid.reduce(0) { $0 + $1.weeks }, 54, "итого финнедель")
        assertInvariant(grid)

        // выборочные строки эталона
        XCTAssertEqual(grid[0].start, CivilDate(2026, 12, 19))
        XCTAssertEqual(grid[0].weeks, 2)
        XCTAssertEqual(grid[1].start, CivilDate(2027, 1, 2))
        XCTAssertEqual(grid[1].weeks, 1)
        XCTAssertEqual(grid.last!.start, CivilDate(2027, 12, 25))
        XCTAssertEqual(grid.last!.weeks, 1)
    }

    // MARK: Кейс 4 · производственный календарь: январский стык

    func testCase4_productionCalendarMovesLongSprint() {
        var holidays: Set<CivilDate> = [
            CivilDate(2026, 11, 4), CivilDate(2026, 12, 31),
            CivilDate(2027, 2, 22), CivilDate(2027, 2, 23), CivilDate(2027, 3, 8),
            CivilDate(2027, 5, 1), CivilDate(2027, 5, 3), CivilDate(2027, 5, 9), CivilDate(2027, 5, 10),
            CivilDate(2027, 6, 12), CivilDate(2027, 6, 14),
            CivilDate(2027, 11, 4), CivilDate(2027, 11, 5), CivilDate(2027, 12, 31)
        ]
        for d in 1...8 { holidays.insert(CivilDate(2027, 1, d)) }
        let production = ProductionCalendar(holidays: holidays,
                                            workingWeekends: [CivilDate(2027, 2, 20)])

        let cal = OwnCalendar(weekBoundary: saturday,
                              anchors: [Anchor(day: 5), Anchor(day: 20)],
                              production: production)
        let grid = window(cal.sprints(fromYear: 2026, fromMonth: 11, toYear: 2028, toMonth: 2))

        // Приход 5 января утянут каникулами на 30 декабря: старт прыгает с 09.01 на 02.01,
        // дополнительная финнеделя переезжает на другой спринт и другой приход (СВ5).
        let december = grid.first { $0.start == CivilDate(2026, 12, 19) }
        XCTAssertNotNil(december)
        XCTAssertEqual(december?.weeks, 2, "декабрьский спринт больше не длинный")

        let january = grid.first { $0.start == CivilDate(2027, 1, 2) }
        XCTAssertNotNil(january, "старт прыгнул с 09.01 на 02.01")
        XCTAssertEqual(january?.weeks, 3, "январский спринт стал длинным")
        XCTAssertEqual(january?.factDates.first, CivilDate(2026, 12, 30),
                       "фактическая дата прихода — последний рабочий день до каникул")

        assertInvariant(grid)
    }

    // MARK: Устройство даты

    func testCivilDateWeekday() {
        XCTAssertEqual(CivilDate(2027, 1, 1).weekday, 5, "1 января 2027 — пятница")
        XCTAssertEqual(CivilDate(2026, 7, 4).weekday, 6, "4 июля 2026 — суббота")
        XCTAssertEqual(CivilDate(2027, 12, 25).weekday, 6, "25 декабря 2027 — суббота")
    }
}
