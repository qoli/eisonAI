//
//  ViewController.swift
//  Shared (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import WebKit
import os.log

#if canImport(EisonAIKit)
import EisonAIKit
#endif

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "com.qoli.eisonAI.Extension"

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

#if os(iOS)
        self.webView.scrollView.isScrollEnabled = false
#endif

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if os(iOS)
        webView.evaluateJavaScript("show('ios')")
#elseif os(macOS)
        webView.evaluateJavaScript("show('mac')")

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

#if os(iOS)
        if let body = message.body as? [String: Any],
           let command = body["command"] as? String {
            handleIOSCommand(command)
        }
#endif
    }

}

#if os(iOS)
extension ViewController {
    private func handleIOSCommand(_ command: String) {
        switch command {
        case "model.getStatus":
            Task { [weak self] in
                guard let self else { return }
                let status = await ModelDownloadManager.shared.refreshStatus()
                self.pushModelStatusToWebView(status)
            }

        case "model.download":
            ModelDownloadManager.shared.onStatusChange = { [weak self] status in
                self?.pushModelStatusToWebView(status)
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await ModelDownloadManager.shared.startDownload()
                } catch {
                    let status = await ModelDownloadManager.shared.refreshStatus()
                    self.pushModelStatusToWebView(status)
                }
            }

        case "model.cancel":
            ModelDownloadManager.shared.cancelDownload()
            Task { [weak self] in
                guard let self else { return }
                let status = await ModelDownloadManager.shared.refreshStatus()
                self.pushModelStatusToWebView(status)
            }

        case "llm.ping":
            Task { [weak self] in
                guard let self else { return }
                await self.runLLMPingTest()
            }

        default:
            break
        }
    }

    private func pushModelStatusToWebView(_ status: ModelDownloadManager.Status) {
        guard let data = try? JSONEncoder().encode(status),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("updateModelStatus(\(json));")
    }

    private struct LLMPingResult: Codable {
        let state: String // idle, running, done, error
        let requestText: String
        let responseText: String?
        let error: String?
    }

    private func pushLLMPingResultToWebView(_ result: LLMPingResult) {
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("updateLLMPingResult(\(json));")
    }

    @MainActor
    private func runLLMPingTest() async {
        let requestText = "Ping"
        pushLLMPingResultToWebView(.init(state: "running", requestText: requestText, responseText: nil, error: nil))

        do {
            let status = await ModelDownloadManager.shared.refreshStatus()
            guard status.state == "ready" else {
                throw NSError(
                    domain: "EisonAI",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Model not ready (\(status.state)). Please download the model first."]
                )
            }

            let start = Date()
            let response = try await LLMPingRunner.shared.respond(to: requestText)
            os_log(.default, "[Eison-App] llm.ping done (elapsed=%.3fs, outLen=%d)", Date().timeIntervalSince(start), response.count)
            pushLLMPingResultToWebView(.init(state: "done", requestText: requestText, responseText: response, error: nil))
        } catch {
            os_log(.error, "[Eison-App] llm.ping failed: %@", String(describing: error))
            pushLLMPingResultToWebView(.init(state: "error", requestText: requestText, responseText: nil, error: error.localizedDescription))
        }
    }
}

private actor LLMPingRunner {
    static let shared = LLMPingRunner()
    @available(iOS 18.0, macOS 15.0, *)
    private var model: AnyLanguageModel.CoreMLLanguageModel?

    func respond(to input: String) async throws -> String {
        guard #available(iOS 18.0, macOS 15.0, *) else {
            throw NSError(domain: "EisonAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "CoreML model requires iOS 18 / macOS 15"])
        }

        let model = try await getModel()
        let session = AnyLanguageModel.LanguageModelSession(model: model, instructions: "你是一個簡潔的助手。請直接回覆，盡量短。")
        let options = AnyLanguageModel.GenerationOptions(temperature: 0.2, maximumResponseTokens: 64)
        let response: AnyLanguageModel.LanguageModelSession.Response<String> = try await session.respond(
            to: AnyLanguageModel.Prompt(input),
            options: options
        )
        return response.content
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func getModel() async throws -> AnyLanguageModel.CoreMLLanguageModel {
        if let model {
            return model
        }

        let repoId = "XDGCC/coreml-Qwen3-0.6B"
        let revision = "fc6bdeb0b02573744ee2cba7e3f408f2851adf57"
        let appGroupID = "group.com.qoli.eisonAI"

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }

        let modelRoot = container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        let compiledURL = modelRoot.appendingPathComponent("Qwen3-0.6B.mlmodelc", isDirectory: true)
        let loaded = try await AnyLanguageModel.CoreMLLanguageModel(url: compiledURL, computeUnits: .all)
        self.model = loaded
        return loaded
    }
}
#endif
