import Foundation

struct BrowserAutomationLaunchConfiguration: Equatable {
    static let defaultURLString = "https://www.wikipedia.org"
    static let defaultPrompt = "Check Wikipedia about Oscars 2026. Tell me who won the best picture."

    let urlString: String
    let prompt: String
    let autoRun: Bool
    let maxRuntimeSeconds: TimeInterval?

    var initialURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    static func current(from environment: [String: String] = ProcessInfo.processInfo.environment) -> BrowserAutomationLaunchConfiguration? {
        guard environment.boolValue(for: "EISON_UI_TEST_OPEN_BROWSER") else { return nil }

        return BrowserAutomationLaunchConfiguration(
            urlString: environment["EISON_UI_TEST_BROWSER_URL"] ?? defaultURLString,
            prompt: environment["EISON_UI_TEST_BROWSER_PROMPT"] ?? defaultPrompt,
            autoRun: environment.boolValue(for: "EISON_UI_TEST_BROWSER_AUTO_RUN", default: true),
            maxRuntimeSeconds: environment.timeIntervalValue(for: "EISON_UI_TEST_BROWSER_MAX_RUNTIME_SECONDS")
        )
    }
}

struct AppAutomationLaunchConfiguration: Equatable {
    let skipOnboarding: Bool
    let browserAutomation: BrowserAutomationLaunchConfiguration?

    static func current(from environment: [String: String] = ProcessInfo.processInfo.environment) -> AppAutomationLaunchConfiguration {
        AppAutomationLaunchConfiguration(
            skipOnboarding: environment.boolValue(for: "EISON_UI_TEST_SKIP_ONBOARDING"),
            browserAutomation: BrowserAutomationLaunchConfiguration.current(from: environment)
        )
    }
}

private extension Dictionary where Key == String, Value == String {
    func boolValue(for key: String, default fallback: Bool = false) -> Bool {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return fallback
        }

        switch value {
        case "1", "true", "yes", "y":
            return true
        case "0", "false", "no", "n":
            return false
        default:
            return fallback
        }
    }

    func timeIntervalValue(for key: String) -> TimeInterval? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let seconds = TimeInterval(value),
              seconds > 0 else {
            return nil
        }
        return seconds
    }
}
