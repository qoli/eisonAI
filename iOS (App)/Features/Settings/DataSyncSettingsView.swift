import SwiftUI

struct DataSyncSettingsView: View {
    private let rawLibraryStore = RawLibraryStore()

    @State private var cloudSyncStatus = ""
    @State private var isCloudSyncing = false
    @State private var rawLibraryItemCount: Int = 0
    @State private var rawLibraryStatus: String = ""
    @State private var rawLibraryCleanupStatus: String = ""
    @State private var showCloudOverwriteAlert = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("History storage limit")
                    Spacer()
                    Text("\(AppConfig.rawLibraryMaxItems) items")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("In use")
                    Spacer()
                    Text("\(rawLibraryItemCount) items")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("History")
            } footer: {
                Text("When the limit is reached, the oldest items are removed automatically.")
            }

            Section {
                Button("Clean unused tags") {
                    do {
                        rawLibraryCleanupStatus = ""
                        let result = try rawLibraryStore.cleanUnusedTags()
                        rawLibraryCleanupStatus = "Removed \(result.removed) unused tags. \(result.kept) remaining."
                    } catch {
                        rawLibraryCleanupStatus = "Cleanup failed. \(error.localizedDescription)"
                    }
                }

                if !rawLibraryCleanupStatus.isEmpty {
                    Text(rawLibraryCleanupStatus)
                        .foregroundStyle(.secondary)
                }

                if !rawLibraryStatus.isEmpty {
                    Text(rawLibraryStatus)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Maintenance")
            }

            Section {
                Button(isCloudSyncing ? "Syncing..." : "Overwrite CloudKit with local data") {
                    showCloudOverwriteAlert = true
                }
                .disabled(isCloudSyncing)

                if !cloudSyncStatus.isEmpty {
                    Text(cloudSyncStatus)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("CloudKit")
            } footer: {
                Text("This deletes all CloudKit records and uploads your local data again.")
            }
        }
        .navigationTitle("Data & Sync")
        .alert("Overwrite CloudKit data?", isPresented: $showCloudOverwriteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Overwrite", role: .destructive) {
                isCloudSyncing = true
                cloudSyncStatus = ""
                Task {
                    do {
                        try await RawLibrarySyncService.shared.overwriteRemoteWithLocal()
                        cloudSyncStatus = "Sync completed."
                    } catch {
                        cloudSyncStatus = "Sync failed. \(error.localizedDescription)"
                    }
                    isCloudSyncing = false
                }
            }
        } message: {
            Text("This will delete all CloudKit records and re-upload your local data.")
        }
        .onAppear {
            do {
                rawLibraryStatus = ""
                rawLibraryItemCount = try rawLibraryStore.countItems()
            } catch {
                rawLibraryStatus = "Failed to load history: \(error.localizedDescription)"
                rawLibraryItemCount = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        DataSyncSettingsView()
    }
}
