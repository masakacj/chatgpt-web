import Foundation

enum CMReducer {
    private static let historyLimit = 24

    static func empty(_ conversationId: String) -> CMState {
        CMState(conversationId: conversationId)
    }

    static func reduce(_ previous: CMState?, event: CMEvent) -> CMReduction {
        guard CMContract.validConversationID(event.conversationId),
              event.sequence >= 0,
              !event.eventId.isEmpty,
              event.eventId.count <= 180 else {
            return CMReduction(state: previous, decision: "invalid")
        }
        var prior = previous ?? empty(event.conversationId)
        guard prior.conversationId == event.conversationId else {
            return CMReduction(state: prior, decision: "wrong_conversation")
        }
        if let owner = prior.ownerGeneration, owner != event.ownerGeneration {
            return CMReduction(state: prior, decision: "wrong_owner_generation")
        }
        if prior.seenEvents.contains(event.eventId) {
            return CMReduction(state: prior, decision: "duplicate")
        }
        if event.at < prior.updatedAt {
            return CMReduction(state: prior, decision: "out_of_order")
        }
        if event.documentId != nil,
           event.documentId == prior.documentId,
           event.sequence > 0,
           event.sequence <= prior.lastSequence {
            return CMReduction(state: prior, decision: "stale_sequence")
        }

        var state = prior
        state.ownerGeneration = event.ownerGeneration
        state.updatedAt = event.at
        state.revision += 1
        state.seenEvents.append(event.eventId)
        if state.seenEvents.count > historyLimit {
            state.seenEvents.removeFirst(state.seenEvents.count - historyLimit)
        }
        if let document = event.documentId {
            if state.documentId != document { state.lastSequence = 0 }
            state.documentId = document
            if event.sequence > 0 { state.lastSequence = event.sequence }
        }

        let conflictingTurn = state.turnKey != nil && event.turnKey != nil && state.turnKey != event.turnKey
        if conflictingTurn {
            let pendingNative = state.pendingSubmit && event.kind == .native &&
                event.turnKey != state.previousTurnKey && event.nativeStatus != .unknown
            if event.kind == .submit || (event.kind == .native && (event.newTurn || pendingNative)) {
                state.turnKey = event.turnKey
                state.taskStatus = .unknown
                state.readState = .unknown
                state.readAt = 0
                state.terminalAt = 0
                state.pendingSubmit = false
                state.previousTurnKey = nil
            } else {
                state.conflicts += 1
                let decision = state.pendingSubmit && event.turnKey == state.previousTurnKey
                    ? "previous_turn_after_submit" : "ambiguous_turn"
                return CMReduction(state: state, decision: decision)
            }
        } else if state.turnKey == nil, let turn = event.turnKey {
            state.turnKey = turn
        }

        switch event.kind {
        case .restore:
            guard prior.revision == 0 else { return CMReduction(state: state, decision: "restore_ignored") }
            state.taskStatus = [.running, .waiting].contains(event.restoredStatus) ? .unknown : event.restoredStatus
            state.readState = event.restoredRead
            state.evidenceSource = .legacy
            state.evidenceAt = event.at
            return CMReduction(state: state, decision: "legacy_imported")

        case .submit:
            state.previousTurnKey = prior.turnKey
            state.turnKey = event.turnKey ?? "pending:\(event.eventId)"
            state.taskStatus = .running
            state.readState = .unknown
            state.readAt = 0
            state.terminalAt = 0
            state.pendingSubmit = true
            state.evidenceSource = .localSubmit
            state.evidenceAt = event.at
            return CMReduction(state: state, decision: "submission_observed")

        case .stop:
            state.taskStatus = .stopped
            state.pendingSubmit = false
            state.terminalAt = event.at
            state.evidenceSource = .localStop
            state.evidenceAt = event.at
            return CMReduction(state: state, decision: "stop_observed")

        case .read:
            guard event.turnKey != nil,
                  state.turnKey == event.turnKey,
                  state.taskStatus == .completed,
                  event.selected, event.visible, event.answerReady else {
                return CMReduction(state: state, decision: "read_unverified")
            }
            state.readState = .read
            state.readAt = event.at
            state.evidenceSource = .localView
            state.evidenceAt = event.at
            return CMReduction(state: state, decision: "read_acknowledged")

        case .sidebar:
            if event.nativeSpinner {
                if [.running, .unknown].contains(state.taskStatus) {
                    if prior.taskStatus == .running && prior.evidenceSource == .nativeSidebar {
                        return CMReduction(state: prior, decision: "same_sidebar_running")
                    }
                    state.taskStatus = .running
                    state.evidenceSource = .nativeSidebar
                    state.evidenceAt = event.at
                    return CMReduction(state: state, decision: "sidebar_running")
                }
                return CMReduction(state: state, decision: "sidebar_running_unverified")
            }
            if event.nativeUnread {
                if state.readState == .read { return CMReduction(state: state, decision: "stale_native_unread") }
                state.readState = .unread
                state.evidenceSource = .nativeSidebar
                state.evidenceAt = event.at
                if prior.taskStatus == .running && event.nativeSpinnerOff {
                    state.taskStatus = .completed
                    state.terminalAt = event.at
                    return CMReduction(state: state, decision: "sidebar_running_to_unread")
                }
                return CMReduction(state: state, decision: "sidebar_unread_unverified")
            }
            return CMReduction(state: state, decision: "sidebar_no_positive_evidence")

        case .native:
            if event.nativeStatus == .unknown { return CMReduction(state: state, decision: "no_native_evidence") }
            if event.nativeStatus == .completed && !event.answerReady {
                return CMReduction(state: state, decision: "completion_waiting_for_answer")
            }
            if [.completed, .error, .stopped].contains(prior.taskStatus),
               [.running, .waiting].contains(event.nativeStatus),
               !event.newTurn, !prior.pendingSubmit {
                return CMReduction(state: state, decision: "terminal_regression_unverified")
            }
            if [.running, .waiting].contains(event.nativeStatus),
               prior.taskStatus == event.nativeStatus,
               prior.turnKey == event.turnKey,
               !event.newTurn, !event.activeGenerationControl {
                return CMReduction(state: prior, decision: "same_native_active")
            }
            state.taskStatus = event.nativeStatus
            state.pendingSubmit = false
            state.evidenceSource = .nativeTurn
            state.evidenceAt = event.at
            if [.completed, .error, .stopped].contains(event.nativeStatus) { state.terminalAt = event.at }
            if [.running, .waiting].contains(event.nativeStatus) {
                if event.newTurn { state.readState = .unknown }
                return CMReduction(state: state, decision: "native_active")
            }
            if event.nativeStatus == .completed {
                if event.visible && event.selected {
                    state.readState = .read
                    state.readAt = event.at
                    return CMReduction(state: state, decision: "native_completed_read")
                }
                if state.readState != .read && event.nativeUnread { state.readState = .unread }
                return CMReduction(state: state, decision: "native_completed")
            }
            return CMReduction(state: state, decision: "native_terminal")
        }
    }

    static func project(_ state: CMState?, now: Int64 = CMContract.nowMilliseconds()) -> CMProjection {
        guard let state else {
            return CMProjection(task: .unknown, read: .unknown, certainty: "unverified", revision: 0)
        }
        let freshSources: Set<CMEvidenceSource> = [.nativeTurn, .nativeSidebar, .localSubmit]
        let fresh = freshSources.contains(state.evidenceSource) && state.evidenceAt > 0 && now - state.evidenceAt < 90_000
        let task: CMTaskStatus = [.running, .waiting].contains(state.taskStatus) && !fresh ? .unknown : state.taskStatus
        let certainty: String
        if fresh { certainty = "native_recent" }
        else if state.evidenceSource == .nativeTurn { certainty = "native_historical" }
        else if state.evidenceSource == .localView { certainty = "view_confirmed" }
        else { certainty = "unverified" }
        return CMProjection(task: task, read: state.readState, certainty: certainty, revision: state.revision)
    }
}
