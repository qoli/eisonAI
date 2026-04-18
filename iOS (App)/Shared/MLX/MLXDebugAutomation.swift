import Foundation

struct MLXDebugAutomationRequest: Equatable, Sendable {
    let repoID: String
    let source: MLXDownloadJob.Source
    let autoSelect: Bool
    let purgeExisting: Bool
}

struct MLXDebugAutomation: Equatable, Sendable {
    enum Route: String, Sendable {
        case directDownload = "direct"
        case mlxModelsPage = "page"
    }

    static let current = MLXDebugAutomation.load()

    let route: Route?
    let request: MLXDebugAutomationRequest?

    var shouldDirectDownloadOnLaunch: Bool {
        route == .directDownload && request != nil
    }

    var shouldPresentMLXModelsPage: Bool {
        route == .mlxModelsPage && request != nil
    }

    private enum Config {
        static let routeEnvironmentKey = "EISONAI_DEBUG_MLX_ROUTE"
        static let repoEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_REPO"
        static let sourceEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_SOURCE"
        static let autoSelectEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_AUTO_SELECT"
        static let purgeExistingEnvironmentKey = "EISONAI_DEBUG_MLX_PURGE_EXISTING"

        static let routeArgument = "-eisonai-debug-mlx-route"
        static let repoArgument = "-eisonai-debug-mlx-download-repo"
        static let sourceArgument = "-eisonai-debug-mlx-download-source"
        static let autoSelectArgument = "-eisonai-debug-mlx-download-auto-select"
        static let purgeExistingArgument = "-eisonai-debug-mlx-purge-existing"
    }

    private static func load() -> MLXDebugAutomation {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = processInfo.arguments

        let routeValue = environment[Config.routeEnvironmentKey] ??
            argumentValue(for: Config.routeArgument, in: arguments)
        let repoID = environment[Config.repoEnvironmentKey] ??
            argumentValue(for: Config.repoArgument, in: arguments)
        let sourceValue = environment[Config.sourceEnvironmentKey] ??
            argumentValue(for: Config.sourceArgument, in: arguments)
        let autoSelectValue = environment[Config.autoSelectEnvironmentKey] ??
            argumentValue(for: Config.autoSelectArgument, in: arguments)
        let purgeExistingValue = environment[Config.purgeExistingEnvironmentKey] ??
            argumentValue(for: Config.purgeExistingArgument, in: arguments)

        let route = routeValue
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap(Route.init(rawValue:))

        guard let repoID = repoID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !repoID.isEmpty
        else {
            return MLXDebugAutomation(route: route, request: nil)
        }

        let source = sourceValue
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap(MLXDownloadJob.Source.init(rawValue:)) ?? MLXDownloadJob.Source.catalog

        let request = MLXDebugAutomationRequest(
            repoID: repoID,
            source: source,
            autoSelect: parseEnabledFlag(autoSelectValue, defaultValue: true),
            purgeExisting: parseEnabledFlag(purgeExistingValue, defaultValue: false)
        )

        return MLXDebugAutomation(route: route, request: request)
    }

    private static func argumentValue(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private static func parseEnabledFlag(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return defaultValue
        }
    }
}
