import SwiftUI

@main
struct IzvestnoeApp: App {
    @State private var model = AppModel()

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
