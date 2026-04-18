//
//  AppDelegate.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import OSLog
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let startupLogger = Logger(subsystem: "com.qoli.eisonAI", category: "StartupProbe")
    private static let lifecycleLogger = Logger(subsystem: "com.qoli.eisonAI", category: "AppLifecycle")
    private static let deepLinkLogger = Logger(subsystem: "com.qoli.eisonAI", category: "DeepLink")

    #if targetEnvironment(macCatalyst)
        private var sceneObserverTokens: [NSObjectProtocol] = []
    #endif

    deinit {
        #if targetEnvironment(macCatalyst)
            for token in sceneObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
        #endif
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        emitStartupLogProbe()
        if let launchURL = launchOptions?[.url] as? URL {
            _ = handleIncomingURL(launchURL, origin: "launchOptions")
        }
        #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                DispatchQueue.main.async { [weak self] in
                    self?.configureIOSAppOnMacWindowTitles(for: application)
                }
            }
        #endif
        #if targetEnvironment(macCatalyst)
            sceneObserverTokens.append(
                NotificationCenter.default.addObserver(
                    forName: UIScene.willConnectNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let windowScene = notification.object as? UIWindowScene else { return }
                    self?.configureMacCatalystTitlebar(for: windowScene)
                }
            )

            sceneObserverTokens.append(
                NotificationCenter.default.addObserver(
                    forName: UIScene.didActivateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let windowScene = notification.object as? UIWindowScene else { return }
                    self?.configureMacCatalystTitlebar(for: windowScene)
                }
            )

            DispatchQueue.main.async { [weak self] in
                self?.configureMacCatalystTitlebars(for: application)
            }
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        handleIncomingURL(url, origin: "openURL")
    }

    private func emitStartupLogProbe() {
        let timestamp = Date().ISO8601Format()
        let process = ProcessInfo.processInfo.processName
        let message = "[StartupProbe] app launched process=\(process) timestamp=\(timestamp)"
        print("[print] \(message)")
        Self.startupLogger.xcodeNotice(message)
        Self.startupLogger.xcodeError("[StartupProbe] logger error probe process=\(process) timestamp=\(timestamp)")
    }

    private func handleIncomingURL(_ url: URL, origin: String) -> Bool {
        handleMLXDownloadURL(url, origin: origin)
    }

    private func handleMLXDownloadURL(_ url: URL, origin: String) -> Bool {
        guard url.scheme?.lowercased() == "eisonai" else { return false }
        guard url.host?.lowercased() == AppConfig.mlxDownloadDeepLinkHost else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Self.deepLinkLogger.xcodeError("Failed to parse MLX download deeplink origin=\(origin) url=\(url.absoluteString)")
            return true
        }

        let repoID = components.queryItems?
            .first(where: { $0.name == AppConfig.mlxDownloadDeepLinkRepoQueryItem })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !repoID.isEmpty else {
            Self.deepLinkLogger.xcodeError("MLX download deeplink missing repo origin=\(origin) url=\(url.absoluteString)")
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

        Self.deepLinkLogger.xcodeNotice(
            "Received MLX download deeplink origin=\(origin) repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect) url=\(url.absoluteString)"
        )

        Task {
            let catalogService = MLXModelCatalogService()
            do {
                let model = try await catalogService.fetchModel(repoID: repoID)
                try await MLXDownloadCoordinator.shared.startInstall(
                    model: model,
                    source: source,
                    autoSelect: autoSelect
                )
                Self.deepLinkLogger.xcodeNotice(
                    "Started MLX download via deeplink repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect)"
                )
            } catch {
                Self.deepLinkLogger.xcodeError(
                    "Failed MLX download deeplink repo=\(repoID) source=\(source.rawValue) autoSelect=\(autoSelect) error=\(error.localizedDescription)"
                )
            }
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Self.lifecycleLogger.xcodeNotice(
            "[AppLifecycle] didBecomeActive job=\(MLXDownloadCoordinator.shared.currentJobLogSummary)"
        )
        #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                configureIOSAppOnMacWindowTitles(for: application)
            }
        #endif
        #if targetEnvironment(macCatalyst)
            configureMacCatalystTitlebars(for: application)
        #endif
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Self.lifecycleLogger.xcodeNotice(
            "[AppLifecycle] willResignActive job=\(MLXDownloadCoordinator.shared.currentJobLogSummary)"
        )
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Self.lifecycleLogger.xcodeNotice(
            "[AppLifecycle] didEnterBackground job=\(MLXDownloadCoordinator.shared.currentJobLogSummary)"
        )
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Self.lifecycleLogger.xcodeNotice(
            "[AppLifecycle] willTerminate job=\(MLXDownloadCoordinator.shared.currentJobLogSummary)"
        )
    }

    #if !targetEnvironment(macCatalyst)
        private func configureIOSAppOnMacWindowTitles(for application: UIApplication) {
            for scene in application.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windowScene.title = ""
            }
        }
    #endif

    #if targetEnvironment(macCatalyst)
        private func configureMacCatalystTitlebars(for application: UIApplication) {
            for scene in application.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                configureMacCatalystTitlebar(for: windowScene)
            }
        }

        private func configureMacCatalystTitlebar(for windowScene: UIWindowScene) {
            guard let titlebar = windowScene.titlebar else { return }
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
    #endif
}
