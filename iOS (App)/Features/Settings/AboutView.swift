import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        Form {
            Section("App") {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links") {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            }

            Section("Legal") {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Terms_of_Service.md")!) {
                    Text("Terms of Service")
                }
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Privacy_Policy.md")!) {
                    Text("Privacy Policy")
                }
            }

            #if DEBUG
                Section("Debug") {
                    NavigationLink("Debug") {
                        DebugSettingsView()
                    }
                }
            #endif
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
