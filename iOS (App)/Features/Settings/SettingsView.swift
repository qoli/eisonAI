import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    Label("General", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Basics")
            } footer: {
                Text("Set up extensions and background behaviors.")
            }

            Section {
                NavigationLink {
                    AIModelsSettingsView()
                } label: {
                    Label("AI Models", systemImage: "cpu")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Control model choices and long‑document chunking.")
            }

            Section {
                NavigationLink {
                    LabsSettingsView()
                } label: {
                    Label("Labs", systemImage: "flask")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Labs")
            } footer: {
                Text("Experimental features and model flags.")
            }

            Section {
                NavigationLink {
                    DataSyncSettingsView()
                } label: {
                    Label("Data & Sync", systemImage: "icloud.and.arrow.up")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Data & Sync")
            } footer: {
                Text("Manage history storage and CloudKit syncing.")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "questionmark.circle")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("About")
            } footer: {
                //
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
