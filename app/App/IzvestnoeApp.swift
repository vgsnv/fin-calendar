import SwiftUI

@main
struct IzvestnoeApp: App {
    @State private var model = AppModel()

    init() {
        // JetBrains Mono из бандла: Info.plist генерируется сборкой,
        // ключа UIAppFonts в нём нет — регистрируем через CoreText.
        CaliperFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.needsOnboarding {
                    OnboardingView()
                } else {
                    TapeView()
                }
            }
            .environment(model)
        }
    }
}
