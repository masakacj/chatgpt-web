import SwiftUI

struct PCCompanionRootView<WebContent: View>: View {
    @AppStorage("PCCompanion.selected") private var remote = true
    @State private var confirmSwitch = false
    let webContent: () -> WebContent
    init(@ViewBuilder webContent: @escaping () -> WebContent) { self.webContent = webContent }
    var body: some View {
        Group {
            #if DEBUG
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let oldFixture = testing && (ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture") || ProcessInfo.processInfo.arguments.contains("--pc-companion-network-fixture"))
            let sharedFixture = testing && ProcessInfo.processInfo.arguments.contains("--shared-tab-fixture")
            #else
            let testing = false
            let oldFixture = false
            let sharedFixture = false
            #endif
            if oldFixture {
                // Retain previous transport/persistence regression fixtures.
                PCCompanionView(returnToWeb: { remote = false })
            } else if sharedFixture || (remote && !testing) {
                SharedTabScreen(returnToWeb: { remote = false })
            } else {
                // The original WebKit smoke exercises this explicit fallback.
                webContent().ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button { confirmSwitch = true } label: {
                            Label("PC 原生", systemImage: "desktopcomputer")
                                .font(.caption.weight(.semibold)).padding(9)
                                .background(.regularMaterial, in: Capsule())
                        }.padding(.leading, 12).padding(.top, 52)
                    }
                    .alert("切换到原生 PC 镜像？", isPresented: $confirmSwitch) {
                        Button("取消", role: .cancel) {}
                        Button("切换") { remote = true }
                    } message: {
                        Text("请先保留当前手机网页里的草稿。原生模式与选定的 PC 标签页共用对话，手机输入仅在点击发送后提交。")
                    }
            }
        }
    }
}
