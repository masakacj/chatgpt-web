import SwiftUI

@main
struct ChatGPTWebApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(nil)
        }
    }
}
