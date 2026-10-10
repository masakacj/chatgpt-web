import Foundation

// Native app-owned data: independent of webpage storage/WebKit process life.
// Only local IDs, state enums and timestamps; never answer text or credentials.
final class ConversationResilienceStore {
    struct Record: Codable {
        var status: String
        var at: Double
        var verifiedAt: Double
        var turnKey: String?
        var source: String
        func display(at now: Double) -> String {
            if ["running", "waiting"].contains(status), now - max(at, verifiedAt) > 90_000 {
                return "uncertain"
            }
            return status
        }
        var json: [String: Any] {
            var result: [String: Any] = ["status": status, "at": at,
                "verifiedAt": verifiedAt, "source": source]
            if let turnKey { result["turnKey"] = turnKey }
            return result
        }
    }
    struct Budget: Codable { var windowAt: Double; var attempts: Int }
    struct Failure { let id: String; let category: String; let at: Double; let document: String }
    struct Envelope: Codable { var records: [String: Record]; var budgets: [String: Budget] }
    private let defaults: UserDefaults
    private let key = "ChatGPTWeb.nativeConversationResilience.v1"
    private(set) var records: [String: Record] = [:]
    private(set) var budgets: [String: Budget] = [:]
    var now: () -> Double

    init(defaults: UserDefaults = .standard, now: @escaping () -> Double = {Date().timeIntervalSince1970 * 1000}) {
        self.defaults = defaults; self.now = now
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Envelope.self, from: data) {
            records = saved.records.filter { Self.validID($0.key) && now() - $0.value.at < 30 * 86_400_000 }
            budgets = saved.budgets.filter { Self.validID($0.key) && now() - $0.value.windowAt < 300_000 }
        }
    }
    static func validID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{12,80}$", options: .regularExpression) != nil
    }
    static func conversationID(_ url: URL?) -> String? {
        guard let url, url.scheme == "https", url.host == "chatgpt.com" else { return nil }
        let parts = url.path.split(separator: "/")
        guard let c = parts.firstIndex(of: "c"), c + 1 < parts.count else { return nil }
        let id = String(parts[c + 1]); return validID(id) ? id : nil
    }
    func save() {
        let time = now()
        records = records.filter {time - $0.value.at < 30 * 86_400_000}
        if records.count > 300 {
            records = Dictionary(uniqueKeysWithValues: records.sorted {$0.value.at > $1.value.at}.prefix(300).map {($0.key,$0.value)})
        }
        budgets = budgets.filter {time - $0.value.windowAt < 300_000}
        if let data = try? JSONEncoder().encode(Envelope(records: records, budgets: budgets)) {
            defaults.set(data, forKey: key)
        }
    }
    func exported() -> [String: Any] { records.mapValues {$0.json} }
    @discardableResult
    func observe(_ value: [String: Any], currentID: String?) -> Record? {
        guard let id = value["id"] as? String, Self.validID(id), id == currentID else { return nil }
        let old = records[id], time = now()
        let kind = value["kind"] as? String ?? "native"
        let native = value["nativeState"] as? String ?? ""
        let turn = (value["turnKey"] as? String).map {String($0.prefix(160))}
        var status: String?
        if kind == "submit" { status = "running" }
        else if kind == "stop" { status = "stopped" }
        else if value["currentTurn"] as? Bool != false {
            if native == "waiting" { status = "waiting" }
            if native == "running" { status = "running" }
            if native == "complete", value["answerReady"] as? Bool == true,
               value["loadError"] as? Bool != true {
                if old?.source == "submit", old?.turnKey == turn, time - (old?.at ?? 0) < 120_000 { return old }
                status = "completed"
            }
        }
        guard let status else { return old } // Loading/failure never erases verified state.
        if old?.status == status, old?.turnKey == turn,
           time - (old?.at ?? 0) < (status == "running" ? 20_000 : 300_000) { return old }
        let record = Record(status: status, at: time, verifiedAt: kind == "submit" ? 0 : time,
                            turnKey: turn, source: kind == "submit" ? "submit" : "native")
        records[id] = record; save(); return record
    }
    func importLegacy(_ items: [[String: Any]]) -> Int {
        var count = 0
        for item in items.prefix(300) {
            guard let id = item["id"] as? String, Self.validID(id),
                  let rec = item["record"] as? [String: Any],
                  let status = rec["status"] as? String,
                  ["running","waiting","completed","uncertain","stopped"].contains(status),
                  let at = rec["at"] as? Double,
                  at > 0, at <= now() + 60_000, now() - at < 30 * 86_400_000,
                  (records[id]?.at ?? 0) < at else { continue }
            records[id] = Record(status: status, at: at, verifiedAt: 0, turnKey: nil, source: "imported")
            count += 1
        }
        if count > 0 { save() }; return count
    }
    static func failureCategory(code: Int, networkError: Bool = false) -> String? {
        if [401,403].contains(code) { return "auth" }
        if code == 429 { return "rate_limit" }
        if [404,410].contains(code) { return "not_found" }
        if [408,425,500,502,503,504].contains(code) { return "transient_http" }
        // fetch TypeError doesn't reliably distinguish offline/TLS/adblock.
        if networkError { return "unclassified_network" }
        return code >= 400 ? "other" : nil
    }
    func reserveRetry(_ value: [String: Any], failure: Failure?, currentID: String?, document: String,
                      appActive: Bool) -> Double? {
        guard appActive, let failure, failure.document == document,
              failure.category == "transient_http", now() - failure.at <= 45_000, now() >= failure.at,
              let id = value["id"] as? String, id == currentID, id == failure.id,
              value["visible"] as? Bool == true, value["loadError"] as? Bool == true,
              value["canRetry"] as? Bool == true else { return nil }
        for key in ["hasDraft","running","waiting","hasAnswer","recoveryCanceled"] {
            guard value[key] as? Bool == false else { return nil }
        }
        let old = budgets[id]
        let attempts = old != nil && now() - old!.windowAt < 300_000 ? old!.attempts : 0
        guard attempts < 2 else { return nil }
        budgets[id] = Budget(windowAt: attempts == 0 ? now() : old!.windowAt, attempts: attempts + 1)
        save() // Durable before dispatch: refresh/restart must not reset budget.
        return attempts == 0 ? 1.6 : 4.2
    }
}
