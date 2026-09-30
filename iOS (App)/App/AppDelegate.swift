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
        emitAppDirectoryPaths()
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

    private func emitStartupLogProbe() {
        let timestamp = Date().ISO8601Format()
        let process = ProcessInfo.processInfo.processName
        let message = "[StartupProbe] app launched process=\(process) timestamp=\(timestamp)"
        print("[print] \(message)")
        Self.startupLogger.xcodeNotice(message)
        Self.startupLogger.xcodeError("[StartupProbe] logger error probe process=\(process) timestamp=\(timestamp)")
    }

    private func emitAppDirectoryPaths() {
        let fileManager = FileManager.default
        let homeDirectory = NSHomeDirectory()
        let bundlePath = Bundle.main.bundlePath
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "unavailable"
        let libraryPath = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?.path ?? "unavailable"
        let cachesPath = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? "unavailable"
        let temporaryPath = fileManager.temporaryDirectory.path
        let currentDirectory = fileManager.currentDirectoryPath

        print("[AppStartup] sandbox home: \(homeDirectory)")
        print("[AppStartup] documents: \(documentsPath)")
        print("[AppStartup] library: \(libraryPath)")
        print("[AppStartup] caches: \(cachesPath)")
        print("[AppStartup] temporary: \(temporaryPath)")
        print("[AppStartup] bundle: \(bundlePath)")
        print("[AppStartup] current working directory: \(currentDirectory)")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                configureIOSAppOnMacWindowTitles(for: application)
            }
        #endif
        #if targetEnvironment(macCatalyst)
            configureMacCatalystTitlebars(for: application)
        #endif
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
