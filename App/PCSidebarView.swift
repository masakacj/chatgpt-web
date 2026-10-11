import SwiftUI

struct PCSidebarProject: Codable, Identifiable {
    let id: String
    let title: String
    let collapsed: Bool
    let hasMore: Bool
}
struct PCSidebarChat: Codable, Identifiable {
    let id: String
    let title: String
    let projectId: String?
    let current: Bool
    let status: String
    let readState: String
    let tabId: Int?
}
struct PCSidebarLibrary: Codable {
    let ok: Bool
    let sourceTabId: Int?
    let projects: [PCSidebarProject]
    let chats: [PCSidebarChat]
    let tabs: [PCRemoteTab]
    let partial: Bool
    let sidebarAvailable: Bool
}
struct PCSidebarOpened: Decodable { let ok: Bool; let tab: PCRemoteTab }

struct PCSidebarView: View {
    @ObservedObject var model: PCCompanionModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded = Set<String>()
    private var busy: Bool { model.libraryLoading || model.working }
    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }
    var body: some View {
        NavigationStack {
            List {
                if let error = model.error {
                    Section { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }
                if let library = model.library {
                    if !query.isEmpty {
                        Section("搜索结果") {
                            ForEach(library.chats.filter { chat in
                                matches(chat.title) || library.projects.contains { $0.id == chat.projectId && matches($0.title) }
                            }) { chat in conversation(chat) }
                        }
                    } else {
                        if !library.tabs.isEmpty {
                            Section("PC 已打开") {
                                ForEach(library.tabs) { tab in
                                    Button {
                                        Task { await model.connect(tab); if model.online { dismiss() } }
                                    } label: {
                                        Label(tab.title, systemImage: model.snapshot?.conversationId == tab.conversationId ? "checkmark.circle.fill" : "desktopcomputer")
                                    }.disabled(busy || model.hasPending)
                                }
                            }
                        }
                        if !library.projects.isEmpty {
                            Section("项目") {
                                ForEach(library.projects) { project in
                                    DisclosureGroup(isExpanded: Binding(
                                        get: { expanded.contains(project.id) },
                                        set: { value in
                                            if value { expanded.insert(project.id) } else { expanded.remove(project.id) }
                                        }
                                    )) {
                                        let children = library.chats.filter { $0.projectId == project.id }
                                        ForEach(children) { chat in conversation(chat) }
                                        if project.collapsed {
                                            Button("展开并同步项目对话") {
                                                Task { await model.expandProject(project.id, more: false) }
                                            }.disabled(busy).accessibilityIdentifier("pc.sidebar.expand.\(project.id)")
                                        } else if project.hasMore {
                                            Button("加载更多对话") {
                                                Task { await model.expandProject(project.id, more: true) }
                                            }.disabled(busy)
                                        } else if children.isEmpty {
                                            Text("PC 侧栏尚未显示此项目的对话").font(.caption).foregroundStyle(.secondary)
                                        }
                                    } label: {
                                        Label(project.title, systemImage: "folder")
                                    }
                                }
                            }
                        }
                        Section("其他与最近对话") {
                            ForEach(library.chats.filter { $0.projectId == nil }) { chat in conversation(chat) }
                        }
                    }
                    if !library.sidebarAvailable {
                        Text("PC 侧栏尚未挂载，请在 PC 展开侧栏后刷新。").font(.caption).foregroundStyle(.secondary)
                    }
                    if library.partial {
                        Section { Text("同步 PC 已加载的官方列表。展开项目或加载更多会更新 PC 侧栏，不删除、归档或重命名任何对话。切换前请处理未发送草稿。").font(.caption).foregroundStyle(.secondary) }
                    }
                } else {
                    Text("读取 PC 的项目与对话列表…").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("项目与对话")
            .searchable(text: $query, prompt: "搜索项目或对话")
            .refreshable { await model.loadLibrary() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.libraryLoading { ProgressView() }
                    else { Button("刷新") { Task { await model.loadLibrary() } }.disabled(model.working) }
                }
            }
            .task { await model.loadLibrary() }
        }
    }
    private func conversation(_ chat: PCSidebarChat) -> some View {
        Button {
            Task {
                await model.openConversation(chat)
                if model.online && model.snapshot?.conversationId == chat.id { dismiss() }
            }
        } label: {
            HStack(spacing: 9) {
                if chat.status == "running" { ProgressView().controlSize(.mini) }
                else if chat.readState == "unread" { Circle().fill(.blue).frame(width: 7, height: 7) }
                else { Image(systemName: model.snapshot?.conversationId == chat.id ? "checkmark.circle" : "bubble.left").foregroundStyle(.secondary) }
                Text(chat.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if chat.status == "error" { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
            }
        }.disabled(busy || model.hasPending).accessibilityIdentifier("pc.sidebar.chat.\(chat.id)")
    }
}
