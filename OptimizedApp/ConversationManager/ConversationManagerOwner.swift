import Foundation
import SwiftUI

@MainActor
final class ConversationManagerOwner: ObservableObject {
    @Published private(set) var projection = CMProjection(task: .unknown, read: .unknown, certainty: "unverified", revision: 0)
    @Published private(set) var recoveryCandidate: CMRecoveryCandidate?
    @Published private(set) var audit = Audit()

    struct Audit: Codable {
        var acceptedEvents = 0
        var rejectedEvents = 0
        var conflicts = 0
        var manualRetryAuthorizations = 0
        var processTerminations = 0
        var currentDocumentSequence = 0
        var lastDecision = "none"
    }

    private let store = CMStore()
    private var ownerGeneration = ""
    private var currentConversation: String?
    private var currentDocument: String?
    private var currentSequence = 0
    private var appActive = true

    init() {
        Task { ownerGeneration = await store.ownerGeneration() }
    }

    func setAppActive(_ active: Bool) {
        appActive = active
        if !active { recoveryCandidate = nil }
    }

    func invalidateDocument(processTerminated: Bool = false) {
        currentDocument = nil
        currentSequence = 0
        recoveryCandidate = nil
        if processTerminated { audit.processTerminations += 1 }
    }

    func handle(_ payload: [String: Any]) async -> [String: Any] {
        guard ownerGeneration.isEmpty == false,
              let type = payload["type"] as? String else {
            audit.rejectedEvents += 1
            return ["ok": false, "error": "owner_not_ready"]
        }
        if type == "boot" {
            guard let document = bounded(payload["document"], 128) else { return reject("invalid_document") }
            currentDocument = document
            currentSequence = 0
            recoveryCandidate = nil
            return ["ok": true, "cmProtocol": CMContract.protocolVersion, "cmVersion": CMContract.version,
                    "ownerGeneration": ownerGeneration]
        }
        guard let document = bounded(payload["document"], 128), document == currentDocument else {
            return reject("stale_document")
        }
        if type == "observe", let observation = payload["observation"] as? [String: Any] {
            return await observe(observation, document: document)
        }
        if type == "audit" {
            return ["ok": true, "accepted": audit.acceptedEvents, "rejected": audit.rejectedEvents,
                    "conflicts": audit.conflicts, "sequence": audit.currentDocumentSequence,
                    "decision": audit.lastDecision]
        }
        return reject("unknown_operation")
    }

    func dismissRecoveryCandidate() {
        recoveryCandidate = nil
    }

    func authorizeManualRetry() async -> Bool {
        guard let candidate = recoveryCandidate else { return false }
        let budget = await store.budget(for: candidate.conversationId)
        switch ManualRecoveryPolicy.decide(candidate: candidate,
                                           currentConversation: currentConversation,
                                           currentDocument: currentDocument,
                                           currentSequence: currentSequence,
                                           budget: budget,
                                           appActive: appActive) {
        case .deny:
            recoveryCandidate = nil
            return false
        case .allow(let next):
            do {
                try await store.writeBudget(next, for: candidate.conversationId)
                audit.manualRetryAuthorizations += 1
                recoveryCandidate = nil
                return true
            } catch {
                recoveryCandidate = nil
                return false
            }
        }
    }

    private func observe(_ value: [String: Any], document: String) async -> [String: Any] {
        guard let id = bounded(value["conversationId"], 80), CMContract.validConversationID(id),
              let eventId = bounded(value["eventId"], 180),
              let kindRaw = value["kind"] as? String, let kind = CMEventKind(rawValue: kindRaw),
              let sequence = value["sequence"] as? Int, sequence >= 0 else {
            return reject("invalid_observation")
        }
        let now = CMContract.nowMilliseconds()
        guard sequence > currentSequence else { return reject("stale_sequence") }
        currentConversation = id
        currentSequence = sequence
        audit.currentDocumentSequence = sequence

        var event = CMEvent(kind: kind, conversationId: id, turnKey: bounded(value["turnKey"], 160),
                            documentId: document, ownerGeneration: ownerGeneration, eventId: eventId,
                            at: (value["at"] as? NSNumber)?.int64Value ?? now, sequence: sequence)
        event.nativeStatus = CMTaskStatus(rawValue: value["nativeStatus"] as? String ?? "unknown") ?? .unknown
        event.nativeSpinner = value["nativeSpinner"] as? Bool ?? false
        event.nativeSpinnerOff = value["nativeSpinnerOff"] as? Bool ?? false
        event.nativeUnread = value["nativeUnread"] as? Bool ?? false
        event.answerReady = value["answerReady"] as? Bool ?? false
        event.visible = value["visible"] as? Bool ?? false
        event.selected = value["selected"] as? Bool ?? false
        event.newTurn = value["newTurn"] as? Bool ?? false
        event.activeGenerationControl = value["activeGenerationControl"] as? Bool ?? false

        let previous = await store.state(for: id)
        let result = CMReducer.reduce(previous, event: event)
        audit.lastDecision = result.decision
        if result.decision.contains("conflict") || result.decision == "ambiguous_turn" { audit.conflicts += 1 }
        guard let state = result.state else { return reject(result.decision) }
        if state != previous {
            do { try await store.write(state) }
            catch { return reject("storage_write_failed") }
        }
        audit.acceptedEvents += 1
        projection = CMReducer.project(state)

        let candidate = CMRecoveryCandidate(
            conversationId: id, documentId: document, sequence: sequence, observedAt: now,
            visible: event.visible, loadError: value["loadError"] as? Bool ?? false,
            canRetry: value["canRetry"] as? Bool ?? false,
            hasDraft: value["hasDraft"] as? Bool ?? false,
            running: value["running"] as? Bool ?? false,
            waiting: value["waiting"] as? Bool ?? false,
            hasAnswer: value["hasAnswer"] as? Bool ?? false,
            recoveryCanceled: value["recoveryCanceled"] as? Bool ?? false)
        if candidate.visible && candidate.loadError && candidate.canRetry &&
            !candidate.hasDraft && !candidate.running && !candidate.waiting &&
            !candidate.hasAnswer && !candidate.recoveryCanceled {
            recoveryCandidate = candidate
        } else if recoveryCandidate?.documentId == document {
            recoveryCandidate = nil
        }
        return ["ok": true, "decision": result.decision, "revision": state.revision]
    }

    private func reject(_ reason: String) -> [String: Any] {
        audit.rejectedEvents += 1
        audit.lastDecision = reason
        return ["ok": false, "error": reason]
    }

    private func bounded(_ value: Any?, _ max: Int) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= max,
              text.range(of: "^[A-Za-z0-9_:.-]+$", options: .regularExpression) != nil else { return nil }
        return text
    }
}
