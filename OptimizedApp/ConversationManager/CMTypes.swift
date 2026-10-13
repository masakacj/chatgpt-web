import Foundation

enum CMTaskStatus: String, Codable, CaseIterable {
    case running, waiting, completed, error, stopped, unknown
}

enum CMReadState: String, Codable {
    case read, unread, unknown
}

enum CMEvidenceSource: String, Codable, Hashable {
    case none, nativeTurn, nativeSidebar, localView, localSubmit, localStop, legacy
}

enum CMEventKind: String, Codable {
    case native, sidebar, read, submit, stop, restore
}

struct CMEvent: Codable, Equatable {
    var kind: CMEventKind
    var conversationId: String
    var turnKey: String?
    var documentId: String?
    var ownerGeneration: String
    var eventId: String
    var at: Int64
    var sequence: Int
    var nativeStatus: CMTaskStatus = .unknown
    var nativeSpinner = false
    var nativeSpinnerOff = false
    var nativeUnread = false
    var answerReady = false
    var visible = false
    var selected = false
    var newTurn = false
    var activeGenerationControl = false
    var restoredStatus: CMTaskStatus = .unknown
    var restoredRead: CMReadState = .unknown
}

struct CMState: Codable, Equatable {
    static let schema = 2
    var schema = CMState.schema
    var conversationId: String
    var turnKey: String?
    var documentId: String?
    var ownerGeneration: String?
    var lastSequence = 0
    var taskStatus: CMTaskStatus = .unknown
    var readState: CMReadState = .unknown
    var evidenceSource: CMEvidenceSource = .none
    var evidenceAt: Int64 = 0
    var updatedAt: Int64 = 0
    var readAt: Int64 = 0
    var terminalAt: Int64 = 0
    var revision = 0
    var pendingSubmit = false
    var previousTurnKey: String?
    var seenEvents: [String] = []
    var conflicts = 0
}

struct CMProjection: Codable, Equatable {
    var task: CMTaskStatus
    var read: CMReadState
    var certainty: String
    var revision: Int
}

struct CMReduction: Equatable {
    var state: CMState?
    var decision: String
}

enum CMContract {
    static let protocolVersion = 2
    static let version = "0.2.2"
    static let idPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{12,80}$")

    static func validConversationID(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return idPattern.firstMatch(in: value, range: range)?.range == range
    }

    static func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
