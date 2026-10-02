import SwiftUI

// Primary runtime: inspectable WKWebView developer shell.
// Safari container remains in the repository only as a fallback/reference path.
struct ContentView: View {
    @ViewBuilder
    var body: some View {
        #if DEBUG
        if let sequence =
            ABBenchmarkSequenceConfig.current
        {
            ABBenchmarkSequenceView(
                config: sequence
            )
        } else if let benchmark =
            ABBenchmarkConfig.current
        {
            ABBenchmarkView(
                config: benchmark
            )
        } else {
            ChatGPTWebView()
                .ignoresSafeArea()
        }
        #else
        ChatGPTWebView()
            .ignoresSafeArea()
        #endif
    }
}
