import SwiftUI

struct DataSyncSettingsView: View {
    private let rawLibraryStore = RawLibraryStore()

    @State private var cloudSyncStatus = ""
    @State private var isCloudSyncing = false
    @State private var rawLibraryItemCount: Int = 0
    @State private var rawLibraryStatus: String = ""
    @State private var rawLibraryCleanupStatus: String = ""

    var body: some View {
        Form {
            Section("History") {
                HStack {
                    Text("History inbox limit")
                    Spacer()
                    Text("\(AppConfig.rawLibraryMaxItems) items")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Currently used")
                    Spacer()
                    Text("\(rawLibraryItemCount) items")
                        .foregroundStyle(.secondary)
                }

                Text("Oldest items are removed automatically when the limit is exceeded.")
                    .foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                Button("Remove unused tags") {
                    do {
                        rawLibraryCleanupStatus = ""
                        let result = try rawLibraryStore.cleanUnusedTags()
                        rawLibraryCleanupStatus = "Removed \(result.removed) unused tag(s) (\(result.kept) remaining)."
                    } catch {
                        rawLibraryCleanupStatus = "Cleanup failed: \(error.localizedDescription)"
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
            }

            Section("CloudKit") {
                Button(isCloudSyncing ? "Syncing..." : "Replace CloudKit data with local data") {
                    isCloudSyncing = true
                    cloudSyncStatus = ""
                    Task {
                        do {
                            try await RawLibrarySyncService.shared.overwriteRemoteWithLocal()
                            cloudSyncStatus = "Sync complete."
                        } catch {
                            cloudSyncStatus = "Failed: \(error.localizedDescription)"
                        }
                        isCloudSyncing = false
                    }
                }
                .disabled(isCloudSyncing)

                Text("This deletes all CloudKit records and re-uploads your local data.")
                    .foregroundStyle(.secondary)

                if !cloudSyncStatus.isEmpty {
                    Text(cloudSyncStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Data & Sync")
        .onAppear {
            do {
                rawLibraryStatus = ""
                rawLibraryItemCount = try rawLibraryStore.countItems()
            } catch {
                rawLibraryStatus = "Failed to load RawLibrary: \(error.localizedDescription)"
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
