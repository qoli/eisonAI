import Foundation

enum BrowserAgentResponseParserError: LocalizedError, Equatable {
    case missingJSONObject
    case invalidJSONObject
    case missingRequiredField(String)
    case invalidStatus(String)
    case missingActionForContinue
    case unexpectedActionForTerminalState(BrowserAgentResponseStatus)
    case invalidAction(String)

    var errorDescription: String? {
        switch self {
        case .missingJSONObject:
            return "The browser agent response did not contain a valid JSON object."
        case .invalidJSONObject:
            return "The browser agent response contained malformed JSON."
        case .missingRequiredField(let field):
            return "The browser agent response is missing required field '\(field)'."
        case .invalidStatus(let status):
            return "The browser agent response used an unsupported status '\(status)'."
        case .missingActionForContinue:
            return "The browser agent must return an action when status is 'continue'."
        case .unexpectedActionForTerminalState(let status):
            return "The browser agent must omit action when status is '\(status.rawValue)'."
        case .invalidAction(let message):
            return "The browser agent returned an invalid action: \(message)"
        }
    }
}

enum BrowserAgentResponseParser {
    static func parse(_ text: String) throws -> BrowserAgentResponse {
        let rootObject = try extractRootObject(from: text)

        let evaluation = try requiredString(
            in: rootObject,
            keys: ["evaluationPreviousGoal", "evaluation_previous_goal"]
        )
        let memory = try requiredString(in: rootObject, keys: ["memory"])
        let nextGoal = try requiredString(in: rootObject, keys: ["nextGoal", "next_goal"])
        let status = try parseStatus(from: rootObject)
        let summary = optionalString(in: rootObject, keys: ["summary"])

        let rawAction = dictionaryValue(in: rootObject, keys: ["action", "nextAction", "next_action"])
        let action = try rawAction.map(decodeAction(_:))

        let response = BrowserAgentResponse(
            evaluationPreviousGoal: evaluation,
            memory: memory,
            nextGoal: nextGoal,
            status: status,
            summary: summary,
            action: action
        )

        switch response.status {
        case .continue:
            guard response.action != nil else {
                throw BrowserAgentResponseParserError.missingActionForContinue
            }
        case .done, .failed:
            if response.action != nil {
                throw BrowserAgentResponseParserError.unexpectedActionForTerminalState(response.status)
            }
        }

        return response
    }

    private static func extractRootObject(from text: String) throws -> [String: Any] {
        let candidates = extractJSONCandidates(from: strippedMarkdownFences(from: text))

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            guard
                let json = try? JSONSerialization.jsonObject(with: data),
                let dictionary = unwrapJSONObject(json)
            else {
                continue
            }
            return dictionary
        }

        if candidates.isEmpty {
            throw BrowserAgentResponseParserError.missingJSONObject
        }
        throw BrowserAgentResponseParserError.invalidJSONObject
    }

    private static func unwrapJSONObject(_ json: Any) -> [String: Any]? {
        guard let dictionary = json as? [String: Any] else { return nil }

        for key in ["response", "output", "result", "browserAgentResponse"] {
            if let nested = dictionary[key] as? [String: Any] {
                return unwrapJSONObject(nested) ?? nested
            }
        }

        return dictionary
    }

    private static func parseStatus(from object: [String: Any]) throws -> BrowserAgentResponseStatus {
        let rawStatus = try requiredString(in: object, keys: ["status"]).lowercased()
        guard let status = BrowserAgentResponseStatus(rawValue: rawStatus) else {
            throw BrowserAgentResponseParserError.invalidStatus(rawStatus)
        }
        return status
    }

    private static func decodeAction(_ object: [String: Any]) throws -> BrowserAgentAction {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BrowserAgentResponseParserError.invalidAction("action payload is not JSON serializable")
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded: BrowserAgentAction
        do {
            decoded = try JSONDecoder().decode(BrowserAgentAction.self, from: data)
        } catch {
            throw BrowserAgentResponseParserError.invalidAction(error.localizedDescription)
        }

        do {
            return try decoded.validated()
        } catch let validationError as BrowserAgentResponseParserError {
            throw validationError
        } catch {
            throw BrowserAgentResponseParserError.invalidAction(error.localizedDescription)
        }
    }

    private static func requiredString(in object: [String: Any], keys: [String]) throws -> String {
        if let value = optionalString(in: object, keys: keys) {
            return value
        }
        throw BrowserAgentResponseParserError.missingRequiredField(keys[0])
    }

    private static func optionalString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let stringValue = value as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func dictionaryValue(in object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let nested = object[key] as? [String: Any] {
                return nested
            }
        }
        return nil
    }

    private static func strippedMarkdownFences(from text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONCandidates(from text: String) -> [String] {
        let characters = Array(text)
        var candidates: [String] = []

        guard !characters.isEmpty else { return candidates }

        for startIndex in characters.indices where characters[startIndex] == "{" {
            var depth = 0
            var isInsideString = false
            var isEscaping = false

            for currentIndex in startIndex ..< characters.count {
                let character = characters[currentIndex]

                if isEscaping {
                    isEscaping = false
                    continue
                }

                if character == "\\" {
                    isEscaping = true
                    continue
                }

                if character == "\"" {
                    isInsideString.toggle()
                    continue
                }

                if isInsideString {
                    continue
                }

                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        candidates.append(String(characters[startIndex ... currentIndex]))
                        break
                    }
                }
            }
        }

        return Array(Set(candidates)).sorted { $0.count > $1.count }
    }
}

private extension BrowserAgentAction {
    func validated() throws -> BrowserAgentAction {
        switch type {
        case .click:
            guard let index, index >= 0 else {
                throw BrowserAgentResponseParserError.invalidAction("click requires a non-negative index")
            }
            return BrowserAgentAction(
                type: .click,
                index: index,
                text: nil,
                option: nil,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        case .input:
            guard let index, index >= 0 else {
                throw BrowserAgentResponseParserError.invalidAction("input requires a non-negative index")
            }
            return BrowserAgentAction(
                type: .input,
                index: index,
                text: text ?? "",
                option: nil,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        case .select:
            guard let index, index >= 0 else {
                throw BrowserAgentResponseParserError.invalidAction("select requires a non-negative index")
            }
            guard let option = option?.trimmingCharacters(in: .whitespacesAndNewlines), !option.isEmpty else {
                throw BrowserAgentResponseParserError.invalidAction("select requires a non-empty option")
            }
            return BrowserAgentAction(
                type: .select,
                index: index,
                text: nil,
                option: option,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        case .scroll:
            let normalizedDirection = direction?.lowercased() == "up" ? "up" : "down"
            guard let pages, pages > 0 else {
                throw BrowserAgentResponseParserError.invalidAction("scroll requires pages > 0")
            }
            if let index, index < 0 {
                throw BrowserAgentResponseParserError.invalidAction("scroll index must be non-negative")
            }
            return BrowserAgentAction(
                type: .scroll,
                index: index,
                text: nil,
                option: nil,
                url: nil,
                direction: normalizedDirection,
                pages: pages,
                milliseconds: nil
            )
        case .wait:
            guard let milliseconds, milliseconds > 0 else {
                throw BrowserAgentResponseParserError.invalidAction("wait requires milliseconds > 0")
            }
            return BrowserAgentAction(
                type: .wait,
                index: nil,
                text: nil,
                option: nil,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: milliseconds
            )
        case .navigate:
            guard let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                throw BrowserAgentResponseParserError.invalidAction("navigate requires a non-empty url")
            }
            return BrowserAgentAction(
                type: .navigate,
                index: nil,
                text: nil,
                option: nil,
                url: url,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        case .pressEnter:
            if let index, index < 0 {
                throw BrowserAgentResponseParserError.invalidAction("pressEnter index must be non-negative")
            }
            return BrowserAgentAction(
                type: .pressEnter,
                index: index,
                text: nil,
                option: nil,
                url: nil,
                direction: nil,
                pages: nil,
                milliseconds: nil
            )
        }
    }
}
