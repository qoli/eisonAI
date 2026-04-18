import Foundation
import OSLog

@MainActor
final class MLXDownloadDeepLinkHandler {
    static let shared = MLXDownloadDeepLinkHandler()

    private enum DebugStartupConfig {
        static let repoEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_REPO"
        static let sourceEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_SOURCE"
        static let autoSelectEnvironmentKey = "EISONAI_DEBUG_MLX_DOWNLOAD_AUTO_SELECT"
        static let purgeExistingEnvironmentKey = "EISONAI_DEBUG_MLX_PURGE_EXISTING"

        static let repoArgument = "-eisonai-debug-mlx-download-repo"
        static let sourceArgument = "-eisonai-debug-mlx-download-source"
        static let autoSelectArgument = "-eisonai-debug-mlx-download-auto-select"
        static let purgeExistingArgument = "-eisonai-debug-mlx-purge-existing"
    }

    private let logger = Logger(subsystem: "com.qoli.eisonAI", category: "DeepLink")
    private let catalogService = MLXModelCatalogService()
    private let modelStore = MLXModelStore()
    private var lastHandledURL: String?
    private var lastHandledAt: Date = .distantPast
    private var didHandleDebugStartupTrigger = false

    private init() {}

    func handleDebugStartupTriggerIfPresent(origin: String) {
        guard !didHandleDebugStartupTrigger else { return }

        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = processInfo.arguments

        let environmentRepo = environment[DebugStartupConfig.repoEnvironmentKey]
        let argumentRepo = argumentValue(for: DebugStartupConfig.repoArgument, in: arguments)
        let environmentSource = environment[DebugStartupConfig.sourceEnvironmentKey]
        let argumentSource = argumentValue(for: DebugStartupConfig.sourceArgument, in: arguments)
        let environmentAutoSelect = environment[DebugStartupConfig.autoSelectEnvironmentKey]
        let argumentAutoSelect = argumentValue(for: DebugStartupConfig.autoSelectArgument, in: arguments)
        let environmentPurgeExisting = environment[DebugStartupConfig.purgeExistingEnvironmentKey]
        let argumentPurgeExisting = argumentValue(for: DebugStartupConfig.purgeExistingArgument, in: arguments)

        logger.xcodeNotice(
            "Debug MLX startup probe origin=\(origin) envRepo=\(environmentRepo ?? "nil") argRepo=\(argumentRepo ?? "nil") envSource=\(environmentSource ?? "nil") argSource=\(argumentSource ?? "nil") envAutoSelect=\(environmentAutoSelect ?? "nil") argAutoSelect=\(argumentAutoSelect ?? "nil") envPurge=\(environmentPurgeExisting ?? "nil") argPurge=\(argumentPurgeExisting ?? "nil")"
        )

        let repoID = environmentRepo ?? argumentRepo
        guard let repoID, !repoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.xcodeNotice("No debug MLX startup trigger present origin=\(origin)")
            return
        }

        let source = environmentSource ??
            argumentSource ??
            MLXDownloadJob.Source.catalog.rawValue
        let autoSelect = environmentAutoSelect ??
            argumentAutoSelect ??
            "1"
        let shouldPurgeExisting = parseEnabledFlag(environmentPurgeExisting ?? argumentPurgeExisting)

        didHandleDebugStartupTrigger = true

        let encodedRepo = repoID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repoID
        let urlString =
            "eisonai://\(AppConfig.mlxDownloadDeepLinkHost)?\(AppConfig.mlxDownloadDeepLinkRepoQueryItem)=\(encodedRepo)&\(AppConfig.mlxDownloadDeepLinkSourceQueryItem)=\(source)&\(AppConfig.mlxDownloadDeepLinkAutoSelectQueryItem)=\(autoSelect)"
        guard let url = URL(string: urlString) else {
            logger.xcodeError("Failed to construct debug MLX startup trigger URL origin=\(origin) repo=\(repoID)")
            return
        }

        logger.xcodeNotice(
            "Handling debug MLX startup trigger origin=\(origin) repo=\(repoID) source=\(source) autoSelect=\(autoSelect) purgeExisting=\(shouldPurgeExisting)"
        )

        MLXDownloadCoordinator.shared.refreshState()
        if shouldPurgeExisting {
            purgeExistingModelArtifacts(for: repoID, origin: origin)
        }
        _ = handle(url, origin: origin)
    }

    func handle(_ url: URL, origin: String) -> Bool {
        guard url.scheme?.lowercased() == "eisonai" else { return false }
        guard url.host?.lowercased() == AppConfig.mlxDownloadDeepLinkHost else { return false }

        let absoluteURL = url.absoluteString
        if absoluteURL == lastHandledURL, Date.now.timeIntervalSince(lastHandledAt) < 2 {
            logger.xcodeNotice("Ignoring duplicate MLX download deeplink origin=\(origin) url=\(absoluteURL)")
            return true
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.xcodeError("Failed to parse MLX download deeplink origin=\(origin) url=\(absoluteURL)")
            return true
        }

        let repoID = components.queryItems?
            .first(where: { $0.name == AppConfig.mlxDownloadDeepLinkRepoQueryItem })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !repoID.isEmpty else {
            logger.xcodeError("MLX download deeplink missing repo origin=\(origin) url=\(absoluteURL)")
            return true
        }

        let sourceValue = components.queryItems?
            .first(where: { $0.name == AppConfig.mlxDownloadDeepLinkSourceQueryItem })?
            .value?
            .lowercased() ?? MLXDownloadJob.Source.catalog.rawValue
        let source = MLXDownloadJob.Source(rawValue: sourceValue) ?? .catalog

        let autoSelectValue = components.queryItems?
            .first(where: { $0.name == AppConfig.mlxDownloadDeepLinkAutoSelectQueryItem })?
            .value?
            .lowercased()
        let autoSelect = switch autoSelectValue {
        case "0", "false", "no":
            false
        default:
            true
        }

        lastHandledURL = absoluteURL
        lastHandledAt = .now

        logger.xcodeNotice(
            "Received MLX download deeplink origin=\(origin) repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect) url=\(absoluteURL)"
        )

        Task { [catalogService] in
            do {
                let model = try await catalogService.fetchModel(repoID: repoID)
                try await MLXDownloadCoordinator.shared.startInstall(
                    model: model,
                    source: source,
                    autoSelect: autoSelect
                )
                logger.xcodeNotice(
                    "Started MLX download via deeplink repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect)"
                )
            } catch {
                logger.xcodeError(
                    "Failed MLX download deeplink repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect) error=\(error.localizedDescription)"
                )
            }
        }

        return true
    }

    private func argumentValue(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private func parseEnabledFlag(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private func purgeExistingModelArtifacts(for repoID: String, origin: String) {
        do {
            try AnyLanguageModelClient.deleteLocalModelArtifacts(modelID: repoID)
            modelStore.removeInstalledModel(id: repoID)
            logger.xcodeNotice("Purged existing MLX model artifacts origin=\(origin) repo=\(repoID)")
        } catch {
            logger.xcodeError(
                "Failed to purge existing MLX model artifacts origin=\(origin) repo=\(repoID) error=\(error.localizedDescription)"
            )
        }
    }
}
