import SwiftUI

struct SettingsView: View {
    private let foundationModelsStore = FoundationModelsSettingsStore()
    private let sharePollingStore = SharePollingSettingsStore()
    private let rawLibraryStore = RawLibraryStore()
    private let tokenEstimatorSettingsStore = TokenEstimatorSettingsStore.shared
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let tokenEstimatorOptions: [Encoding] = [.cl100k, .o200k, .p50k, .r50k]
    private let longDocumentChunkSizeOptions: [Int] = [2200, 2600, 3000, 3200]
    private let longDocumentMaxChunkOptions: [Int] = [4, 5, 6, 7]

    @State private var cloudSyncStatus = ""
    @State private var isCloudSyncing = false
    @State private var didLoad = false
    @State private var foundationModelsAppEnabled = false
    @State private var foundationModelsExtensionEnabled = false
    @State private var sharePollingEnabled = false
    @State private var rawLibraryItemCount: Int = 0
    @State private var rawLibraryStatus: String = ""
    @State private var rawLibraryCleanupStatus: String = ""
    @State private var tokenEstimatorEncoding: Encoding = .cl100k
    @State private var longDocumentChunkTokenSize: Int = 2600
    @State private var longDocumentMaxChunkCount: Int = 5

    var fmStatus: FoundationModelsAvailability.Status {
        FoundationModelsAvailability.currentStatus()
    }

    var body: some View {
        Form {
            Section("About") {
                NavigationLink("About") {
                    AboutView()
                }
            }

            Section("Foundation Models (Apple Intelligence)") {
                Toggle(
                    "Use Foundation Models (App)",
                    isOn: Binding(
                        get: { foundationModelsAppEnabled },
                        set: { newValue in
                            guard fmStatus == .available else { return }
                            foundationModelsAppEnabled = newValue
                            foundationModelsStore.setAppEnabled(newValue)
                        }
                    )
                )
                .disabled(fmStatus != .available)

                Toggle(
                    "Use Foundation Models (Safari Extension)",
                    isOn: Binding(
                        get: { foundationModelsExtensionEnabled },
                        set: { newValue in
                            guard fmStatus == .available else { return }
                            foundationModelsExtensionEnabled = newValue
                            foundationModelsStore.setExtensionEnabled(newValue)
                        }
                    )
                )
                .disabled(fmStatus != .available)

                switch fmStatus {
                case .available:
                    Text("Available.")
                        .foregroundStyle(.secondary)
                case .notSupported:
                    Text("Requires iOS 26+ with Apple Intelligence enabled.")
                        .foregroundStyle(.secondary)
                case let .unavailable(reason):
                    Text(reason)
                        .foregroundStyle(.secondary)
                }

                Text("When unavailable, the app/extension automatically falls back to the bundled WebLLM/MLC paths.")
                    .foregroundStyle(.secondary)
            }

            Section("Advanced Settings") {
                Picker(
                    "Token Estimation Method",
                    selection: Binding(
                        get: { tokenEstimatorEncoding },
                        set: { newValue in
                            tokenEstimatorEncoding = newValue
                            tokenEstimatorSettingsStore.setSelectedEncoding(newValue)
                        }
                    )
                ) {
                    ForEach(tokenEstimatorOptions, id: \.self) { encoding in
                        Text(encoding.rawValue).tag(encoding)
                    }
                }

                Text("This setting syncs token estimation for both the app and Safari extension.")
                    .foregroundStyle(.secondary)

                Picker(
                    "Long Document Chunk Size",
                    selection: Binding(
                        get: { longDocumentChunkTokenSize },
                        set: { newValue in
                            longDocumentChunkTokenSize = newValue
                            longDocumentSettingsStore.setChunkTokenSize(newValue)
                        }
                    )
                ) {
                    ForEach(longDocumentChunkSizeOptions, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }

                Text("Chunk size is fixed to these options; chunks beyond the max count are discarded.")
                    .foregroundStyle(.secondary)

                Picker(
                    "Max Chunk Count",
                    selection: Binding(
                        get: { longDocumentMaxChunkCount },
                        set: { newValue in
                            longDocumentMaxChunkCount = newValue
                            longDocumentSettingsStore.setMaxChunkCount(newValue)
                        }
                    )
                ) {
                    ForEach(longDocumentMaxChunkOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Text("Chunks beyond the limit are discarded.")
                    .foregroundStyle(.secondary)
            }

            Section("Safari Extension") {
                Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                    .foregroundStyle(.secondary)
            }

            Section("Share Extension") {
                Toggle(
                    "Enable Share polling (foreground only)",
                    isOn: Binding(
                        get: { sharePollingEnabled },
                        set: { newValue in
                            sharePollingEnabled = newValue
                            sharePollingStore.setEnabled(newValue)
                        }
                    )
                )

                Text("When enabled, the app checks for shared payloads on foreground and polls every 2 seconds while active.")
                    .foregroundStyle(.secondary)
            }

            Section("RawLibrary") {
                HStack {
                    Text("History Inbox Limit")
                    Spacer()
                    Text("\(AppConfig.rawLibraryMaxItems) items")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Currently Used")
                    Spacer()
                    Text("\(rawLibraryItemCount) items")
                        .foregroundStyle(.secondary)
                }

                Text("When over the limit, the oldest records are removed automatically.")
                    .foregroundStyle(.secondary)

                Button("Clean Invalid Tags") {
                    do {
                        rawLibraryCleanupStatus = ""
                        let result = try rawLibraryStore.cleanUnusedTags()
                        rawLibraryCleanupStatus = "Removed \(result.removed) invalid tag(s) (\(result.kept) remaining)."
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

            Section("CloudKit Sync") {
                Button(isCloudSyncing ? "Syncing..." : "Overwrite CloudKit with Local Data") {
                    isCloudSyncing = true
                    cloudSyncStatus = ""
                    Task {
                        do {
                            try await RawLibrarySyncService.shared.overwriteRemoteWithLocal()
                            cloudSyncStatus = "Completed."
                        } catch {
                            cloudSyncStatus = "Failed: \(error.localizedDescription)"
                        }
                        isCloudSyncing = false
                    }
                }
                .disabled(isCloudSyncing)

                Text("This deletes all remote RawLibrary records and re-uploads local files.")
                    .foregroundStyle(.secondary)

                if !cloudSyncStatus.isEmpty {
                    Text(cloudSyncStatus)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .navigationTitle("Settings")
        .onAppear {
            if !didLoad {
                didLoad = true
                foundationModelsAppEnabled = foundationModelsStore.isAppEnabled()
                foundationModelsExtensionEnabled = foundationModelsStore.isExtensionEnabled()
                sharePollingEnabled = sharePollingStore.isEnabled()
                tokenEstimatorEncoding = tokenEstimatorSettingsStore.selectedEncoding()
                longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
                longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()

                if FoundationModelsAvailability.currentStatus() != .available {
                    foundationModelsAppEnabled = false
                    foundationModelsExtensionEnabled = false
                    foundationModelsStore.setAppEnabled(false)
                    foundationModelsStore.setExtensionEnabled(false)
                }
            }

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
        SettingsView()
    }
}
