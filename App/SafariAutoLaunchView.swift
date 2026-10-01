import SwiftUI
import UIKit

private let chatGPTSafariURL =
    URL(string: "https://chatgpt.com/")!

struct SafariAutoLaunchView: View {
    @State private var hasLaunchedSafari =
        false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "safari")
                .font(.system(size: 40))
                .accessibilityHidden(true)

            Text("ChatGPT · Safari")
                .font(.headline)

            Text(
                "ChatGPT 会在 Safari 中打开。启用扩展并允许 chatgpt.com 后，优化脚本会在页面加载时自动注入。"
            )
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Button(
                "打开 ChatGPT"
            ) {
                openChatGPT()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .task {
            guard !hasLaunchedSafari else {
                return
            }

            hasLaunchedSafari = true

            try? await Task.sleep(
                for: .milliseconds(180)
            )

            openChatGPT()
        }
    }

    private func openChatGPT() {
        UIApplication.shared.open(
            chatGPTSafariURL,
            options: [:],
            completionHandler: nil
        )
    }
}
