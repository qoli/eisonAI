//
//  EisonAIApp.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import StoreKit
import SwiftUI
import UIKit

@main
struct EisonAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootGateView()
        }
    }
}

private struct RootGateView: View {
    @AppStorage(
        AppConfig.onboardingCompletedKey,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    ) private var onboardingCompleted = false
    @State private var hasCheckedEntitlements = false
    @State private var hasLifetimeAccess = false

    var body: some View {
        Group {
            if onboardingCompleted {
                LibraryRootView()
            } else if !hasCheckedEntitlements {
                ProgressView()
            } else if hasLifetimeAccess {
                LibraryRootView()
            } else {
                OnboardingView {
                    onboardingCompleted = true
                }
            }
        }
        .task {
            await refreshLifetimeAccessIfNeeded()
        }
    }

    @MainActor
    private func refreshLifetimeAccessIfNeeded() async {
        guard !hasCheckedEntitlements else { return }
        var hasAccess = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if transaction.productID == AppConfig.lifetimeAccessProductId {
                hasAccess = true
                break
            }
        }
        hasLifetimeAccess = hasAccess
        hasCheckedEntitlements = true
        if hasAccess {
            onboardingCompleted = true
        }
    }
}
