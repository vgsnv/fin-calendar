import SwiftUI

@main
struct IzvestnoeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TapeView()
                .environment(model)
        }
    }
}
