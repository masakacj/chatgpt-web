import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

private enum STQuickPickerKind { case effort, model }

private struct STTranscriptContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct STTranscriptViewportHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct STTranscriptLastMessageBottom: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct STSelectedInteraction: Identifiable {
    let card: PCInteractionCard; let button: PCInteractionButton; let document: String
    var id: String { button.id }
}

private enum STCompactEffort {
    static func code(_ effort: String) -> String {
        let text = effort.lowercased()
        if text == "pro" || text.contains("professional") { return "P" }
        if text.contains("extra") || text.contains("极高") || text == "超" { return "超" }
        if text.contains("medium") || text == "中" { return "中" }
        if text.contains("high") || text == "高" { return "高" }
        if text.contains("level 4") || text.contains("档位 4") { return "超" }
        if text.contains("level 3") || text.contains("档位 3") { return "高" }
        if text.contains("level 2") || text.contains("档位 2") { return "中" }
        if text.contains("level 1") || text.contains("档位 1") { return "低" }
        if text.contains("instant") || text.contains("low") || text == "低" { return "低" }
        return "?"
    }
}

struct SharedTabScreen: View {
    @StateObject private var model = SharedTabModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var sidebar = false
    @State private var query = ""
    @State private var expanded = Set<String>()
    @State private var followLatest = true
    @State private var latestScrollRequest = 0
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var interaction: STSelectedInteraction?
    @State private var showFilePicker = false
    @State private var showQuickPicker = false
    @State private var quickPickerKind: STQuickPickerKind = .effort
    @State private var cachedModelOptions: [STModelOption] = []
    @State private var cachedModelKind: STQuickPickerKind?
    @State private var cachedModelDocumentId: String?
    @State private var cachedModelConversationId: String?
    @State private var photo: PhotosPickerItem?
    @FocusState private var editing: Bool
    let returnToWeb: () -> Void

    private func dismissKeyboard() {
        editing = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private func rememberModelOptions(_ options: [STModelOption]) {
        guard !options.isEmpty, let snap = model.snapshot,
              model.modelOptionsDocumentId == snap.documentId,
              model.modelOptionsConversationId == snap.conversationId,
              model.modelOptionsLevel == (quickPickerKind == .effort ? "effort" : "model") else { return }
        cachedModelKind = quickPickerKind
        cachedModelOptions = options
        cachedModelDocumentId = snap.documentId
        cachedModelConversationId = snap.conversationId
    }
    private func openQuickPicker(_ kind: STQuickPickerKind) {
        guard model.canPickModel else { return }
        dismissKeyboard()
        if cachedModelKind != kind {
            cachedModelKind = nil
            cachedModelOptions = []
        }
        quickPickerKind = kind
        showQuickPicker = true
        Task {
            if model.actionPending != nil { await model.checkReceipts() }
            await model.loadModelOptions(menuLevel: kind == .effort ? "effort" : "model")
            rememberModelOptions(model.modelOptions)
        }
    }
    private var displayedModelOptions: [STModelOption] {
        let options: [STModelOption]
        if let snap = model.snapshot,
           model.modelOptionsDocumentId == snap.documentId,
           model.modelOptionsConversationId == snap.conversationId,
           model.modelOptionsLevel == (quickPickerKind == .effort ? "effort" : "model"),
           !model.modelOptions.isEmpty {
            options = model.modelOptions
        } else if let snap = model.snapshot, let pending = model.actionPending,
                  pending.documentId == snap.documentId, pending.conversation == snap.conversationId,
                  pending.optionMenuLevel == (quickPickerKind == .effort ? "effort" : "model"),
                  cachedModelKind == quickPickerKind,
                  cachedModelDocumentId == snap.documentId,
                  cachedModelConversationId == snap.conversationId, !cachedModelOptions.isEmpty {
            options = cachedModelOptions
        } else if let snap = model.snapshot, let pending = model.actionPending,
                  cachedModelKind == quickPickerKind,
                  pending.optionMenuLevel == (quickPickerKind == .effort ? "effort" : "model"),
                  pending.documentId == snap.documentId, pending.conversation == snap.conversationId,
                  let optId = pending.optionId {
            options = [STModelOption(id: optId, label: pending.targetLabel ?? "所选项目",
                                     selected: nil, submenu: nil, kind: nil, value: nil,
                                     description: nil, disabled: true, selectionEvidence: nil,
                                     min: nil, max: nil, step: nil, valueText: nil)]
        } else {
            options = []
        }
        if model.actionPending != nil {
            return options.map { opt in
                var d = opt
                d.disabled = true
                return d
            }
        }
        return options
    }
    private var quickPickerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(quickPickerKind == .effort ? "思考强度" : "选择模型")
                    .font(.headline)
                Spacer()
                Button("完成") { showQuickPicker = false }
                    .font(.subheadline)
                    .accessibilityIdentifier("shared.model.close")
            }
            HStack(spacing: 8) {
                Text(model.displayedModelName)
                    .accessibilityIdentifier("shared.picker.currentModel")
                Spacer(minLength: 2)
                Text(model.displayedEffortName)
                    .accessibilityIdentifier("shared.picker.currentEffort")
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if model.actionPending != nil {
                HStack(spacing: 8) {
                    Text("上次操作回执未确认，暂不能选择新选项")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("shared.model.pending")
                    Button("核对回执") {
                        Task {
                            await model.checkReceipts()
                            if model.actionPending == nil {
                                await model.loadModelOptions(menuLevel: quickPickerKind == .effort ? "effort" : "model")
                            }
                            rememberModelOptions(model.modelOptions)
                        }
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("shared.model.recheck")
                }
            }
            if model.modelPickerLoading {
                ProgressView("正在读取 PC 网页选项…")
                    .accessibilityIdentifier("shared.model.loading")
            } else if displayedModelOptions.isEmpty {
                Text(model.controlNotice ?? "PC 当前未提供此类选项")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(displayedModelOptions) { option in
                        Button {
                            Task {
                                await model.chooseModel(option)
                                rememberModelOptions(model.modelOptions)
                                if model.controlNotice?.hasPrefix("已在 PC 网页选择：") == true {
                                    showQuickPicker = false
                                } else if model.controlNotice == "请选择 PC 网页实际提供的细分档位" {
                                    quickPickerKind = .effort
                                    rememberModelOptions(model.modelOptions)
                                    if model.modelOptions.isEmpty {
                                        await model.loadModelOptions(menuLevel: "effort")
                                        rememberModelOptions(model.modelOptions)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).lineLimit(2)
                                    if let desc = option.description, !desc.isEmpty {
                                        Text(desc).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 6)
                                if option.selected == true { Image(systemName: "checkmark") }
                                if option.submenu == true { Image(systemName: "chevron.right") }
                            }
                            .foregroundStyle((option.disabled == true || model.actionPending != nil) ? .secondary : .primary)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(option.disabled == true || model.modelPickerLoading ||
                                  model.actionPending != nil)
                        .accessibilityIdentifier("shared.model.\(option.id)")
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 320)
            if let notice = model.controlNotice, !notice.isEmpty {
                Text(notice).font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("shared.picker.notice")
            }
        }
        .padding(14)
        .frame(width: 290)
        .presentationCompactAdaptation(.popover)
        .onAppear {
            rememberModelOptions(model.modelOptions)
        }
        .onChange(of: model.modelOptions) { _, newOptions in
            rememberModelOptions(newOptions)
        }
    }
    private func openSidebar() {
        dismissKeyboard(); query = ""
        withAnimation(.easeOut(duration: 0.16)) { sidebar = true }
        Task { await model.catalog() }
    }
    // Edge-right to open, horizontal-left to close. A simultaneous gesture
    // leaves vertical transcript/list scrolling and horizontal code scrolling intact.
    private var sidebarSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { swipe in
                let dx = swipe.translation.width, dy = swipe.translation.height
                guard abs(dx) > 85 && abs(dx) > abs(dy) * 1.6 else { return }
                if sidebar && dx < 0 {
                    dismissKeyboard()
                    withAnimation(.easeOut(duration: 0.16)) { sidebar = false }
                } else if !sidebar && dx > 0 && swipe.startLocation.x < 64 {
                    openSidebar()
                }
            }
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
            .simultaneousGesture(sidebarSwipe)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $model.needsSettings) { settings }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
                if case let .success(url) = result {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        let type = UTType(filenameExtension: url.pathExtension)
                        Task { await model.upload(data, filename: url.lastPathComponent,
                            mimeType: type?.preferredMIMEType ?? "application/octet-stream") }
                    } else {
                        model.controlNotice = "无法读取选定文件，未传给 PC"
                    }
                }
            }
            .onChange(of: photo) { _, chosen in
                guard let chosen else { return }
                Task {
                    if let data = try? await chosen.loadTransferable(type: Data.self) {
                        let type = chosen.supportedContentTypes.first
                        await model.upload(data,
                            filename: "image-" + UUID().uuidString + "." + (type?.preferredFilenameExtension ?? "jpg"),
                            mimeType: type?.preferredMIMEType ?? "image/jpeg")
                    } else {
                        model.controlNotice = "无法读取照片，未传给 PC"
                    }
                    photo = nil
                }
            }
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
    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool = false) {
        guard followLatest, !showQuickPicker, let lastId = model.displayMessages.last?.id else { return }
        DispatchQueue.main.async {
            // A queued layout correction must never override intentional
            // history browsing or scroll an already-switched conversation.
            guard followLatest, !showQuickPicker,
                  model.displayMessages.last?.id == lastId else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: openSidebar) {
                Image(systemName: "line.3.horizontal").font(.system(size: 21)).frame(width: 44, height: 44)
            }.accessibilityLabel("打开侧边栏").accessibilityIdentifier("shared.sidebar")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(model.projectTitle ?? "ChatGPT").font(.headline).lineLimit(1)
                    if model.snapshot?.status == "running" {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("PC 正在生成")
                            .accessibilityIdentifier("shared.header.running")
                        Text("生成中").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    } else if model.snapshot?.status == "completed" {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                            .symbolEffect(.bounce, value: model.snapshot?.status)
                            .accessibilityIdentifier("shared.header.completed")
                    } else if model.snapshot?.status == "error" {
                        Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red)
                            .symbolEffect(.pulse, value: model.snapshot?.status)
                            .accessibilityIdentifier("shared.header.error")
                    } else if model.snapshot?.status == "waiting" {
                        Image(systemName: "hand.raised.circle").font(.caption).foregroundStyle(.orange)
                        Text("待确认").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("shared.header.waiting")
                    }
                }
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
    private var transcript: some View {
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
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("正在同步 PC 当前对话").foregroundStyle(.secondary)
                                Spacer()
                                Button("刷新状态") { Task { await model.reconcileLoading() } }
                                    .font(.caption)
                                    .accessibilityIdentifier("shared.loading.refresh")
                            }.padding(.top, 30)
                        } else if model.displayMessages.isEmpty {
                            VStack(spacing: 14) {
                                Text("有什么可以帮你？").font(.title2.weight(.semibold))
                                if !model.online { Button("连接 PC") { model.needsSettings = true; Task { await model.loadTabs() } }.buttonStyle(.bordered) }
                                else if let title = model.projectTitle { Text("在 \(title) 中开始新聊天").foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity).padding(.top, 90)
                        }
                        ForEach(model.displayMessages) { message in
                            STMessageView(message: message, onLink: { link in Task { await model.followRemoteLink(link) } })
                                .id(message.id)
                                .background {
                                    if message.id == model.displayMessages.last?.id {
                                        // Measure the actual rendered bottom, not the
                                        // estimated LazyVStack content height.
                                        GeometryReader { last in
                                            Color.clear.preference(key: STTranscriptLastMessageBottom.self,
                                                value: last.frame(in: .named("shared.transcript.viewport")).maxY)
                                        }
                                    }
                                }
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
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background {
                        GeometryReader { size in
                            Color.clear.preference(key: STTranscriptContentHeight.self, value: size.size.height)
                        }
                    }
                    .background {
                        // A visible-color backing gives blank transcript space a hit target;
                        // it stays behind messages/links rather than intercepting controls.
                        Color(uiColor: .systemBackground).contentShape(Rectangle()).onTapGesture(perform: dismissKeyboard)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("shared.transcript")
                .coordinateSpace(name: "shared.transcript.viewport")
                .background {
                    GeometryReader { viewport in
                        Color.clear.preference(key: STTranscriptViewportHeight.self, value: viewport.size.height)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { gesture in
                            if gesture.translation.height > 10 && abs(gesture.translation.height) > abs(gesture.translation.width) {
                                followLatest = false
                            }
                        }
                )
                .onAppear { scrollToLatest(proxy: proxy) }
                // Late image decoding / history hydration changes message height
                // without changing its text or ID. Follow the actual last
                // message, not a spacer below the transcript.
                .onPreferenceChange(STTranscriptContentHeight.self) { _ in
                    if followLatest && !showQuickPicker { scrollToLatest(proxy: proxy) }
                }
                .onPreferenceChange(STTranscriptViewportHeight.self) { height in
                    guard abs(height - transcriptViewportHeight) > 1 else { return }
                    transcriptViewportHeight = height
                    // Keyboard/safe-area resizing changes the visible tail.
                    if followLatest && !showQuickPicker { scrollToLatest(proxy: proxy) }
                }
                .onPreferenceChange(STTranscriptLastMessageBottom.self) { bottom in
                    // Measure without writing state on every scroll frame: this
                    // avoids re-rendering the composer and dismissing its model menu.
                    // Correct only when actual reply content is BELOW the viewport.
                    if followLatest && !showQuickPicker && !sidebar &&
                       transcriptViewportHeight > 0 && bottom.isFinite &&
                       bottom > transcriptViewportHeight + 12 {
                        scrollToLatest(proxy: proxy)
                    }
                }
                .onChange(of: latestScrollRequest) { _, _ in
                    scrollToLatest(proxy: proxy)
                }
                .onChange(of: model.snapshot?.conversationId) { _, _ in
                    followLatest = true
                    scrollToLatest(proxy: proxy)
                }
                .onChange(of: model.snapshot?.documentId) { _, _ in
                    followLatest = true
                    scrollToLatest(proxy: proxy)
                }
                .onChange(of: model.displayMessages.last?.id) { _, _ in
                    if followLatest {
                        scrollToLatest(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: model.displayMessages.last?.text) { _, _ in
                    if followLatest {
                        scrollToLatest(proxy: proxy, animated: false)
                    }
                }
                if !followLatest {
                    Button {
                        dismissKeyboard()
                        followLatest = true
                        if let lastId = model.displayMessages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down").frame(width: 40, height: 40).background(.regularMaterial, in: Circle()).overlay(Circle().stroke(.quaternary))
                    }.accessibilityLabel("回到最新消息").padding(14)
                }
            }
        }
    }
    private var composer: some View {
        VStack(spacing: 7) {
            if model.currentPending != nil || model.hasUnresolvedActionReceipts {
                Button("核对发送／操作回执") { Task { await model.checkReceipts() } }
                    .font(.caption).accessibilityIdentifier("shared.receipt")
            }
            HStack(alignment: .bottom, spacing: 8) {
                if model.canUpload {
                    Menu {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("照片与图片", systemImage: "photo")
                        }
                        Button { showFilePicker = true } label: {
                            Label("附件与文件", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus.circle").font(.system(size: 22))
                            .frame(width: 34, height: 40)
                    }.accessibilityIdentifier("shared.attach")
                }
                TextField("发送消息", text: Binding(get: { model.text }, set: { model.edited($0) }), axis: .vertical)
                    .lineLimit(1...6).font(.body).focused($editing).padding(.vertical, 11).padding(.leading, 15)
                    .id(model.composerResetToken)
                    .accessibilityIdentifier("shared.composer")
                if model.canPickModel || showQuickPicker {
                    Text(STCompactEffort.code(model.displayedEffortName))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.primary)
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                        .contentShape(Circle())
                        // Exclusive gesture: a long press must never first open effort.
                        .gesture(LongPressGesture(minimumDuration: 0.45)
                            .exclusively(before: TapGesture())
                            .onEnded { value in
                                switch value {
                                case .first: openQuickPicker(.model)
                                case .second: openQuickPicker(.effort)
                                }
                            })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { openQuickPicker(.effort) }
                        .accessibilityAction(named: Text("选择模型")) { openQuickPicker(.model) }
                        .accessibilityLabel("轻点选择思考强度，长按选择模型。当前：\(model.displayedModelName)，\(model.displayedEffortName)")
                        .accessibilityIdentifier("shared.modelPicker")
                        .popover(isPresented: $showQuickPicker,
                                 attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            quickPickerContent
                        }
                        .padding(.bottom, 5)
                }
                if model.showsNativeStop {
                    // Positive PC-native Stop evidence owns the main button.
                    // A typed follow-up remains independently sendable while
                    // the original assistant response is still generating.
                    if !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Keep the Send control visible even when a previous
                        // receipt is unknown; explain the exact blocker below.
                        Button {
                            dismissKeyboard()
                            followLatest = true
                            Task { await model.send() }
                        } label: {
                            Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .background(Color.primary.opacity(model.canSubmit ? 1 : 0.3), in: Circle())
                        }.disabled(!model.canSubmit)
                            .accessibilityLabel("发送后续消息")
                            .accessibilityIdentifier("shared.send")
                            .padding(.bottom, 6)
                    }
                    Button {
                        dismissKeyboard()
                        Task { await model.stopGeneration() }
                    } label: {
                        Group {
                            if model.busy { ProgressView().tint(Color(uiColor: .systemBackground)) }
                            else { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)) }
                        }
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(Color.primary.opacity(model.canStopGeneration ? 1 : 0.3), in: Circle())
                    }.disabled(!model.canStopGeneration)
                        .padding(.bottom, 5).padding(.trailing, 6)
                        .accessibilityLabel("中止 PC 当前回复")
                        .accessibilityIdentifier("shared.stop")
                } else {
                    Button {
                        dismissKeyboard()
                        followLatest = true
                        Task { await model.send() }
                    } label: {
                        Group { if model.busy { ProgressView().tint(Color(uiColor: .systemBackground)) } else { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)) } }
                            .frame(width: 36, height: 36).foregroundStyle(Color(uiColor: .systemBackground))
                            .background(Color.primary.opacity(model.canSubmit ? 1 : 0.3), in: Circle())
                    }.disabled(!model.canSubmit).padding(.bottom, 5).padding(.trailing, 6)
                        .accessibilityLabel("发送").accessibilityIdentifier("shared.send")
                }
            }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 25))
            if let reason = model.sendDisabledReason {
                Text(reason).font(.caption2).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("shared.send.disabledReason")
            }
            if let notice = model.controlNotice {
                Text(notice).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityIdentifier("shared.controlNotice")
            }
            Text(model.status).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).accessibilityIdentifier("shared.status")
            #if DEBUG
            if model.fixture {
                if ProcessInfo.processInfo.arguments.contains("--shared-fixture-old-session-closed") {
                    Button("模拟旧会话关闭") {
                        SharedTabFixtureProtocol.simulateOldSessionClosed()
                        Task {
                            model.pause()
                            await model.resume()
                            if model.online { model.controlNotice = "已恢复同一 PC 标签页" }
                        }
                    }.accessibilityIdentifier("shared.fixture.oldSessionClosed")
                }
                if ProcessInfo.processInfo.arguments.contains("--shared-fixture-pc-model-switch") {
                    // DEBUG only: the simulated PC changes its own model.
                    // The phone must observe the next snapshot without issuing
                    // a model_select action or changing its local draft.
                    Button("模拟 PC 模型变化") {
                        SharedTabFixtureProtocol.simulatePCModelSwitch()
                    }.accessibilityIdentifier("shared.fixture.pcModelChange")
                }
                if ProcessInfo.processInfo.arguments.contains("--shared-fixture-late-old-send-confirm") ||
                   ProcessInfo.processInfo.arguments.contains("--shared-fixture-late-old-send-fail") {
                    Button("核对旧对话回执") { Task { await model.checkReceipts() } }
                        .accessibilityIdentifier("shared.fixture.checkOlderReceipt")
                }
                Text(SharedTabFixtureProtocol.counters).font(.system(size: 9))
                    .accessibilityIdentifier("shared.fixture.counters")
                Button("测试附件交付") {
                    Task { await model.upload(Data("synthetic attachment".utf8),
                        filename: "fixture.txt", mimeType: "text/plain") }
                }.accessibilityIdentifier("shared.fixture.upload")
            }
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
                    if !model.runningChats.isEmpty {
                        Section("进行中") {
                            ForEach(model.runningChats) { chat in chatRow(chat) }
                        }
                    }
                    if !model.unreadChats.isEmpty {
                        Section("未读") {
                            ForEach(model.unreadChats) { chat in chatRow(chat) }
                        }
                    }
                    if !model.prioritizedRecentActive.isEmpty {
                        Section("最近活跃（含项目对话）") {
                            ForEach(model.prioritizedRecentActive) { chat in chatRow(chat) }
                        }
                    }
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
                    Section("其他已显示对话") {
                        ForEach(model.chats.filter { chat in
                            let priorityIds = Set(model.runningChats.map(\.id) + model.unreadChats.map(\.id))
                            return chat.projectId == nil &&
                                !priorityIds.contains(chat.id) &&
                                !model.prioritizedRecentActive.contains(where: { $0.id == chat.id })
                        }) { chat in chatRow(chat) }
                    }
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
            // Even selecting the ALREADY active conversation is an explicit
            // request to show its latest answer; its IDs may not change.
            followLatest = true
            latestScrollRequest += 1
            Task { await model.open(chat) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title).lineLimit(2).foregroundStyle(.primary)
                    if let projectTitle = model.projectTitle(for: chat.projectId) {
                        Text(projectTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if displayedChatStatus(chat) == "running" {
                    ProgressView().controlSize(.mini).accessibilityLabel("生成中")
                } else if displayedChatStatus(chat) == "waiting" {
                    Image(systemName: "hand.raised").font(.caption2).foregroundStyle(.orange)
                } else if displayedChatStatus(chat) == "error" {
                    Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.red)
                } else if model.isChatUnread(chat) {
                    Circle().fill(displayedChatStatus(chat) == "completed" ? Color.green : Color.blue)
                        .frame(width: 7, height: 7)
                } else if model.isChatPendingRefresh(chat) {
                    Text("待刷新").font(.caption2).foregroundStyle(.secondary)
                }
                if chat.id == model.snapshot?.conversationId { Image(systemName: "checkmark").font(.caption2).foregroundStyle(.secondary) }
            }
        }.disabled(model.busy || model.libraryLoading).accessibilityIdentifier("shared.chat.\(chat.id)")
            .accessibilityValue(displayedChatStatus(chat) == "running" ? "生成中" :
                displayedChatStatus(chat) == "waiting" ? "等待确认" :
                model.isChatUnread(chat) ? "未读" :
                model.isChatPendingRefresh(chat) ? "待刷新" :
                displayedChatStatus(chat) == "error" ? "错误" : "")
    }
    private func displayedChatStatus(_ chat: STChat) -> String {
        model.effectiveChatStatus(chat)
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section("PC 连接") {
                    TextField("HTTPS 服务地址", text: $model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    if model.retiredCloudflareEndpointRouted {
                        Text("旧 Cloudflare 地址已停用：实际请求走 781751.xyz 家宽直连，原配对、草稿和待确认回执保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    SecureField("配对密钥", text: $model.pairingKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("正式线路：\(PCCompanionPolicy.defaultEndpoint)。在 PC 打开 http://127.0.0.1:13213/local/pair 获取密钥；超时的发送需先核对回执。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("读取 PC 标签页") { Task { await model.loadTabs() } }.disabled(model.busy).accessibilityIdentifier("shared.connect")
                    Text("手机与选中的 PC 标签页双向切换对话。输入草稿只在手机保存，点击发送才提交。").font(.caption)
                }
                Section("跨证书恢复") {
                    NavigationLink("备份 / 恢复 PC 配对配置") {
                        ConfigRecoveryView(
                            scope: .mirror,
                            exportConfig: { model.exportRecoveryConfig() },
                            importConfig: { model.importRecoveryConfig($0) })
                    }
                    Text("只备份 PC 服务地址及配对密钥；不迁移网页登录、草稿或正在发送的操作。")
                        .font(.caption).foregroundStyle(.secondary)
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
                    if let remote = STResourcePolicy.publicURL(link.url) {
                        STNativeWebLink(title: link.title, url: remote)
                    } else if link.interactionId != nil && link.interactionRevision != nil {
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
            if let raw = block.thumbnail, raw.count <= 48000,
               let data = Data(base64Encoded: raw), let preview = UIImage(data: data) {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("shared.generatedImagePreview")
                    .accessibilityLabel(block.text.isEmpty ? "PC 生成图片预览" : block.text)
            } else if let raw = block.url, let remote = URL(string: raw),
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
        } else if let url = STResourcePolicy.publicURL(block.url) {
            STNativeFileLink(title: block.text, url: url)
        } else {
            Label(block.text + " · 仅 PC 可获取", systemImage: "doc")
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
