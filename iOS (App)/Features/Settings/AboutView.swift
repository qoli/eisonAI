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
