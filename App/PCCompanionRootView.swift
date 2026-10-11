import SwiftUI

struct PCCompanionRootView: View {
    @AppStorage("PCCompanion.selected") private var remote = false
    @State private var confirmSwitch = false
    var body: some View {
        Group {
            if remote {
                PCCompanionView(returnToWeb: { remote = false })
            } else {
                ChatGPTWebView().ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button { confirmSwitch = true } label: {
                            Label("PC 同步",systemImage:"desktopcomputer")
                                .font(.caption.weight(.semibold)).padding(9)
                                .background(.regularMaterial,in:Capsule())
                        }.padding(.leading,12).padding(.top,52)
                    }
                    .alert("切换到 PC 同步？",isPresented:$confirmSwitch) {
                        Button("取消",role:.cancel) {}
                        Button("切换") { remote = true }
                    } message: {
                        Text("请先处理手机网页中尚未发送的草稿。切换后使用原生阅读界面，PC Chrome 保持原状。")
                    }
            }
        }
    }
}
