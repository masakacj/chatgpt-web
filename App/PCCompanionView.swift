import SwiftUI
import Security
import CryptoKit

struct PCRemoteBlock: Codable, Identifiable {
    let kind: String
    let text: String
    var id: String { kind + ":" + String(SHA256.hash(data: Data(text.utf8)).description.prefix(24)) }
}
struct PCRemoteLink: Codable { let title: String; let url: String }
struct PCRemoteMessage: Codable, Identifiable {
    let id: String
    let role: String
    let text: String
    let blocks: [PCRemoteBlock]
    let links: [PCRemoteLink]
    let truncated: Bool
}
struct PCRemoteSnapshot: Codable {
    let schema: Int
    let documentId: String
    let conversationId: String
    let title: String
    let messages: [PCRemoteMessage]
    let status: String
    let draft: String
    let draftHash: String
    let canSend: Bool
    let composing: Bool
    let unsupportedTools: Bool
    let historyPartial: Bool
}
struct PCRemoteTab: Codable, Identifiable {
    let tabId: Int
    let title: String
    let conversationId: String
    let active: Bool
    var id: Int { tabId }
}
struct PCRemoteEnvelope: Codable {
    let ok: Bool
    let sessionId: String
    let revision: Int
    let capturedAt: Double
    let routeChanged: Bool
    let snapshot: PCRemoteSnapshot?
}
private struct PCRemoteTabs: Decodable { let tabs: [PCRemoteTab] }
private struct PCCommandResult: Codable {
    let status: String?
    let draftHash: String?
    let documentId: String?
    let error: String?
}
private struct PCCommandReceipt: Decodable {
    let ok: Bool
    let commandId: String
    let state: String
    let result: PCCommandResult?
}
private struct PCRemoteFailure: Decodable { let error: String }
private struct PCSavedView: Codable { let snapshot: PCRemoteSnapshot; let capturedAt: Double }

// Pairing credentials are not website cookies and never go into source or logs.
private enum PCPairingKeychain {
    static let service = "ChatGPTWeb.PCCompanion.v1"
    static func load() -> String {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,kSecAttrAccount as String:"pairing",
            kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess,
              let data=result as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
    static func save(_ text: String) throws {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,kSecAttrAccount as String:"pairing"]
        SecItemDelete(q as CFDictionary)
        var insert=q
        insert[kSecValueData as String]=Data(text.utf8)
        insert[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary,nil) == errSecSuccess else {
            throw NSError(domain:"PCCompanion",code:1,userInfo:[NSLocalizedDescriptionKey:"无法安全保存配对密钥"])
        }
    }
}
// A redirect must never forward a pairing bearer token to another endpoint.
private final class PCNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class PCCompanionModel: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey:"PCCompanion.endpoint") ?? ""
    @Published var pairingKey = PCPairingKeychain.load()
    @Published var tabs: [PCRemoteTab] = []
    @Published var snapshot: PCRemoteSnapshot?
    @Published var text = ""
    @Published var status = "未连接 PC"
    @Published var online = false
    @Published var working = false
    @Published var error: String?
    @Published var localDirty = false
    @Published var pendingSend = UserDefaults.standard.string(forKey:"PCCompanion.pendingSend")
    @Published var capturedAt: Double = 0
    private var sessionId: String?
    private var revision = -1
    private var baseDraftHash: String? = UserDefaults.standard.string(forKey:"PCCompanion.draftBase")
    private var draftOwner: String? = UserDefaults.standard.string(forKey:"PCCompanion.draftOwner")
    private var pollTask: Task<Void,Never>?
    private let redirect = PCNoRedirect()
    private lazy var transport: URLSession = {
        let c=URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest=35
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpShouldSetCookies=false
        c.httpCookieStorage=nil
        return URLSession(configuration:c,delegate:redirect,delegateQueue:nil)
    }()
    private var cacheURL: URL? {
        guard let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first else {return nil}
        return root.appendingPathComponent("PCCompanion/latest.json")
    }
    init() {
        let fixtureEnabled=ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")
        if fixtureEnabled {
            snapshot=PCRemoteSnapshot(schema:1,documentId:"fixture",conversationId:"11111111-1111-4111-8111-111111111111",title:"PC 原生同步验收",messages:[PCRemoteMessage(id:"m1",role:"assistant",text:"已从 PC 同步的最新答案。手机原生界面无需加载完整网页。",blocks:[PCRemoteBlock(kind:"text",text:"已从 PC 同步的最新答案。")],links:[],truncated:false)],status:"completed",draft:"",draftHash:"fixture",canSend:false,composing:false,unsupportedTools:true,historyPartial:true)
            status="本地快照 · 尚未连接 PC";return
        }
        if let u=cacheURL,let data=try? Data(contentsOf:u),let cache=try? JSONDecoder().decode(PCSavedView.self,from:data) {
            snapshot=cache.snapshot;capturedAt=cache.capturedAt
            status="本地快照 · 尚未连接 PC"
        }
        text=UserDefaults.standard.string(forKey:"PCCompanion.localDraft") ?? ""
        localDirty = !text.isEmpty
    }
    private func url(_ path: String) throws -> URL {
        guard let base=URL(string:endpoint.trimmingCharacters(in:.whitespacesAndNewlines)),
              base.scheme=="https",let host=base.host,!host.isEmpty,
              base.user==nil,base.password==nil,base.query==nil,base.fragment==nil,
              base.path.isEmpty || base.path=="/" else {
            throw NSError(domain:"PCCompanion",code:2,userInfo:[NSLocalizedDescriptionKey:"请输入 HTTPS 服务地址，不包含路径、账号或密钥"])
        }
        return URL(string:path,relativeTo:base)!.absoluteURL
    }
    private func request<T:Decodable>(_ path:String,method:String="GET",body:[String:Any]?=nil) async throws -> T {
        guard pairingKey.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil else {
            throw NSError(domain:"PCCompanion",code:3,userInfo:[NSLocalizedDescriptionKey:"配对密钥格式不正确"])
        }
        var req=URLRequest(url:try url(path));req.httpMethod=method
        req.setValue("Bearer "+pairingKey,forHTTPHeaderField:"Authorization")
        if let body {req.httpBody=try JSONSerialization.data(withJSONObject:body);req.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await transport.data(for:req)
        guard data.count<=800000,let response=response as? HTTPURLResponse else {throw URLError(.badServerResponse)}
        guard (200...299).contains(response.statusCode) else {
            let reason=(try? JSONDecoder().decode(PCRemoteFailure.self,from:data).error) ?? "HTTP \(response.statusCode)"
            throw NSError(domain:"PCCompanion",code:response.statusCode,userInfo:[NSLocalizedDescriptionKey:reason])
        }
        return try JSONDecoder().decode(T.self,from:data)
    }
    func loadTabs() async {
        guard !working else{return};working=true;defer{working=false};error=nil
        do {
            let result:PCRemoteTabs=try await request("/v1/tabs")
            tabs=result.tabs;try PCPairingKeychain.save(pairingKey)
            UserDefaults.standard.set(endpoint,forKey:"PCCompanion.endpoint")
            status=tabs.isEmpty ? "PC 没有已打开的 ChatGPT 对话" : "选择 PC 上的会话"
        }catch{self.error=error.localizedDescription;online=false}
    }
    func connect(_ tab:PCRemoteTab) async {
        guard !working else{return}
        if localDirty, !text.isEmpty, let draftOwner, draftOwner != tab.conversationId {
            error="另一会话还有本地草稿，请先保存或清空；不会将它写入当前会话";return
        }
        await disconnect();working=true;defer{working=false};error=nil
        do {
            let result:PCRemoteEnvelope=try await request("/v1/sessions",method:"POST",body:["tabId":tab.tabId])
            sessionId=result.sessionId;online=true;apply(result)
            pollTask=Task { [weak self] in await self?.poll() }
        }catch{self.error=error.localizedDescription;online=false}
    }
    private func apply(_ value:PCRemoteEnvelope) {
        revision=value.revision
        if value.routeChanged {online=false;status="PC 已切换会话，请重新连接";return}
        if let fresh=value.snapshot {
            snapshot=fresh;capturedAt=value.capturedAt
            if !localDirty {text=fresh.draft;baseDraftHash=fresh.draftHash}
            status=fresh.status=="running" ? "PC 生成中" : fresh.status=="waiting" ? "需要在 PC 处理工具授权" : "已同步 PC"
            if let target=cacheURL,
               let data=try? JSONEncoder().encode(PCSavedView(snapshot:fresh,capturedAt:capturedAt)) {
                try? FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? data.write(to:target,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
                var dir=target.deletingLastPathComponent();var values=URLResourceValues();values.isExcludedFromBackup=true
                try? dir.setResourceValues(values)
            }
        }
    }
    private func poll() async {
        while !Task.isCancelled,let id=sessionId,online {
            do {
                let value:PCRemoteEnvelope=try await request("/v1/sessions/\(id)?after=\(revision)")
                guard !Task.isCancelled,sessionId==id else{return};apply(value)
            }catch{
                if Task.isCancelled{return}
                online=false;status="连接已断开 · 显示最近快照";self.error=error.localizedDescription;return
            }
        }
    }
    func edited(_ value:String) {
        if !localDirty {baseDraftHash=snapshot?.draftHash}
        text=value;localDirty=true
        if let id=snapshot?.conversationId {draftOwner=id}
        UserDefaults.standard.set(draftOwner,forKey:"PCCompanion.draftOwner")
        UserDefaults.standard.set(baseDraftHash,forKey:"PCCompanion.draftBase")
        UserDefaults.standard.set(value,forKey:"PCCompanion.localDraft")
    }
    @discardableResult
    private func syncDraftInternal() async throws -> String {
        guard let id=sessionId,online,let snap=snapshot,let base=baseDraftHash ?? snapshot?.draftHash else {throw URLError(.notConnectedToInternet)}
        let value=text
        let receipt:PCCommandReceipt=try await request("/v1/sessions/\(id)/commands",method:"POST",body:[
            "commandId":UUID().uuidString,"action":"draft","documentId":snap.documentId,"baseDraftHash":base,"text":value])
        guard receipt.ok,receipt.result?.status=="draft_synced",let hash=receipt.result?.draftHash else {throw URLError(.cannotParseResponse)}
        baseDraftHash=hash
        UserDefaults.standard.set(hash,forKey:"PCCompanion.draftBase")
        if text==value {localDirty=false}
        status="草稿已同步到 PC，尚未发送"
        return hash
    }
    func syncDraft() async {
        guard !working,online,pendingSend==nil else{return};working=true;defer{working=false};error=nil
        do{_ = try await syncDraftInternal()}catch{self.error=error.localizedDescription}
    }
    func send() async {
        guard !working,online,pendingSend==nil,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        working=true;defer{working=false};error=nil
        do{
            let intended=text
            let hash=try await syncDraftInternal()
            guard text==intended,let id=sessionId,let snap=snapshot else {throw URLError(.cancelled)}
            let key=UUID().uuidString
            // Persist BEFORE making the request. Reconnect queries this receipt;
            // it never automatically repeats a Send that might have succeeded.
            pendingSend=key;UserDefaults.standard.set(key,forKey:"PCCompanion.pendingSend")
            let receipt:PCCommandReceipt=try await request("/v1/sessions/\(id)/commands",method:"POST",body:[
                "commandId":key,"action":"send","documentId":snap.documentId,"baseDraftHash":hash,"text":intended])
            resolve(receipt)
        }catch{self.error=error.localizedDescription;if pendingSend != nil{status="发送结果未确认，请核对回执；不会自动重发"}}
    }
    private func resolve(_ receipt:PCCommandReceipt) {
        if receipt.state=="done",receipt.result?.status=="sent_confirmed" {
            pendingSend=nil;UserDefaults.standard.removeObject(forKey:"PCCompanion.pendingSend")
            text="";localDirty=false;baseDraftHash=nil;draftOwner=nil
            UserDefaults.standard.removeObject(forKey:"PCCompanion.draftBase")
            UserDefaults.standard.removeObject(forKey:"PCCompanion.draftOwner")
            UserDefaults.standard.removeObject(forKey:"PCCompanion.localDraft")
            status="PC 网页已确认收到消息"
        }else if receipt.state=="failed" {
            pendingSend=nil;UserDefaults.standard.removeObject(forKey:"PCCompanion.pendingSend")
            error=receipt.result?.error ?? "发送未执行";status="请检查 PC 状态"
        }else {status="发送结果待确认，请在 PC 核对；不会再次发送"}
    }
    func checkReceipt() async {
        guard let key=pendingSend,!working else{return};working=true;defer{working=false}
        do {let value:PCCommandReceipt=try await request("/v1/commands/\(key)");resolve(value)}catch{self.error=error.localizedDescription}
    }
    func disconnect() async {
        pollTask?.cancel();pollTask=nil;online=false
        let old=sessionId;sessionId=nil
        if let old {let _:PCDisconnect?=try? await request("/v1/sessions/\(old)",method:"DELETE")}
        status=snapshot==nil ? "未连接 PC" : "本地快照 · PC 未连接"
    }
    private struct PCDisconnect:Decodable {let ok:Bool}
    func pause(){pollTask?.cancel();pollTask=nil;online=false;status="已暂停连接 · 保留本地快照"}
    func resume() async {
        guard let id=sessionId else{return}
        do{let value:PCRemoteEnvelope=try await request("/v1/sessions/\(id)");online=true;apply(value);pollTask=Task{[weak self] in await self?.poll()}}
        catch{sessionId=nil;online=false;status="请重新选择 PC 会话"}
    }
}

struct PCCompanionView: View {
    @StateObject private var model=PCCompanionModel()
    @State private var settings = !ProcessInfo.processInfo.arguments.contains("--pc-companion-fixture")
    @Environment(\.scenePhase) private var scenePhase
    let returnToWeb: () -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                HStack {
                    Circle().fill(model.online ? Color.green : Color.gray).frame(width:7,height:7)
                    Text(model.status).font(.caption)
                    Spacer()
                    if model.working {ProgressView().controlSize(.small)}
                }.padding(.horizontal).padding(.vertical,8)
                if let error=model.error {Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal)}
                if let snapshot=model.snapshot {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment:.leading,spacing:18) {
                                if snapshot.historyPartial {Text("当前同步最近消息；完整历史和工具操作保留在 PC。").font(.caption).foregroundStyle(.secondary)}
                                ForEach(snapshot.messages) { message in
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(message.role=="user" ? "你" : "ChatGPT").font(.caption.bold()).foregroundStyle(.secondary)
                                        // Render text, not arbitrary remote HTML/JavaScript.
                                        Text(message.text).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                                        if message.truncated {Text("内容较长，完整内容请查看 PC").font(.caption).foregroundStyle(.secondary)}
                                    }.padding(12).background(.quaternary.opacity(message.role=="user" ? 0.8 : 0.25)).clipShape(RoundedRectangle(cornerRadius:12)).id(message.id)
                                }
                                if snapshot.unsupportedTools {Label("复杂工具及附件操作请在 PC 原网页完成",systemImage:"desktopcomputer").font(.caption).foregroundStyle(.secondary)}
                                Color.clear.frame(height:1).id("end")
                            }.padding()
                        }.onAppear {proxy.scrollTo("end",anchor:.bottom)}
                    }
                }else{ContentUnavailableView("连接你的 PC Chrome",systemImage:"desktopcomputer",description:Text("PC 保留官方网页和扩展，手机仅显示同步内容。"))}
                VStack(spacing:8) {
                    TextEditor(text:Binding(get:{model.text},set:{model.edited($0)})).frame(minHeight:55,maxHeight:110).padding(6).background(.quaternary).clipShape(RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("pc.remote.composer")
                    HStack {
                        if model.pendingSend != nil {Button("核对发送回执"){Task{await model.checkReceipt()}}}
                        else {Button("同步草稿"){Task{await model.syncDraft()}}.disabled(!model.online||model.working)}
                        Spacer()
                        Button("发送"){Task{await model.send()}}.buttonStyle(.borderedProminent)
                            .disabled(!model.online||model.working||model.pendingSend != nil||model.text.isEmpty||model.snapshot==nil||model.snapshot?.status=="running"||model.snapshot?.status=="waiting")
                    }
                }.padding().background(.regularMaterial)
            }.navigationTitle(model.snapshot?.title ?? "PC 同步").navigationBarTitleDisplayMode(.inline)
             .toolbar {
                 ToolbarItem(placement:.topBarLeading){Button("原网页"){Task{await model.disconnect();returnToWeb()}}}
                 ToolbarItem(placement:.topBarTrailing){Button("连接"){settings=true}}
             }
             .sheet(isPresented:$settings){configuration}
             .onChange(of:scenePhase){_,phase in if phase == .active {Task{await model.resume()}}else if phase == .background{model.pause()}}
        }
    }
    private var configuration: some View {
        NavigationStack {
            Form {
                Section("PC 配对") {
                    TextField("HTTPS 服务地址",text:$model.endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("配对密钥",text:$model.pairingKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("读取 PC 会话"){Task{await model.loadTabs()}}.disabled(model.working)
                    Text("配对密钥保存在本机钥匙串。登录 Cookie 留在 PC，不会同步至手机。").font(.caption)
                }
                if let error=model.error {Section{Text(error).foregroundStyle(.red)}}
                Section("PC 已打开的对话") {
                    ForEach(model.tabs){tab in Button(tab.title){Task{await model.connect(tab);if model.online{settings=false}}}.disabled(model.working)}
                }
                Section {Text("首版支持文字阅读、草稿同步和发送。PC 草稿已变化时会拒绝覆盖；不自动重发未确认的消息。复杂 MCP、图片上传保留原网页处理。").font(.caption)}
            }.navigationTitle("连接 PC").toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){settings=false}}}
        }
    }
}
