import SwiftUI

struct SettingsView: View {
    private let foundationModelsStore = FoundationModelsSettingsStore()
    private let sharePollingStore = SharePollingSettingsStore()
    private let rawLibraryStore = RawLibraryStore()
    private let tokenEstimatorSettingsStore = TokenEstimatorSettingsStore.shared
    private let tokenEstimatorOptions: [Encoding] = [.cl100k, .o200k, .p50k, .r50k]

    @State private var debugStatus = ""
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

    var body: some View {
        let fmStatus = FoundationModelsAvailability.currentStatus()

        Form {
            #if DEBUG
                Section("Demos") {
                    NavigationLink("Qwen3 0.6B (MLC Swift)") {
                        MLCQwenDemoView()
                    }
                    Text("A single-turn, streaming chat demo using the native MLC Swift SDK.")
                        .foregroundStyle(.secondary)

                    NavigationLink("Clipboard 2600-Token Splitter") {
                        ClipboardTokenChunkingView()
                    }
                    Text("Paste from clipboard and split long text into 2600-token chunks (using the selected tokenizer).")
                        .foregroundStyle(.secondary)
                }
            #endif

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

            Section("Prompts") {
                NavigationLink("Prompt Settings") {
                    PromptSettingsView()
                }
                Text("Manage summary, chunk, and title prompts in one place.")
                    .foregroundStyle(.secondary)
            }

            Section("高階設定") {
                Picker(
                    "Token 計算方式",
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

                Text("此設定會同步影響 App 與 Safari Extension 的 token 計算。")
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
                    Text("歷史紀錄收件箱上限")
                    Spacer()
                    Text("\(AppConfig.rawLibraryMaxItems) 筆")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("目前已使用")
                    Spacer()
                    Text("\(rawLibraryItemCount) 筆")
                        .foregroundStyle(.secondary)
                }

                Text("超過上限時會自動移除最舊的記錄。")
                    .foregroundStyle(.secondary)

                Button("清理無效 Tag") {
                    do {
                        rawLibraryCleanupStatus = ""
                        let result = try rawLibraryStore.cleanUnusedTags()
                        rawLibraryCleanupStatus = "已清理 \(result.removed) 個無效 Tag（剩餘 \(result.kept)）"
                    } catch {
                        rawLibraryCleanupStatus = "清理失敗：\(error.localizedDescription)"
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

            #if DEBUG
                Section("Share Payload (Debug)") {
                    Button("Clear pending share payloads") {
                        do {
                            let count = try SharePayloadStore().clearAllPending()
                            debugStatus = "Cleared \(count) payload(s)."
                        } catch {
                            debugStatus = "Clear failed: \(error.localizedDescription)"
                        }
                    }

                    if !debugStatus.isEmpty {
                        Text(debugStatus)
                            .foregroundStyle(.secondary)
                    }
                }
            #endif
        }
        .navigationTitle("Settings")
        .onAppear {
            if !didLoad {
                didLoad = true
                foundationModelsAppEnabled = foundationModelsStore.isAppEnabled()
                foundationModelsExtensionEnabled = foundationModelsStore.isExtensionEnabled()
                sharePollingEnabled = sharePollingStore.isEnabled()
                tokenEstimatorEncoding = tokenEstimatorSettingsStore.selectedEncoding()

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
                rawLibraryStatus = "讀取 RawLibrary 失敗：\(error.localizedDescription)"
                rawLibraryItemCount = 0
            }
        }
    }
}
