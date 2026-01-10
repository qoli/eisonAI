import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
import Darwin

struct AboutView: View {
    @State private var showOnboarding = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(buildNumber))"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private func sysctlString(_ name: String) -> String {
        var size: size_t = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var value = [CChar](repeating: 0, count: Int(size))
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: value)
    }

    private var deviceDescription: String {
        #if canImport(UIKit)
            let device = UIDevice.current
            return "\(device.model) (\(device.name))"
        #else
            return "Unknown"
        #endif
    }

    private var deviceModelIdentifier: String {
        sysctlString("hw.machine")
    }

    private var hardwareModel: String {
        sysctlString("hw.model")
    }

    private var architectureDescription: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }

    private var deviceIdiomDescription: String {
        #if canImport(UIKit)
            switch UIDevice.current.userInterfaceIdiom {
            case .phone: return "iPhone"
            case .pad: return "iPad"
            case .tv: return "Apple TV"
            case .carPlay: return "CarPlay"
            case .mac: return "Mac"
            case .vision: return "Vision"
            default: return "Unspecified"
            }
        #else
            return "Unknown"
        #endif
    }

    private var lowPowerModeDescription: String {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off"
    }

    private var thermalStateDescription: String {
        if #available(iOS 11.0, macOS 10.10.3, *) {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return "Nominal"
            case .fair: return "Fair"
            case .serious: return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }
        return "Unavailable"
    }

    private var osDescription: String {
        #if canImport(UIKit)
            let device = UIDevice.current
            let full = ProcessInfo.processInfo.operatingSystemVersionString
            let simple = "\(device.systemName) \(device.systemVersion)"
            return full.contains(device.systemVersion) ? simple : "\(simple) (\(full))"
        #else
            return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private var ramDescription: String {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private var feedbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "llqoli@gmail.com"
        let body = """
        Please describe the issue:


        ---
        App Version: \(appVersion)
        Bundle ID: \(bundleIdentifier)
        Device: \(deviceDescription)
        Device Idiom: \(deviceIdiomDescription)
        Model Identifier: \(deviceModelIdentifier)
        Hardware Model: \(hardwareModel)
        Architecture: \(architectureDescription)
        OS Version: \(osDescription)
        RAM: \(ramDescription)
        CPU Cores: \(ProcessInfo.processInfo.processorCount) (active: \(ProcessInfo.processInfo.activeProcessorCount))
        Low Power Mode: \(lowPowerModeDescription)
        Thermal State: \(thermalStateDescription)
        """
        components.queryItems = [
            URLQueryItem(name: "subject", value: "EisonAI Feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()

                    VStack {
                        Image("ImageLogo")
                        Image("TextLogo")

                        Color.clear.frame(height: 6)

                        Text("Version \(appVersion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 28)
            }

            Section {
                HighlightsListView()

            } header: {
                Text("Highlights")
            } footer: {
                Text("Built to keep reading fast, clear, and reliable.")
            }

            Section {
                NavigationLink("View onboarding again") {
                    OnboardingView(defaultPage: 0, dismissOnCompletion: true)
                }
            } header: {
                Text("Experience")
            } footer: {
                Text("Revisit the full onboarding walkthrough anytime.")
            }

            Section {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            } header: {
                Text("Links")
            }

            Section {
                if let url = feedbackURL {
                    Link(destination: url) {
                        Label("Report an issue", systemImage: "envelope")
                    }
                } else {
                    Text("Feedback email is unavailable.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text("The email template includes your app version to help us troubleshoot faster.")
            }

            Section {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Terms_of_Service.md")!) {
                    Text("Terms of Service")
                }
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Privacy_Policy.md")!) {
                    Text("Privacy Policy")
                }
            } header: {
                Text("Legal")
            }

            #if DEBUG
                Section {
                    NavigationLink("Debug") {
                        DebugSettingsView()
                    }
                } header: {
                    Text("Debug")
                }
            #endif
        }
        .navigationTitle("About")
    }
}

private struct HighlightsListView: View {
    var body: some View {
        highlightRow(
            symbol: "viewfinder.circle",
            title: "Cognitive Index",
            subtitle: "Make structure visible."
        )
        highlightRow(
            symbol: "doc.text.magnifyingglass",
            title: "Long-Document",
            subtitle: "Chunked reading keeps long texts stable."
        )
        highlightRow(
            symbol: "puzzlepiece.extension",
            title: "Safari Extension",
            subtitle: "Summaries, right inside Safari."
        )
        highlightRow(
            symbol: "lock.square",
            title: "Local-First",
            subtitle: "On-device by default."
        )
        highlightRow(
            symbol: "checkmark.seal",
            title: "Source Trust",
            subtitle: "Verify sources, not slogans."
        )
        highlightRow(
            symbol: "book.pages",
            title: "Library & Tags",
            subtitle: "Organize what matters."
        )
    }

    @ViewBuilder
    private func highlightRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack {
            ZStack {
                Image(systemName: symbol)
                    .offset(x: -4)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
