import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    Label("General", systemImage: "gearshape")
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
                    Label("AI Models", systemImage: "sparkles")
                        .foregroundStyle(.primary)
                }
                NavigationLink {
                    DocumentsSettingsView()
                } label: {
                    Label("Documents", systemImage: "doc.text")
                        .foregroundStyle(.primary)
                }
            } header: {
                Text("Models & Documents")
            } footer: {
                Text("Control model choices and long‑document chunking.")
            }

            Section {
                NavigationLink {
                    DataSyncSettingsView()
                } label: {
                    Label("Data & Sync", systemImage: "arrow.triangle.2.circlepath")
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
                    Label("About", systemImage: "info.circle")
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
