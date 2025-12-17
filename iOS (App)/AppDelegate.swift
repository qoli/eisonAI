//
//  AppDelegate.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }
}

@main
struct EisonAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private enum AppConfig {
    static let appGroupIdentifier = "group.com.qoli.eisonAI"
    static let systemPromptKey = "eison.systemPrompt"

    static let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 5-6 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""
}

private struct SystemPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.systemPromptKey) else {
            return AppConfig.defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultSystemPrompt
        }
        return stored
    }

    func save(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: AppConfig.systemPromptKey)
        }
    }
}

private struct RootView: View {
    private let store = SystemPromptStore()

    @State private var draftPrompt = ""
    @State private var status = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Safari Extension") {
                    Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                    Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                        .foregroundStyle(.secondary)
                }

                Section("System prompt") {
                    Text("Used by the Safari extension popup summary.")
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draftPrompt)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Button("Save") {
                            store.save(draftPrompt)
                            draftPrompt = store.load()
                            status = "Saved."
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset to default") {
                            store.save(nil)
                            draftPrompt = store.load()
                            status = "Reset to default."
                        }
                        .buttonStyle(.bordered)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("eisonAI")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftPrompt = store.load()
        }
    }
}
