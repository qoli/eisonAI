import Foundation

enum BrowserAgentRunState: Equatable {
    case idle
    case running(step: Int)
    case completed(String)
    case failed(String)
    case cancelled

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .running(let step):
            return "Running · Step \(step)"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Stopped"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Ready for a same-tab browser task."
        case .running:
            return "Observing the page and choosing the next action."
        case .completed(let summary), .failed(let summary):
            return summary
        case .cancelled:
            return "The current run was cancelled."
        }
    }
}

struct BrowserAgentLogEntry: Identifiable, Equatable {
    enum Kind {
        case decision
        case action
        case result
        case error
    }

    let id = UUID()
    let step: Int
    let title: String
    let detail: String
    let kind: Kind
    let timestamp = Date()
}

struct BrowserAgentTaskState: Codable, Equatable {
    enum Status: String, Codable {
        case idle
        case running
        case completed
        case failed
        case cancelled
    }

    struct PageContext: Codable, Equatable {
        var url: String
        var title: String
        var observationSummary: String
    }

    struct ActionRecord: Codable, Equatable {
        enum Outcome: String, Codable {
            case pending
            case succeeded
            case failed
        }

        var step: Int
        var summary: String
        var type: BrowserAgentActionType
        var index: Int?
        var targetURL: String?
        var textPreview: String?
        var option: String?
        var direction: String?
        var pages: Int?
        var milliseconds: Int?
        var outcome: Outcome
        var resultMessage: String
    }

    var goal: String
    var status: Status
    var currentStep: Int
    var maxSteps: Int
    var currentPage: PageContext?
    var pendingObjective: String
    var latestThought: String
    var latestModelSummary: String
    var rollingSummary: String
    var completedMilestones: [String]
    var importantFacts: [String]
    var knownFailures: [String]
    var lastAction: ActionRecord?

    static func idle(maxSteps: Int) -> BrowserAgentTaskState {
        BrowserAgentTaskState(
            goal: "",
            status: .idle,
            currentStep: 0,
            maxSteps: maxSteps,
            currentPage: nil,
            pendingObjective: "",
            latestThought: "",
            latestModelSummary: "",
            rollingSummary: "",
            completedMilestones: [],
            importantFacts: [],
            knownFailures: [],
            lastAction: nil
        )
    }
}

struct BrowserPageObservation: Codable {
    let url: String
    let title: String
    let header: String
    let content: String
    let footer: String
}

struct BrowserBridgeActionResult: Codable {
    let success: Bool
    let message: String
}

enum BrowserAgentActionType: String, Codable {
    case click
    case input
    case select
    case scroll
    case wait
    case navigate
    case pressEnter
}

struct BrowserAgentAction: Codable {
    let type: BrowserAgentActionType
    let index: Int?
    let text: String?
    let option: String?
    let url: String?
    let direction: String?
    let pages: Int?
    let milliseconds: Int?

    var summary: String {
        switch type {
        case .click:
            return "Click [\(index ?? -1)]"
        case .input:
            return "Input text into [\(index ?? -1)]"
        case .select:
            return "Select option in [\(index ?? -1)]"
        case .scroll:
            return "Scroll \(direction ?? "down")"
        case .wait:
            return "Wait \(milliseconds ?? 800)ms"
        case .navigate:
            return "Navigate to \(url ?? "")"
        case .pressEnter:
            return "Press Enter"
        }
    }
}

struct BrowserAgentResponse: Codable {
    let thought: String?
    let status: String
    let summary: String?
    let action: BrowserAgentAction?
}
