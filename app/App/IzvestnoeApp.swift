import SwiftUI

@main
struct IzvestnoeApp: App {
    var body: some Scene {
        WindowGroup {
            TapeView(model: .demo())
        }
    }
}
