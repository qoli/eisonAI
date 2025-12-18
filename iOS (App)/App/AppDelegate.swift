//
//  AppDelegate.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
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
