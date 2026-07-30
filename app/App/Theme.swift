import SwiftUI

/// Токены визуального языка — те же, что в Figma-файле «Известное будущее · MVP».
/// Спокойный планировщик: тёплый бумажный фон, один акцент, тревожных цветов нет.
enum Theme {
    static let bg = Color(hex: 0xFCFBF8)
    static let surface = Color(hex: 0xFFFFFF)
    static let subtle = Color(hex: 0xF3F1EB)
    static let text = Color(hex: 0x1D1C19)
    static let textMuted = Color(hex: 0x8B877C)
    static let textFaint = Color(hex: 0xB8B4A8)
    static let line = Color(hex: 0xE7E4DB)
    static let accent = Color(hex: 0x2F5D50)
    static let accentSoft = Color(hex: 0xE4EEE9)
}

extension View {
    /// Тап-зона иконочной кнопки — не меньше 44×44 (минимум HIG): значок на 15–17 pt
    /// мельче пальца, и без этого человек мажет. Значок остаётся своего размера,
    /// растёт только область попадания.
    func tapTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }

    /// Тап-зона строки: вся строка во всю ширину и не ниже 44. `contentShape`
    /// обязателен — без него прозрачные части (отступы, место под Spacer'ом)
    /// тап не ловят, и строка отзывается только на буквы и цифры.
    func tapRow(minHeight: CGFloat = 44) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
    }

    /// Тап-зона вокруг готовой фигуры (капсула, чип): визуальный размер не меняется,
    /// вокруг добавляется прозрачный запас до `minHeight`.
    func tapPadded(minHeight: CGFloat = 44, visualHeight: CGFloat) -> some View {
        padding(.vertical, max(0, (minHeight - visualHeight) / 2))
            .contentShape(Rectangle())
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Строка-переключатель на Button вместо системного Toggle: системный Toggle
/// глотает первый тап, пока фокус в текстовом поле, — кнопка не глотает.
struct SwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack {
                label().frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(isOn ? Theme.accent : Theme.line)
                    .frame(width: 51, height: 31)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 27, height: 27)
                            .padding(2)
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Кнопочный степпер «− | +» — по той же причине, что и SwitchRow.
struct StepperControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            step("minus") { if value > range.lowerBound { value -= 1 } }
            Rectangle().fill(Theme.line).frame(width: 1, height: 18)
            step("plus") { if value < range.upperBound { value += 1 } }
        }
        .background(Capsule().fill(Theme.subtle))
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Кнопка «числа месяца» — открывает попап с сеткой 1–28 (СВ1):
/// выбор одним тапом вместо перебора степпером.
struct DayGridButton: View {
    @Binding var day: Int
    var suffix = "-е"
    @State private var showGrid = false

    var body: some View {
        Button { showGrid = true } label: {
            Text("\(day)\(suffix)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.subtle))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGrid) { DayGridSheet(day: $day) }
    }
}

private struct DayGridSheet: View {
    @Binding var day: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Число месяца")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                      spacing: 8) {
                ForEach(1...28, id: \.self) { d in
                    Button {
                        day = d
                        dismiss()
                    } label: {
                        Text(String(d))
                            .font(.system(size: 17, weight: d == day ? .semibold : .regular))
                            .foregroundStyle(d == day ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(d == day ? Theme.accent : Theme.subtle))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("1–28 — такие числа есть в любом месяце")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(340)])
        .presentationBackground(Theme.surface)
    }
}

enum RU {
    static let months = ["ЯНВАРЬ", "ФЕВРАЛЬ", "МАРТ", "АПРЕЛЬ", "МАЙ", "ИЮНЬ",
                         "ИЮЛЬ", "АВГУСТ", "СЕНТЯБРЬ", "ОКТЯБРЬ", "НОЯБРЬ", "ДЕКАБРЬ"]
    static let monthsGen = ["января", "февраля", "марта", "апреля", "мая", "июня",
                            "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let days = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    /// Счётная фраза недель на экране: «1 неделя» · «2 недели» · «5 недель».
    /// Единственное место, где это склонение живёт: слова «финнеделя» на экране
    /// нет ни в одной форме (МП12б), а на экране неделя — только отрезок (МП12а).
    static func weeks(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        let word: String
        if m10 == 1 && m100 != 11 { word = "неделя" }
        else if (2...4).contains(m10) && !(12...14).contains(m100) { word = "недели" }
        else { word = "недель" }
        return "\(n) \(word)"
    }

    static func money(_ v: Double) -> String {
        let n = Int(v.rounded())
        var s = String(n), out = ""
        while s.count > 3 {
            out = " " + s.suffix(3) + out
            s = String(s.dropLast(3))
        }
        return s + out
    }
}
