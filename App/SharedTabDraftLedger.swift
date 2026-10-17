import Foundation

struct STLocalDraft: Codable, Equatable {
    var text = ""
    var revision = 0
}
struct STPendingSend: Codable, Identifiable, Equatable {
    let id: String
    let owner: String
    let text: String
    let revision: Int
    let server: String
    let temporary: Bool
}
enum STLedgerError: Error { case pendingSend, emptyDraft }

/// Phone drafts never consume PC editor text. This value type is tested without UIKit.
struct STDraftLedger: Codable {
    var drafts: [String: STLocalDraft] = [:]
    var pending: [String: STPendingSend] = [:]

    func draft(_ owner: String) -> STLocalDraft { drafts[owner] ?? STLocalDraft() }
    func pendingFor(_ owner: String) -> STPendingSend? { pending.values.first { $0.owner == owner } }
    func pendingCount(_ owner: String) -> Int { pending.values.filter { $0.owner == owner }.count }

    // A reservation with an UNKNOWN result must remain queryable, but it
    // must not indefinitely lock an explicitly different phone draft.
    // Identical text (even retyped) is never treated as a new send.
    func canReserve(_ owner: String) -> Bool {
        let value = draft(owner)
        guard !owner.isEmpty, !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return pending.values.filter { $0.owner == owner }.allSatisfy {
            value.revision > $0.revision && value.text != $0.text
        }
    }

    mutating func edit(_ owner: String, text: String) {
        guard !owner.isEmpty else { return }
        let old = draft(owner)
        guard old.text != text else { return }
        drafts[owner] = STLocalDraft(text: text, revision: old.revision + 1)
    }
    mutating func reserve(_ owner: String, server: String, temporary: Bool, id: String = UUID().uuidString) throws -> STPendingSend {
        let value = draft(owner)
        guard !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw STLedgerError.emptyDraft }
        guard canReserve(owner) else { throw STLedgerError.pendingSend }
        let command = STPendingSend(id: id, owner: owner, text: value.text, revision: value.revision, server: server, temporary: temporary)
        pending[id] = command
        return command
    }
    mutating func definitelyNotSent(_ id: String) { pending.removeValue(forKey: id) }

    /// Clears only the submitted revision; a reply never erases the next draft.
    mutating func confirmed(_ id: String, actualOwner: String? = nil) {
        guard let command = pending.removeValue(forKey: id) else { return }
        let current = draft(command.owner)
        if current.text == command.text && current.revision == command.revision {
            drafts[command.owner] = STLocalDraft(text: "", revision: current.revision + 1)
        } else if let actualOwner, actualOwner != command.owner, draft(actualOwner).text.isEmpty {
            // A new chat acquired its real ID while the next local message was typed.
            drafts[actualOwner] = current
            drafts[command.owner] = STLocalDraft(text: "", revision: current.revision + 1)
        }
    }
    // Unknown or timed-out sends deliberately have no replay/clear operation.
}
