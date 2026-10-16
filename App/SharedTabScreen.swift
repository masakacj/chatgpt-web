import SwiftUI
import UIKit

private struct STSelectedInteraction: Identifiable {
    let card: PCInteractionCard; let button: PCInteractionButton; let document: String
    var id: String { button.id }
}

struct SharedTabScreen: View {
    @StateObject private var model = SharedTabModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var sidebar = false
    @State private var modelSheet = false
    @State private var query = ""
    @State private var expanded = Set<String>()
    @State private var followLatest = true
    @State private var interaction: STSelectedInteraction?
    @FocusState private var editing: Bool
    let returnToWeb: () -> Void

    private func dismissKeyboard() {
        editing = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private func openSidebar() {
        dismissKeyboard(); query = ""
        withAnimation(.easeOut(duration: 0.16)) { sidebar = true }
        Task { await model.catalog() }
    }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    header
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 6)
                            .accessibilityIdentifier("shared.error")
                    }
                    transcript
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(Color(uiColor: .systemBackground))
                if sidebar {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { sidebar = false; dismissKeyboard() }
                    library.frame(width: min(UIScreen.main.bounds.width * 0.88, 370)).transition(.move(edge: .leading))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $model.needsSettings) { settings }
            .sheet(isPresented: $modelSheet) { modelPicker }
            .sheet(item: $interaction) { selected in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(selected.card.title).font(.title3.weight(.semibold))
                            Text(selected.card.summary).textSelection(.enabled)
                            Text("将在当前 PC 对话中执行一次“\(selected.button.label)”。").font(.footnote).foregroundStyle(.secondary)
                            Button("确认“\(selected.button.label)”") {
                                interaction = nil
                                Task { await model.interact(selected.button, document: selected.document) }
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("shared.interaction.confirm")
                        }.padding(24)
                    }.navigationTitle("确认操作").navigationBarTitleDisplayMode(.inline)
                     .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { interaction = nil } } }
                }.presentationDetents([.medium, .large])
            }
            .task { await model.resume() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.resume() } }
                else if phase == .background { model.pause() }
            }
            .onDisappear { model.pause() }
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: openSidebar) {
                Image(systemName: "line.3.horizontal").font(.system(size: 21)).frame(width: 44, height: 44)
            }.accessibilityLabel("打开侧边栏").accessibilityIdentifier("shared.sidebar")
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    dismissKeyboard()
                    modelSheet = true
                    Task { await model.loadModelChoices() }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.currentModelName).font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(.primary)
                }
                .disabled(!model.canOpenModelPicker)
                .accessibilityLabel("选择模型和思考强度，当前：\(model.currentModelName)")
                .accessibilityIdentifier("shared.model.open")
                Text(model.snapshot?.title ?? (model.loading ? "正在切换对话" : "PC 共享标签页"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("shared.title")
            }
            Spacer(minLength: 4)
            Button { dismissKeyboard(); Task { await model.newChat() } } label: { Image(systemName: "square.and.pencil").font(.system(size: 20)).frame(width: 40, height: 44) }
                .disabled(!model.online || model.busy).accessibilityLabel("新建聊天").accessibilityIdentifier("shared.new")
            Menu {
                Button("连接设置", systemImage: "desktopcomputer") { dismissKeyboard(); model.needsSettings = true }
                Button("重新连接", systemImage: "arrow.clockwise") { Task { model.pause(); await model.resume() } }
                Button("原网页模式", systemImage: "safari") { Task { await model.disconnect(); returnToWeb() } }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }.accessibilityLabel("更多")
        }.foregroundStyle(.primary).padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 4)
    }
    private var modelPicker: some View {
        NavigationStack {
            List {
                Section("PC 当前设置") {
                    HStack {
                        Text("模型")
                        Spacer()
                        Text(model.currentModelName).foregroundStyle(.secondary).lineLimit(2)
                            .accessibilityIdentifier("shared.model.current")
                    }
                    if let effort = model.currentThinkingEffort {
                        HStack {
                            Text("思考强度")
                            Spacer()
                            Text(effort).foregroundStyle(.secondary)
                                .accessibilityIdentifier("shared.model.effort")
                        }
                    }
                }
                Section("PC 网页提供的选项") {
                    if model.modelLoading {
                        HStack(spacing: 10) { ProgressView(); Text("正在读取模型菜单…") }
                    } else if !model.modelMenuAvailable || model.modelOptions.isEmpty {
                        Text("暂无可选择的模型或思考强度").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.modelOptions) { option in
                            Button {
                                Task {
                                    let confirmed = await model.chooseModelOption(option)
                                    if confirmed { modelSheet = false }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Text(option.label).foregroundStyle(.primary)
                                    Spacer()
                                    if option.selected == true { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    if option.submenu == true { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                                }.contentShape(Rectangle())
                            }
                            .disabled(model.modelLoading || model.actionPending != nil)
                            .accessibilityIdentifier("shared.model.option.\(option.id)")
                        }
                    }
                }
                if let notice = model.modelPickerNotice {
                    Section { Text(notice).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("shared.model.notice") }
                }
                Section {
                    Text("模型和思考强度均来自当前 PC ChatGPT 网页；没有出现在官方菜单中的选项无法从手机启用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("模型与思考强度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { modelSheet = false }
                        .accessibilityIdentifier("shared.model.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.loadModelChoices() }
                    } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.modelLoading || !model.canOpenModelPicker)
                        .accessibilityLabel("重新读取 PC 模型菜单")
                        .accessibilityIdentifier("shared.model.refresh")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            if model.canLoadHistory {
                                Button {
                                    followLatest = false; let anchor = model.displayMessages.first?.id
                                    Task { await model.loadEarlier(); if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
                                } label: { HStack { Spacer(); if model.historyLoading { ProgressView() }; Text("查看更早消息"); Spacer() }.font(.caption) }
                                    .accessibilityIdentifier("shared.history")
                            }
                            if !model.online && model.snapshot != nil {
                                HStack { Text("离线快照"); Spacer(); Button("重连") { Task { await model.resume() } } }
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if model.loading {
                                HStack { ProgressView(); Text("正在读取 PC 当前对话").foregroundStyle(.secondary) }.padding(.top, 30)
                            } else if model.displayMessages.isEmpty {
                                VStack(spacing: 14) {
                                    Text("有什么可以帮你？").font(.title2.weight(.semibold))
                                    if !model.online { Button("连接 PC") { model.needsSettings = true; Task { await model.loadTabs() } }.buttonStyle(.bordered) }
                                    else if let title = model.projectTitle { Text("在 \(title) 中开始新聊天").foregroundStyle(.secondary) }
                                }.frame(maxWidth: .infinity).padding(.top, 90)
                            }
                            ForEach(model.displayMessages) { message in
                                STMessageView(message: message, onLink: { link in Task { await model.followRemoteLink(link) } }).id(message.id)
                            }
                            if model.thinking {
                                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("思考中").foregroundStyle(.secondary) }
                                    .accessibilityIdentifier("shared.thinking")
                            }
                            ForEach(model.snapshot?.interactions ?? []) { card in
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(card.title, systemImage: "hand.tap").font(.subheadline.weight(.semibold))
                                    Text(card.summary).font(.subheadline).textSelection(.enabled)
                                    ForEach(card.buttons) { button in
                                        Button(button.label) { interaction = STSelectedInteraction(card: card, button: button, document: model.snapshot?.documentId ?? "") }
                                            .buttonStyle(.bordered).disabled(button.disabled || !model.online || model.busy || model.actionPending != nil)
                                    }
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                            Color.clear.frame(height: 1).id("shared.bottom")
                                .onAppear { followLatest = true }.onDisappear { followLatest = false }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height), alignment: .top)
                        .background {
                            // A visible-color backing gives blank transcript space a hit target;
                            // it stays behind messages/links rather than intercepting controls.
                            Color(uiColor: .systemBackground).contentShape(Rectangle()).onTapGesture(perform: dismissKeyboard)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("shared.transcript")
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                    .onAppear { proxy.scrollTo("shared.bottom", anchor: .bottom) }
                    .onChange(of: model.snapshot?.conversationId) { _, _ in followLatest = true; proxy.scrollTo("shared.bottom", anchor: .bottom) }
                    .onChange(of: model.displayMessages.last?.text) { _, _ in if followLatest { proxy.scrollTo("shared.bottom", anchor: .bottom) } }
                    if !followLatest {
                        Button { dismissKeyboard(); followLatest = true; proxy.scrollTo("shared.bottom", anchor: .bottom) } label: {
                            Image(systemName: "arrow.down").frame(width: 40, height: 40).background(.regularMaterial, in: Circle()).overlay(Circle().stroke(.quaternary))
                        }.accessibilityLabel("回到最新消息").padding(14)
                    }
                }
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 7) {
            if model.currentPending != nil || model.actionPending != nil {
                Button("核对发送／操作回执") { Task { await model.checkReceipts() } }
                    .font(.caption).accessibilityIdentifier("shared.receipt")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("发送消息", text: Binding(get: { model.text }, set: { model.edited($0) }), axis: .vertical)
                    .lineLimit(1...6).font(.body).focused($editing).padding(.vertical, 11).padding(.leading, 15)
                    .accessibilityIdentifier("shared.composer")
                if model.canStopGeneration {
                    Button {
                        dismissKeyboard()
                        Task { await model.stopGeneration() }
                    } label: {
                        Image(systemName: "stop.fill").font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .background(Color.primary, in: Circle())
                    }.padding(.bottom, 5)
                     .accessibilityLabel("停止生成")
                     .accessibilityIdentifier("shared.stop")
                }
                Button {
                    dismissKeyboard()
                    Task { await model.send() }
                } label: {
                    Group { if model.busy { ProgressView().tint(Color(uiColor: .systemBackground)) } else { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)) } }
                        .frame(width: 36, height: 36).foregroundStyle(Color(uiColor: .systemBackground))
                        .background(Color.primary.opacity(model.canSubmit ? 1 : 0.3), in: Circle())
                }.disabled(!model.canSubmit).padding(.bottom, 5).padding(.trailing, 6)
                    .accessibilityLabel("发送").accessibilityIdentifier("shared.send")
            }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 25))
            Text(model.status).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).accessibilityIdentifier("shared.status")
            #if DEBUG
            if model.fixture { Text(SharedTabFixtureProtocol.counters).font(.system(size: 9)).accessibilityIdentifier("shared.fixture.counters") }
            #endif
        }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 3).background(Color(uiColor: .systemBackground))
    }
    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Button { sidebar = false; dismissKeyboard() } label: { Image(systemName: "xmark").frame(width: 40, height: 44) }.accessibilityLabel("关闭侧边栏")
                Text("聊天").font(.headline); Spacer()
                Button { sidebar = false; dismissKeyboard(); Task { await model.newChat() } } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }.accessibilityLabel("侧边栏新建聊天")
            }.padding(.horizontal, 10)
            HStack(spacing: 8) {
                TextField("搜索全部历史", text: $query).submitLabel(.search).onSubmit { Task { if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await model.catalog() } else { await model.search(query) } } }
                    .accessibilityLabel("搜索全部历史").accessibilityIdentifier("shared.search.input")
                Button { dismissKeyboard(); Task { if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await model.catalog() } else { await model.search(query) } } } label: { Image(systemName: "magnifyingglass").frame(width: 36, height: 36) }
                    .accessibilityLabel("搜索历史").accessibilityIdentifier("shared.search")
            }.padding(.leading, 12).padding(.trailing, 5).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)
            if model.libraryLoading { ProgressView().padding(8) }
            List {
                if !query.isEmpty {
                    Section("搜索结果") {
                        ForEach(model.chats) { chat in chatRow(chat) }
                        if model.searchHasMore { Button("加载更多搜索结果") { Task { await model.search(query, more: true) } }.disabled(model.libraryLoading) }
                    }
                } else {
                    Section("项目") {
                        ForEach(model.projects) { project in
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(project.id) }, set: { value in
                                if value { expanded.insert(project.id); if project.collapsed { Task { await model.expand(project) } } } else { expanded.remove(project.id) }
                            })) {
                                Button { sidebar = false; dismissKeyboard(); Task { await model.newChat(project: project) } } label: { Label("在项目中新建聊天", systemImage: "plus") }
                                    .accessibilityIdentifier("shared.project.new.\(project.id)")
                                ForEach(model.chats.filter { $0.projectId == project.id }) { chat in chatRow(chat) }
                                if project.hasMore { Button("加载更多项目对话") { Task { await model.expand(project, more: true) } } }
                            } label: { Text(project.title).lineLimit(1) }
                        }
                    }
                    Section("最近对话") { ForEach(model.chats.filter { $0.projectId == nil }) { chat in chatRow(chat) } }
                }
                Section {
                    Text(model.searchNotice).font(.caption).foregroundStyle(.secondary)
                    Button("连接设置") { sidebar = false; dismissKeyboard(); model.needsSettings = true }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
        }.background(Color(uiColor: .secondarySystemBackground))
        // Do not put one identifier on this whole container: SwiftUI can propagate
        // it to the search field and replace the field's own accessibility identity.
    }
    private func chatRow(_ chat: STChat) -> some View {
        Button {
            dismissKeyboard(); sidebar = false
            Task { await model.open(chat) }
        } label: {
            HStack {
                Text(chat.title).lineLimit(2).foregroundStyle(.primary)
                Spacer(minLength: 4)
                if chat.id == model.snapshot?.conversationId { Image(systemName: "checkmark").font(.caption) }
                else if chat.status == "running" { ProgressView().controlSize(.mini) }
                else if chat.readState == "unread" { Circle().frame(width: 6, height: 6) }
            }
        }.disabled(model.busy || model.libraryLoading).accessibilityIdentifier("shared.chat.\(chat.id)")
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("PC 连接") {
                    TextField("HTTPS 服务地址", text: $model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("配对密钥", text: $model.pairingKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await model.chooseStageBridge() }
                    } label: {
                        Label("使用新版 PC Bridge 测试通道", systemImage: "desktopcomputer")
                    }
                    .accessibilityIdentifier("shared.useTestBridge")
                    Text("在 PC 上打开 http://127.0.0.1:13213/local/pair，复制配对密钥到手机。测试服务独立于旧正式通道。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("读取 PC 标签页") { Task { await model.loadTabs() } }.disabled(model.busy).accessibilityIdentifier("shared.connect")
                    Text("手机与选中的 PC 标签页双向切换对话。输入草稿只在手机保存，点击发送才提交。").font(.caption)
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
                Section("选择共用的 ChatGPT 标签页") {
                    ForEach(model.tabs) { tab in
                        Button { Task { await model.bind(tab) } } label: {
                            HStack { Text(tab.title).lineLimit(2); Spacer(); if model.selectedTabId == tab.tabId { Image(systemName: "checkmark") } }
                        }.disabled(model.busy).accessibilityIdentifier("shared.bind.\(tab.tabId)")
                    }
                }
                Section {
                    Text("PC 需保持在线；切到其他浏览器标签不会更换绑定。绑定页关闭后，请在这里重新选择。").font(.caption).foregroundStyle(.secondary)
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")（\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")）").font(.caption)
                    Button("原网页模式") { Task { await model.disconnect(); model.needsSettings = false; returnToWeb() } }
                }
            }.navigationTitle("连接设置").navigationBarTitleDisplayMode(.inline)
             .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.needsSettings = false } } }
        }
    }
}

private struct STMessageView: View {
    let message: PCRemoteMessage
    let onLink: (PCRemoteLink) -> Void
    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 42)
                VStack(alignment: .leading, spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text).textSelection(.enabled)
                    }
                    ForEach(Array(message.blocks.enumerated()).filter { ["image", "attachment"].contains($0.element.kind) }, id: \.offset) { _, block in
                        STRemoteMediaBlock(block: block)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            }.frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if message.blocks.isEmpty { Text(LocalizedStringKey(message.text)).textSelection(.enabled).lineSpacing(5) }
                else {
                    ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                        switch block.kind {
                        case "code":
                            ScrollView(.horizontal) {
                                Text(block.text).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(12)
                            }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        case "table":
                            STRemoteTableBlock(block: block)
                        case "image", "attachment":
                            STRemoteMediaBlock(block: block)
                        case "quote":
                            Text(block.text).foregroundStyle(.secondary).padding(.leading, 12)
                                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 3) }
                        case "heading": Text(block.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                        case "list": HStack(alignment: .top, spacing: 8) { Text("•"); Text(LocalizedStringKey(block.text)).textSelection(.enabled) }
                        default: Text(LocalizedStringKey(block.text)).textSelection(.enabled).lineSpacing(5)
                        }
                    }
                }
                ForEach(Array(message.links.enumerated()), id: \.offset) { _, link in
                    if link.interactionId != nil && link.interactionRevision != nil {
                        Button { onLink(link) } label: {
                            Label("在 PC 打开：" + (link.title.isEmpty ? "网页链接" : link.title), systemImage: "link")
                                .font(.footnote)
                        }.accessibilityIdentifier("shared.pcLink")
                    } else {
                        Label((link.title.isEmpty ? "网页链接" : link.title) + " · 请在 PC 查看", systemImage: "link")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc").font(.system(size: 14)) }.accessibilityLabel("复制消息")
                    if message.truncated { Text("此段已截断，完整内容请在 PC 查看").font(.caption2) }
                }.foregroundStyle(.secondary).padding(.top, 3)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

 
// Only images with a usable HTTPS URL are fetched on the phone. Unavailable
// PC blob/auth-only media are still represented, not silently dropped.
private struct STRemoteMediaBlock: View {
    let block: PCRemoteBlock
    var body: some View {
        if block.kind == "image" {
            if let raw = block.url, let remote = URL(string: raw),
               remote.scheme == "https", remote.user == nil, remote.password == nil,
               let host = remote.host, host.contains(".") {
                AsyncImage(url: remote) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Label(block.text.isEmpty ? "图片" : block.text, systemImage: "photo")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityLabel(block.text.isEmpty ? "PC 网页图片" : block.text)
            } else {
                Label(block.text.isEmpty ? "仅 PC 可查看的图片" : block.text + " · 请在 PC 查看", systemImage: "photo")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Label(block.text, systemImage: "doc")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct STRemoteTableBlock: View {
    let block: PCRemoteBlock
    var body: some View {
        if let rows = block.rows, !rows.isEmpty {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell).font(rowIndex == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                    .textSelection(.enabled)
                                    .frame(minWidth: 130, maxWidth: 200, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 9)
                            }
                        }
                        .background(rowIndex == 0 ? Color(uiColor: .tertiarySystemFill) : Color.clear)
                        .overlay(alignment: .bottom) { Rectangle().fill(.quaternary).frame(height: 0.5) }
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            ScrollView(.horizontal) {
                Text(block.text).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled).padding(12)
            }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
