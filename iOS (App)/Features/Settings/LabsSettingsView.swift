import SwiftUI

struct LabsSettingsView: View {
    var body: some View {
        Form {
            Section {
                InstalledMemoryView()
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)
            } header: {
                Text("Device")
            } footer: {
                Text("Local model configuration has moved into AI Models.")
            }

            Section {
                Text("MLC-LLM and WebLLM have been removed. Use AI Models to configure Apple Intelligence, BYOK, and downloaded MLX repos.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Labs")
    }
}

#Preview {
    NavigationStack {
        LabsSettingsView()
    }
}
