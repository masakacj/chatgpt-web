import SwiftUI

struct PCInteractionButton: Codable, Identifiable {
    let id: String; let label: String; let revision: String
    let disabled: Bool; let requiresConfirmation: Bool
}
struct PCInteractionCard: Codable, Identifiable {
    let id: String; let title: String; let summary: String; let buttons: [PCInteractionButton]
}
struct PCInteractionSelection: Identifiable {
    let card: PCInteractionCard; let button: PCInteractionButton; let document: String
    var id: String { button.id }
}
struct PCHistoryPage: Codable {
    let schema: Int; let documentId: String; let conversationId: String
    let messages: [PCRemoteMessage]; let cursor: String?; let hasMore: Bool; let source: String
}
struct PCSavedHistory: Codable {
    let conversation: String; let document: String; let messages: [PCRemoteMessage]; let cursor: String?; let hasMore: Bool
}
struct PCInteractionPending: Codable {
    let id: String; let server: String; let conversation: String
}

struct NativeConversationScreen: View {
    @ObservedObject var model: PCCompanionModel
    let openSettings: () -> Void
    let returnToWeb: () -> Void
    @State private var showLibrary = false
    @State private var confirmDraft = false
    @State private var confirmReceipt = false
    @State private var interaction: PCInteractionSelection?
    @State private var followLatest = true
    @FocusState private var editing: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
                        .accessibilityIdentifier("pc.remote.error")
                }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--pc-companion-network-fixture") {
                    Text(PCCompanionTestProtocol.counters).font(.caption2).accessibilityIdentifier("pc.fixture.counters")
                }
                #endif
                transcript
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLibrary) { PCSidebarView(model: model) }
            .sheet(item: $interaction) { selected in interactionConfirmation(selected) }
            .alert("采用 PC 草稿？", isPresented: $confirmDraft) {
                Button("取消", role: .cancel) {}
                Button("替换手机草稿", role: .destructive) { model.usePCDraft() }
            } message: { Text("只替换手机输入框，不会发送消息。请先复制需要保留的文字。") }
            .alert("已检查 PC 发送结果？", isPresented: $confirmReceipt) {
                Button("取消", role: .cancel) {}
                Button("已核对，解除等待") { model.acknowledgeManualCheck() }
            } message: { Text("请先在 PC 确认消息是否已发送。这里只解除等待，不会重发消息。") }
        }
    }
    private var header: some View {
        HStack(spacing: 14) {
            Button { editing = false; showLibrary = true } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 21, weight: .medium)).frame(width: 36, height: 42)
            }.accessibilityLabel("对话").accessibilityIdentifier("pc.remote.sidebar")
            VStack(alignment: .leading, spacing: 2) {
                Text("ChatGPT").font(.system(size: 20, weight: .semibold))
                Text(model.snapshot?.title ?? "PC 同步").font(.caption).lineLimit(1).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if model.working || model.reconnecting { ProgressView().controlSize(.small) }
            Button(action: openSettings) { Image(systemName: "slider.horizontal.3").font(.system(size: 20)).frame(width: 34, height: 42) }.accessibilityLabel("连接")
            Menu {
                Button("原网页") { Task { await model.disconnect(); returnToWeb() } }
                Button("重连 PC") { Task { await model.resume() } }
                Button("刷新对话列表") { showLibrary = true }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 42) }.accessibilityLabel("更多")
        }.foregroundStyle(.primary).padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if model.snapshot != nil {
                            if model.canLoadHistory {
                                Button {
                                    let anchor = model.displayMessages.first?.id
                                    followLatest = false
                                    Task {
                                        await model.loadHistory()
                                        if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                    }
                                } label: {
                                    HStack { Spacer(); if model.historyLoading { ProgressView().controlSize(.small) }; Text("查看更早消息").font(.caption); Spacer() }
                                }.disabled(model.historyLoading || !model.online).accessibilityIdentifier("pc.history.more")
                            } else if model.historyReachedStart {
                                Text("已显示 PC 当前加载的历史").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                            }
                            if !model.online {
                                HStack {
                                    Text("离线快照").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("重连") { Task { await model.resume() } }.font(.caption).accessibilityIdentifier("pc.remote.reconnect")
                                }
                            }
                            ForEach(model.displayMessages) { message in
                                messageRow(message).id(message.id)
                            }
                            if model.isThinking {
                                HStack(spacing: 9) { ProgressView().controlSize(.small); Text("思考中").font(.body).foregroundStyle(.secondary) }
                                    .padding(.vertical, 8).accessibilityIdentifier("pc.response.thinking")
                            } else if model.snapshot?.status == "loading" {
                                HStack(spacing: 9) { ProgressView(); Text("正在加载对话").foregroundStyle(.secondary) }
                            }
                            ForEach(model.snapshot?.interactions ?? []) { card in
                                interactionCard(card)
                            }
                            if model.snapshot?.status == "waiting" && (model.snapshot?.interactions ?? []).isEmpty {
                                Label("需要在 PC 处理此交互", systemImage: "hand.tap").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Text("有什么可以帮你？").font(.title2.weight(.semibold))
                                Text("连接 PC，查看和继续你的对话").foregroundStyle(.secondary)
                                Button("连接 PC", action: openSettings).buttonStyle(.bordered)
                            }.frame(maxWidth: .infinity).padding(.top, 110)
                        }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { followLatest = true }.onDisappear { followLatest = false }
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.snapshot?.conversationId) { _, _ in followLatest = true; proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.snapshot?.messages.last?.text) { _, _ in if followLatest { proxy.scrollTo("end", anchor: .bottom) } }
                if !followLatest {
                    Button { editing = false; followLatest = true; proxy.scrollTo("end", anchor: .bottom) } label: {
                        Image(systemName: "arrow.down").font(.body.weight(.medium)).frame(width: 38, height: 38)
                            .background(.regularMaterial, in: Circle()).overlay(Circle().stroke(.quaternary))
                    }.accessibilityLabel("最新消息").padding(16)
                }
            }
        }
    }
    private func messageRow(_ message: PCRemoteMessage) -> some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 10) {
            if message.role == "user" {
                HStack {
                    Spacer(minLength: 48)
                    Text(message.text).textSelection(.enabled).padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                }
            } else {
                PCAnswerBody(message: message)
                HStack(spacing: 18) {
                    Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc").font(.system(size: 14)) }.accessibilityLabel("复制消息")
                    if message.truncated { Text("部分正文，请在 PC 查看完整内容").font(.caption2) }
                }.foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if model.hasPending {
                HStack {
                    Button("核对发送回执") { Task { await model.checkReceipt() } }.accessibilityIdentifier("pc.remote.receipt")
                    Button("已在 PC 核对") { confirmReceipt = true }
                }.font(.caption)
            }
            if model.hasPendingInteraction {
                Button("核对操作回执") { Task { await model.checkInteractionReceipt() } }.font(.caption).accessibilityIdentifier("pc.action.receipt")
            }
            VStack(spacing: 3) {
                TextEditor(text: Binding(get: { model.draft.text }, set: { model.edited($0) }))
                    .focused($editing).scrollContentBackground(.hidden).font(.body)
                    .frame(minHeight: 40, maxHeight: 105).padding(.horizontal, 8).padding(.top, 5)
                    .accessibilityIdentifier("pc.remote.composer")
                HStack {
                    Menu {
                        Button("同步草稿") { Task { await model.syncDraft() } }.disabled(!model.canWrite)
                        Button("采用 PC 草稿") { confirmDraft = true }.disabled(model.working || model.snapshot == nil)
                    } label: { Image(systemName: "plus").font(.system(size: 22)).frame(width: 36, height: 36) }.accessibilityLabel("输入选项")
                    Text(model.online ? "PC 已连接" : "未连接").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button { Task { await model.send() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).frame(width: 34, height: 34)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .background(Color.primary.opacity(model.canWrite && !model.draft.text.isEmpty ? 1 : 0.25), in: Circle())
                    }.disabled(!model.canWrite || model.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送")
                }.padding(.horizontal, 10).padding(.bottom, 7)
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26))
            Text(model.status).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).accessibilityIdentifier("pc.remote.status")
        }.padding(.horizontal, 12).padding(.top, 5).padding(.bottom, 4).background(Color(uiColor: .systemBackground))
    }
    private func interactionCard(_ card: PCInteractionCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(card.title, systemImage: "hand.tap").font(.subheadline.weight(.semibold))
            if !card.summary.isEmpty { Text(card.summary).font(.subheadline).textSelection(.enabled) }
            ForEach(card.buttons) { button in
                Button(button.label) {
                    interaction = PCInteractionSelection(card: card, button: button, document: model.snapshot?.documentId ?? "")
                }.buttonStyle(.bordered).disabled(button.disabled || !model.online || model.working || model.hasPendingInteraction)
                 .accessibilityIdentifier("pc.action.\(button.id)")
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
         .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func interactionConfirmation(_ selected: PCInteractionSelection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selected.card.title).font(.title3.weight(.semibold))
                    Text(selected.card.summary).textSelection(.enabled)
                    Text("将在当前 PC 对话中点击“\(selected.button.label)”。只执行这一次操作。").font(.footnote).foregroundStyle(.secondary)
                    Button("确认“\(selected.button.label)”") {
                        interaction = nil
                        Task { await model.performInteraction(selected) }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("pc.action.confirm")
                }.padding(24)
            }.navigationTitle("确认操作").navigationBarTitleDisplayMode(.inline)
             .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { interaction = nil } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct PCAnswerBody: View {
    let message: PCRemoteMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.blocks.isEmpty {
                Text(message.text).textSelection(.enabled).lineSpacing(5)
            } else {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { _, block in
                    switch block.kind {
                    case "code":
                        ScrollView(.horizontal) {
                            Text(block.text).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).padding(14)
                        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    case "table":
                        ScrollView(.horizontal) { Text(block.text).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled).padding(.vertical, 6) }
                    case "heading":
                        Text(block.text).font(.title3.weight(.semibold)).textSelection(.enabled).padding(.top, 4)
                    case "list":
                        HStack(alignment: .top, spacing: 10) { Text("•"); Text(block.text).textSelection(.enabled).lineSpacing(4) }
                    default:
                        Text(block.text).textSelection(.enabled).lineSpacing(5)
                    }
                }
            }
            ForEach(Array(message.links.enumerated()), id: \.offset) { _, link in
                if let url = URL(string: link.url), ["https", "http"].contains(url.scheme ?? "") {
                    Link(link.title.isEmpty ? (url.host ?? "打开链接") : link.title, destination: url).font(.footnote)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
