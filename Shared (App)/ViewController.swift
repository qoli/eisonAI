//
//  ViewController.swift
//  Shared (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import WebKit

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
}
#endif
