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
