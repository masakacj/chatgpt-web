import SwiftUI

// Primary runtime: inspectable WKWebView developer shell.
// Safari container remains in the repository only as a fallback/reference path.
struct ContentView: View {
    var body: some View {
        ChatGPTWebView()
            .ignoresSafeArea()
    }
}
