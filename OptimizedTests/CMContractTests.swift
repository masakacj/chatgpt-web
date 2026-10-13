import XCTest
@testable import ChatGPTWebOptimized

final class CMContractTests: XCTestCase {
    struct Corpus: Decodable {
        struct Case: Decodable {
            let name: String
            let events: [CMEvent]
            let decisions: [String]
            let task: CMTaskStatus
            let read: CMReadState
        }
        let cmProtocol: Int
        let cmVersion: String
        let cases: [Case]
    }

    func testReducerCorpus() throws {
        let url = sourceRoot().appendingPathComponent("Contracts/ConversationManager/v2/reducer-cases.json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.cmProtocol, CMContract.protocolVersion)
        XCTAssertEqual(corpus.cmVersion, CMContract.version)
        for item in corpus.cases {
            var state: CMState?
            var decisions: [String] = []
            for event in item.events {
                let result = CMReducer.reduce(state, event: event)
                state = result.state
                decisions.append(result.decision)
            }
            XCTAssertEqual(decisions, item.decisions, item.name)
            XCTAssertEqual(state?.taskStatus, item.task, item.name)
            XCTAssertEqual(state?.readState, item.read, item.name)
        }
    }

    func testManualRecoveryRequiresCurrentCleanCandidate() {
        let now: Int64 = 1_791_856_000_000
        let clean = CMRecoveryCandidate(conversationId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                                        documentId: "doc-1", sequence: 4, observedAt: now,
                                        visible: true, loadError: true, canRetry: true,
                                        hasDraft: false, running: false, waiting: false,
                                        hasAnswer: false, recoveryCanceled: false)
        XCTAssertEqual(ManualRecoveryPolicy.decide(candidate: clean,
                                                    currentConversation: clean.conversationId,
                                                    currentDocument: clean.documentId,
                                                    currentSequence: clean.sequence,
                                                    budget: nil, appActive: true, now: now),
                       .allow(next: CMRecoveryBudget(windowAt: now, attempts: 1)))
        var blocked = clean
        blocked = CMRecoveryCandidate(conversationId: blocked.conversationId,
                                      documentId: blocked.documentId, sequence: blocked.sequence,
                                      observedAt: blocked.observedAt, visible: true, loadError: true,
                                      canRetry: true, hasDraft: true, running: false, waiting: false,
                                      hasAnswer: false, recoveryCanceled: false)
        XCTAssertEqual(ManualRecoveryPolicy.decide(candidate: blocked,
                                                    currentConversation: blocked.conversationId,
                                                    currentDocument: blocked.documentId,
                                                    currentSequence: blocked.sequence,
                                                    budget: nil, appActive: true, now: now),
                       .deny("interactive_or_answer_present"))
    }

    func testObserverHasNoNetworkOrVisualMutationHooks() throws {
        let url = sourceRoot().appendingPathComponent("OptimizedResources/Observation/conversation-observer.js")
        let source = try String(contentsOf: url, encoding: .utf8)
        for denied in ["fetch(", "XMLHttpRequest", "localStorage", "appendChild", "insertAdjacentHTML",
                       "data-cm-state", "data-native-chat-status", "location.reload", "innerHTML ="] {
            XCTAssertFalse(source.contains(denied), denied)
        }
        XCTAssertTrue(source.contains("MutationObserver"))
        XCTAssertTrue(source.contains("optimizedConversation"))
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
