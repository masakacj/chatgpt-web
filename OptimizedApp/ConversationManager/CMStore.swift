import Foundation

actor CMStore {
    struct Envelope: Codable {
        var schema = 1
        var cmProtocol = CMContract.protocolVersion
        var cmVersion = CMContract.version
        var ownerGeneration: String
        var records: [String: CMState]
        var budgets: [String: CMRecoveryBudget]
    }

    private let fileURL: URL
    private var envelope: Envelope

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ChatGPTWebOptimized", isDirectory: true)
        fileURL = root.appendingPathComponent("conversation-manager-v1.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
           decoded.schema == 1,
           decoded.cmProtocol == CMContract.protocolVersion {
            envelope = decoded
        } else {
            envelope = Envelope(ownerGeneration: "ios-owner-\(UUID().uuidString)", records: [:], budgets: [:])
        }
        let now = CMContract.nowMilliseconds()
        envelope.records = envelope.records.filter { key, value in
            CMContract.validConversationID(key) && now >= value.updatedAt && now - value.updatedAt < 30 * 86_400_000
        }
        envelope.budgets = envelope.budgets.filter { key, value in
            CMContract.validConversationID(key) && value.attempts >= 0 && value.attempts <= 2 && now >= value.windowAt && now - value.windowAt < 300_000
        }
    }

    func ownerGeneration() -> String { envelope.ownerGeneration }
    func state(for id: String) -> CMState? { envelope.records[id] }
    func budget(for id: String) -> CMRecoveryBudget? { envelope.budgets[id] }
    func allStates() -> [String: CMState] { envelope.records }

    func write(_ state: CMState) throws {
        guard CMContract.validConversationID(state.conversationId),
              state.ownerGeneration == envelope.ownerGeneration else { throw StoreError.ownerMismatch }
        if let old = envelope.records[state.conversationId] {
            guard old.revision <= state.revision else { throw StoreError.staleRevision }
            if old.revision == state.revision, old.updatedAt > state.updatedAt { throw StoreError.staleObservation }
        }
        envelope.records[state.conversationId] = state
        try persist()
    }

    func writeBudget(_ budget: CMRecoveryBudget, for id: String) throws {
        guard CMContract.validConversationID(id), budget.attempts >= 0, budget.attempts <= 2 else {
            throw StoreError.invalidBudget
        }
        envelope.budgets[id] = budget
        try persist()
    }

    func rotateOwner() throws -> String {
        envelope.ownerGeneration = "ios-owner-\(UUID().uuidString)"
        try persist()
        return envelope.ownerGeneration
    }

    private func persist() throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var directory = parent
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(envelope).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    enum StoreError: Error {
        case ownerMismatch, staleRevision, staleObservation, invalidBudget
    }
}
