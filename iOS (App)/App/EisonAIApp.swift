//
//  EisonAIApp.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI
import UIKit

@main
struct EisonAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showsOnboarding = true

    var body: some Scene {
        WindowGroup {
            if showsOnboarding {
                OnboardingView {
                    showsOnboarding = false
                }
            } else {
                LibraryRootView()
            }
        }
    }
}
