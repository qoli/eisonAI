import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("General")) {
                Toggle("Enable Notifications", isOn: .constant(true))
                Toggle("Use Cellular Data", isOn: .constant(false))
            }

            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://example.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
