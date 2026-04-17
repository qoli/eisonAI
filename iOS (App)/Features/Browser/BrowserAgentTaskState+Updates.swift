import Foundation

extension BrowserAgentTaskState {
    static func starting(
        goal: String,
        pageURL: String,
        pageTitle: String,
        maxSteps: Int
    ) -> BrowserAgentTaskState {
        var state = BrowserAgentTaskState.idle(maxSteps: maxSteps)
        state.goal = Self.trimmedValue(goal, limit: Limits.goal)
        state.status = .running
        state.currentStep = 1
        state.nextGoal = Self.trimmedValue(goal, limit: Limits.stepValue)
        state.currentPage = PageContext(
            url: Self.trimmedValue(pageURL, limit: Limits.url),
            title: Self.trimmedValue(pageTitle, limit: Limits.title),
            observationSummary: ""
        )
        return state
    }

    mutating func updateLocation(url: String, title: String) {
        guard !url.isEmpty || !title.isEmpty else { return }

        let existingSummary = currentPage?.observationSummary ?? ""
        currentPage = PageContext(
            url: Self.trimmedValue(url, limit: Limits.url),
            title: Self.trimmedValue(title, limit: Limits.title),
            observationSummary: existingSummary
        )
    }

    mutating func recordObservation(_ observation: BrowserPageObservation, step: Int) {
        currentStep = step
        currentPage = PageContext(
            url: Self.trimmedValue(observation.url, limit: Limits.url),
            title: Self.trimmedValue(observation.title, limit: Limits.title),
            observationSummary: Self.compactObservationSummary(observation)
        )
    }

    mutating func recordModelResponse(_ response: BrowserAgentResponse, step: Int) {
        currentStep = step
        latestEvaluation = Self.trimmedValue(response.evaluationPreviousGoal, limit: Limits.stepValue)
        latestMemory = Self.trimmedValue(response.memory, limit: Limits.stepValue)
        nextGoal = Self.trimmedValue(response.nextGoal, limit: Limits.stepValue)
        lastStepSummary = Self.trimmedValue(response.summary ?? "", limit: Limits.stepValue)
        lastValidationError = ""
    }

    mutating func recordPlannedAction(_ action: BrowserAgentAction, step: Int) {
        lastAction = ActionRecord(
            step: step,
            summary: Self.trimmedValue(action.summary, limit: Limits.actionSummary),
            type: action.type,
            index: action.index,
            targetURL: Self.trimmedValue(action.url ?? "", limit: Limits.url).nilIfEmpty,
            textPreview: Self.previewText(action.text, limit: Limits.preview),
            option: Self.trimmedValue(action.option ?? "", limit: Limits.preview).nilIfEmpty,
            direction: Self.trimmedValue(action.direction ?? "", limit: 40).nilIfEmpty,
            pages: action.pages,
            milliseconds: action.milliseconds,
            outcome: .pending,
            resultMessage: ""
        )
    }

    mutating func recordActionResult(
        _ result: BrowserBridgeActionResult,
        for action: BrowserAgentAction,
        step: Int
    ) {
        var record = lastAction ?? ActionRecord(
            step: step,
            summary: Self.trimmedValue(action.summary, limit: Limits.actionSummary),
            type: action.type,
            index: action.index,
            targetURL: Self.trimmedValue(action.url ?? "", limit: Limits.url).nilIfEmpty,
            textPreview: Self.previewText(action.text, limit: Limits.preview),
            option: Self.trimmedValue(action.option ?? "", limit: Limits.preview).nilIfEmpty,
            direction: Self.trimmedValue(action.direction ?? "", limit: 40).nilIfEmpty,
            pages: action.pages,
            milliseconds: action.milliseconds,
            outcome: .pending,
            resultMessage: ""
        )

        record.outcome = result.success ? .succeeded : .failed
        record.resultMessage = Self.trimmedValue(result.message, limit: Limits.stepValue)
        lastAction = record

        if result.success {
            lastValidationError = ""
            switch action.type {
            case .navigate:
                if let url = action.url, !url.isEmpty {
                    appendUniqueLine("Navigated toward \(url).", to: \.importantFacts)
                }
            case .input:
                appendUniqueLine("Filled a page field for the current task.", to: \.importantFacts)
            case .select:
                appendUniqueLine("Updated a select control on the page.", to: \.importantFacts)
            case .pressEnter:
                appendUniqueLine("Submitted the focused field with Enter.", to: \.importantFacts)
            case .click, .scroll, .wait:
                break
            }
        } else {
            recordRuntimeIssue("Step \(step) \(action.summary) failed: \(result.message)")
        }
    }

    mutating func recordRuntimeIssue(_ message: String) {
        let normalized = Self.trimmedValue(message, limit: Limits.stepValue)
        guard !normalized.isEmpty else { return }

        lastValidationError = normalized
        appendUniqueLine(normalized, to: \.knownFailures)
    }

    mutating func appendUniqueLine(
        _ rawValue: String,
        to keyPath: WritableKeyPath<BrowserAgentTaskState, [String]>
    ) {
        let normalized = Self.trimmedValue(rawValue, limit: Limits.stepValue)
        guard !normalized.isEmpty else { return }

        var lines = self[keyPath: keyPath]
        if lines.contains(normalized) { return }
        lines.append(normalized)
        if lines.count > Limits.listCount {
            lines.removeFirst(lines.count - Limits.listCount)
        }
        self[keyPath: keyPath] = lines
    }

    private enum Limits {
        static let goal = 320
        static let url = 260
        static let title = 140
        static let preview = 80
        static let actionSummary = 140
        static let stepValue = 240
        static let observationSummary = 320
        static let listCount = 6
    }

    private static func compactObservationSummary(_ observation: BrowserPageObservation) -> String {
        let summary = [
            observation.header,
            observation.content,
            observation.footer,
        ]
        .joined(separator: "\n")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedValue(summary, limit: Limits.observationSummary)
    }

    private static func previewText(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let preview = trimmedValue(text, limit: limit)
        return preview.isEmpty ? nil : preview
    }

    private static func trimmedValue(_ value: String, limit: Int) -> String {
        let cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }
        return String(cleaned.prefix(limit))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
