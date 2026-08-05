import SwiftUI
import CoreText

/// Токены Caliper Design System (CaliperDesignSystem/Caliper App UI Kit.html):
/// утилитарная «инструментальная» система. Тёплый графитовый монохром, без
/// градиентов и ярких цветов; единственный хроматический акцент — приглушённый
/// вермильон «signal», только для живого/критичного/деструктивного. Числа —
/// табличные, технические подписи — JetBrains Mono, сигнатура системы —
/// крошечные капсы с широким трекингом.
enum Theme {
    // Нейтральная рампа — тёплый графит
    static let n0 = Color(hex: 0xFFFFFF)
    static let n50 = Color(hex: 0xF6F5F2)
    static let n100 = Color(hex: 0xECEBE7)
    static let n150 = Color(hex: 0xE3E1DB)
    static let n200 = Color(hex: 0xD8D6CF)
    static let n300 = Color(hex: 0xC4C1B8)
    static let n400 = Color(hex: 0xA6A39A)
    static let n500 = Color(hex: 0x84817A)
    static let n600 = Color(hex: 0x605D57)
    static let n700 = Color(hex: 0x444039)
    static let n800 = Color(hex: 0x2A2823)
    static let n900 = Color(hex: 0x1A1916)

    // Семантика светлой темы
    static let bg = n100                // фон приложения
    static let surface = n50            // вторичная поверхность (ячейки выбора)
    static let surfaceRaised = n0       // карточки
    static let lineSoft = n150          // сепараторы внутри карточек
    static let line = n200              // общий hairline
    static let lineStrong = n300        // бордеры контролов (1.5px)
    static let text = n900
    static let text2 = n600             // вторичный текст
    static let text3 = n500             // приглушённый текст, капсы
    static let textDisabled = n400
    static let icon = n700
    static let iconMuted = n400
    static let fill = n900              // тёмный контрол на светлом (primary)
    static let fillFg = n50

    // Тёмные «инструментальные» поверхности (панель свободных денег, отладка)
    static let inkBg = Color(hex: 0x131310)
    static let inkSurface = Color(hex: 0x1D1D19)
    static let inkRaised = Color(hex: 0x292924)
    static let inkLine = Color(hex: 0x34342E)
    static let inkFg = Color(hex: 0xECEAE3)
    static let inkMuted = Color(hex: 0x8B887F)

    // Signal — единственный цвет: живое сейчас, критичное, деструктивное
    static let signal = Color(hex: 0xBF4A2A)
    static let signalSoft = Color(hex: 0xD96A4A)
    static let signalFaint = Color(hex: 0xF0D9D0)

    /// Тёплая базовая тень Caliper (rgba(20,18,12,…)).
    static let shadowTint = Color(hex: 0x14120C)

    // Моушен: быстрый, механический, без баунса — cubic-bezier(0.2, 0, 0.1, 1)
    static func ease(_ duration: Double = 0.16) -> Animation {
        .timingCurve(0.2, 0, 0.1, 1, duration: duration)
    }
}

// MARK: Шрифты

/// JetBrains Mono вложен в бандл (OFL); Archivo кириллицы не имеет, поэтому
/// гротеск — системный, следующий шаг стека самого кита («Helvetica Neue…»).
enum CaliperFonts {
    static func register() {
        for name in ["JetBrainsMono-Regular", "JetBrainsMono-Medium"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf",
                                            subdirectory: nil) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// UI-гротеск Caliper (стек: Archivo → системный).
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Технический моно для данных: суммы, даты, статусные строки.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular", size: size)
    }
}

/// Сигнатура Caliper: крошечные капсы с трекингом 0.14em.
struct Cap: View {
    let text: String
    var color: Color = Theme.text3

    init(_ text: String, color: Color = Theme.text3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.sans(11, .medium))
            .tracking(1.54)
            .foregroundStyle(color)
    }
}

extension View {
    /// Карточка Caliper: белая, радиус 16, две мягкие тени, без бордера.
    func caliperCard(radius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(Theme.surfaceRaised)
                .shadow(color: Theme.shadowTint.opacity(0.07), radius: 1.5, y: 1)
                .shadow(color: Theme.shadowTint.opacity(0.05), radius: 8, y: 6)
        )
    }

    /// Тёмная «инструментальная» панель на светлом экране.
    func inkPanel(radius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius)
                .fill(Theme.inkSurface)
                .overlay(RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.inkLine, lineWidth: 1))
        )
    }
}

// MARK: Кнопки

/// Кнопки Caliper: высота 50 (компакт 40), радиус 8, подпись 13/600 с трекингом;
/// нажатие — сжатие до 0.975 без баунса.
struct CaliperButtonStyle: ButtonStyle {
    enum Kind {
        case primary     // тёмная заливка n900
        case secondary   // светлая, бордер 1.5 n300
        case ghost       // прозрачная, текст fg-2
        case danger      // прозрачная, бордер и текст signal
        case signal      // заливка signal — «запись»: живое действие сейчас
    }

    var kind: Kind = .primary
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(13, .semibold))
            .tracking(0.26)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 16 : 22)
            .frame(height: compact ? 40 : 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background(pressed: configuration.isPressed))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(border, lineWidth: 1.5))
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Theme.ease(0.09), value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.textDisabled }
        switch kind {
        case .primary: return Theme.fillFg
        case .secondary: return Theme.text
        case .ghost: return Theme.text2
        case .danger: return Theme.signal
        case .signal: return .white
        }
    }

    private func background(pressed: Bool) -> Color {
        guard isEnabled else {
            return kind == .primary || kind == .signal ? Theme.n200 : .clear
        }
        switch kind {
        case .primary: return pressed ? Theme.n700 : Theme.fill
        case .secondary: return Theme.surfaceRaised
        case .ghost, .danger: return .clear
        case .signal: return pressed ? Theme.signalSoft : Theme.signal
        }
    }

    private var border: Color {
        guard isEnabled else { return kind == .secondary ? Theme.line : .clear }
        switch kind {
        case .secondary: return Theme.lineStrong
        case .danger: return Theme.signal
        default: return .clear
        }
    }
}

extension ButtonStyle where Self == CaliperButtonStyle {
    static func caliper(_ kind: CaliperButtonStyle.Kind = .primary,
                        compact: Bool = false) -> CaliperButtonStyle {
        CaliperButtonStyle(kind: kind, compact: compact)
    }
}

// MARK: Тап-зоны (без изменений — эргономика, не стиль)

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

    /// Тап-зона текстового поля: сам TextField ловит тап только по кадру высотой
    /// в строку текста, поэтому область растягивается (не ниже `minHeight`) и любой
    /// тап по ней переводит фокус в поле. На самом поле нужен парный `.focused(...)`.
    func tapFocuses<F: Hashable>(_ focus: FocusState<F?>.Binding, equals value: F,
                                 minHeight: CGFloat = 44) -> some View {
        frame(minHeight: minHeight)
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = value }
    }

    /// То же для единственного поля на экране (FocusState<Bool>).
    func tapFocuses(_ focus: FocusState<Bool>.Binding,
                    minHeight: CGFloat = 44) -> some View {
        frame(minHeight: minHeight)
            .contentShape(Rectangle())
            .onTapGesture { focus.wrappedValue = true }
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
/// Тумблер Caliper: 50×30, трек n300 → заливка n900, белая шайба 24.
struct SwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            withAnimation(Theme.ease()) { isOn.toggle() }
        } label: {
            HStack {
                label().frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(isOn ? Theme.fill : Theme.lineStrong)
                    .frame(width: 50, height: 30)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Theme.n0)
                            .frame(width: 24, height: 24)
                            .padding(3)
                            .shadow(color: Theme.shadowTint.opacity(0.06), radius: 1, y: 1)
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
            Rectangle().fill(Theme.lineStrong).frame(width: 1, height: 18)
            step("plus") { if value < range.upperBound { value += 1 } }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.n200))
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.icon)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Сегмент-контрол Caliper: подложка n200, радиус 8, активная кнопка — белая
/// плашка с малой тенью. Замена системному .segmented, который не стилизуется.
struct CaliperSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(Theme.ease(0.09)) { selection = option.value }
                } label: {
                    Text(option.label.uppercased())
                        .font(.sans(12, .semibold))
                        .tracking(0.48)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selection == option.value ? Theme.text : Theme.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == option.value ? Theme.surfaceRaised : .clear)
                                .shadow(color: Theme.shadowTint.opacity(
                                    selection == option.value ? 0.06 : 0), radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.n200))
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
                .font(.mono(14, medium: true))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.lineStrong, lineWidth: 1.5))
                )
                .tapPadded(visualHeight: 36)
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
            Cap("Число месяца")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                      spacing: 8) {
                ForEach(1...28, id: \.self) { d in
                    Button {
                        day = d
                        dismiss()
                    } label: {
                        Text(String(d))
                            .font(.mono(15, medium: d == day))
                            .foregroundStyle(d == day ? Theme.fillFg : Theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(d == day ? Theme.fill : Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("1–28 — такие числа есть в любом месяце")
                .font(.sans(12))
                .foregroundStyle(Theme.text3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.height(340)])
        .presentationBackground(Theme.surfaceRaised)
        .presentationCornerRadius(22)
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
