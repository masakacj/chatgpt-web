import Foundation

struct CMRecoveryBudget: Codable, Equatable {
    var windowAt: Int64
    var attempts: Int
}

struct CMRecoveryCandidate: Codable, Equatable, Identifiable {
    var id: String { "\(conversationId):\(documentId):\(sequence)" }
    let conversationId: String
    let documentId: String
    let sequence: Int
    let observedAt: Int64
    let visible: Bool
    let loadError: Bool
    let canRetry: Bool
    let hasDraft: Bool
    let running: Bool
    let waiting: Bool
    let hasAnswer: Bool
    let recoveryCanceled: Bool
}

enum ManualRecoveryDecision: Equatable {
    case allow(next: CMRecoveryBudget)
    case deny(String)
}

enum ManualRecoveryPolicy {
    static let window: Int64 = 5 * 60 * 1_000
    static let maximumAttempts = 2

    static func decide(candidate: CMRecoveryCandidate,
                       currentConversation: String?,
                       currentDocument: String?,
                       currentSequence: Int,
                       budget: CMRecoveryBudget?,
                       appActive: Bool,
                       now: Int64 = CMContract.nowMilliseconds()) -> ManualRecoveryDecision {
        guard appActive else { return .deny("app_inactive") }
        guard candidate.conversationId == currentConversation,
              candidate.documentId == currentDocument,
              candidate.sequence == currentSequence else { return .deny("stale_page") }
        guard now >= candidate.observedAt, now - candidate.observedAt <= 45_000 else { return .deny("stale_candidate") }
        guard candidate.visible, candidate.loadError else { return .deny("not_visible_load_error") }
        guard candidate.canRetry else { return .deny("native_retry_unavailable") }
        guard !candidate.hasDraft, !candidate.running, !candidate.waiting,
              !candidate.hasAnswer, !candidate.recoveryCanceled else { return .deny("interactive_or_answer_present") }
        let attempts = budget != nil && now - budget!.windowAt < window ? budget!.attempts : 0
        guard attempts < maximumAttempts else { return .deny("retry_budget_exhausted") }
        return .allow(next: CMRecoveryBudget(windowAt: attempts == 0 ? now : budget!.windowAt,
                                             attempts: attempts + 1))
    }
}
