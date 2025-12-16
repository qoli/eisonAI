//
//  ViewController.swift
//  Shared (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation
import WebKit
import os.log

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "com.qoli.eisonAI.Extension"
let appGroupIdentifier = "group.com.qoli.eisonAI"
let systemPromptKey = "eison.systemPrompt"

let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 5-6 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = true
#endif

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    private func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func loadSystemPrompt() -> String {
        guard let stored = sharedDefaults()?.string(forKey: systemPromptKey) else {
            return defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultSystemPrompt
        }
        return stored
    }

    private func saveSystemPrompt(_ value: String?) {
        guard let defaults = sharedDefaults() else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: systemPromptKey)
        }
    }

    private func sendSystemPromptToWebView(status: String? = nil) {
        var payload: [String: Any] = ["prompt": loadSystemPrompt()]
        if let status {
            payload["status"] = status
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let json = String(data: data, encoding: .utf8)
        else { return }

        webView.evaluateJavaScript("setSystemPromptFromNative(\(json))")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
        sendSystemPromptToWebView()
#elseif os(macOS)
        webView.evaluateJavaScript("show('mac')")
        sendSystemPromptToWebView()

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                // Insert code to inform the user that something went wrong.
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show('mac', \(state.isEnabled), false)")
                }
            }
        }
#endif
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String {
#if os(macOS)
            if text == "open-preferences" {
                SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                    guard error == nil else {
                        return
                    }

                    DispatchQueue.main.async {
                        NSApp.terminate(self)
                    }
                }
            }
#endif
            return
        }

        guard
            let dict = message.body as? [String: Any],
            let command = dict["command"] as? String
        else { return }

        switch command {
        case "setSystemPrompt":
            let prompt = dict["prompt"] as? String
            saveSystemPrompt(prompt)
            sendSystemPromptToWebView(status: "Saved.")
        case "resetSystemPrompt":
            saveSystemPrompt(nil)
            sendSystemPromptToWebView(status: "Reset to default.")
        default:
            os_log(.default, "[Eison-App] Unknown command: %@", command)
        }
    }

}
