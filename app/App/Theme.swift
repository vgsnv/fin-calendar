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

enum RU {
    static let months = ["ЯНВАРЬ", "ФЕВРАЛЬ", "МАРТ", "АПРЕЛЬ", "МАЙ", "ИЮНЬ",
                         "ИЮЛЬ", "АВГУСТ", "СЕНТЯБРЬ", "ОКТЯБРЬ", "НОЯБРЬ", "ДЕКАБРЬ"]
    static let monthsGen = ["января", "февраля", "марта", "апреля", "мая", "июня",
                            "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let days = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

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
