import Foundation
import OSLog
import SwiftUI

struct AIModelsSettingsView: View {
    private static let logger = Logger(subsystem: "com.qoli.eisonAI", category: "AIModelsSettingsView")
    private let appBackendStore = GenerationBackendSettingsStore()
    private let extensionBackendStore = ExtensionGenerationBackendSettingsStore()
    private let byokStore = BYOKSettingsStore()
    private let autoStrategyStore = AutoStrategySettingsStore.shared
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let catalogService = MLXModelCatalogService()
    private let modelStore = MLXModelStore()
    private let client = AnyLanguageModelClient()
    @ObservedObject private var downloadCoordinator = MLXDownloadCoordinator.shared
    private let debugAutomationRequest: MLXDebugAutomationRequest?
    private let startInMLXManagement: Bool
    private let longDocumentChunkSizeOptions: [Int] = LongDocumentDefaults.allowedChunkSizes
    private let longDocumentMaxChunkOptions: [Int] = LongDocumentDefaults.allowedMaxChunkCounts
    private static let modelPickerPlaceholderTag = "__byok_model_placeholder__"
    private static let modelPickerCustomTag = "__byok_model_custom__"
    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    @State private var didLoad = false
    @State private var appBackend: GenerationBackend = .local
    @State private var extensionBackend: ExtensionGenerationBackendSelection = .auto
    @State private var autoLocalPreference: AutoStrategySettingsStore.LocalModelPreference = .appleIntelligence
    @State private var longDocumentChunkTokenSize = LongDocumentDefaults.fallbackChunkSize
    @State private var longDocumentMaxChunkCount = LongDocumentDefaults.fallbackMaxChunkCount

    @State private var installedModels: [InstalledMLXModel] = []
    @State private var selectedMLXModelID: String?
    @State private var catalogModels: [MLXCatalogModel] = []
    @State private var isRefreshingCatalog = false
    @State private var catalogError = ""
    @State private var showAllCatalogModels = false
    @State private var showCustomRepoSection = false
    @State private var modelOperationMessage = ""
    @State private var modelOperationIsError = false
    @State private var activeModelOperationIDs = Set<String>()
    @State private var customRepoDraft = ""
    @State private var didRunDebugAutomation = false

    @State private var byokProvider: BYOKProvider = .openAIChat
    @State private var byokProviderOptionID = ""
    @State private var lastConfirmedProviderOptionID = ""
    @State private var pendingProviderOptionID: String?
    @State private var showOverwriteAPIAlert = false
    @State private var suppressProviderOptionChange = false
    @State private var byokApiURL = ""
    @State private var byokApiKey = ""
    @State private var byokModel = ""
    @State private var byokFooterMessage = ""
    @State private var byokFooterIsError = false
    @State private var byokConnectionStatus: BYOKConnectionStatus = .idle
    @State private var byokConnectionError = ""
    @State private var byokConnectionMessage = ""
    @State private var byokConnectionTask: Task<Void, Never>?
    @State private var byokAvailableModels: [String] = []
    @State private var showCustomModelPrompt = false
    @State private var customModelDraft = ""
    @State private var byokPingStatus: BYOKPingStatus = .idle
    @State private var byokPingResponse = ""
    @State private var byokPingError = ""
    @State private var byokPingTask: Task<Void, Never>?

    init(
        debugAutomationRequest: MLXDebugAutomationRequest? = nil,
        startInMLXManagement: Bool = false
    ) {
        self.debugAutomationRequest = debugAutomationRequest
        self.startInMLXManagement = startInMLXManagement
        self._downloadCoordinator = ObservedObject(wrappedValue: MLXDownloadCoordinator.shared)
    }

    private var aiStatus: AppleIntelligenceAvailability.Status {
        AppleIntelligenceAvailability.currentStatus()
    }

    private var localAvailability: LocalModelAvailability {
        appBackendStore.localModelAvailability()
    }

    private var selectedProviderOption: BYOKProvider.ProviderOption? {
        BYOKProvider.httpOptions.first { $0.id == byokProviderOptionID }
    }

    private var pendingProviderOption: BYOKProvider.ProviderOption? {
        guard let pendingProviderOptionID else { return nil }
        return BYOKProvider.httpOptions.first { $0.id == pendingProviderOptionID }
    }

    private var selectedProviderDocsURL: URL? {
        selectedProviderOption?.preset?.docsURL
    }

    private var byokModelPickerOptions: [ModelPickerOption] {
        var options: [ModelPickerOption] = []
        let trimmedModel = byokModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()

        if trimmedModel.isEmpty {
            options.append(ModelPickerOption(
                value: Self.modelPickerPlaceholderTag,
                label: "Select a model"
            ))
        }

        let sortedModels = byokAvailableModels.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        for model in sortedModels {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            options.append(ModelPickerOption(value: trimmed, label: trimmed))
        }

        if !trimmedModel.isEmpty, seen.insert(trimmedModel).inserted {
            options.append(ModelPickerOption(
                value: trimmedModel,
                label: "Custom: \(trimmedModel)"
            ))
        }

        options.append(ModelPickerOption(
            value: Self.modelPickerCustomTag,
            label: "Enter Model ID"
        ))
        return options
    }

    var body: some View {
        displayedPage
            .navigationTitle("AI Models")
            .alert("Replace API URL?", isPresented: $showOverwriteAPIAlert) {
            Button("Replace", role: .destructive) {
                guard let option = pendingProviderOption else { return }
                applyProviderOption(option)
                pendingProviderOptionID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingProviderOptionID = nil
            }
        } message: {
            if let presetURL = pendingProviderOption?.preset?.apiURL {
                Text("This will replace the current API URL with:\n\(presetURL)")
            } else {
                Text("This will replace the current API URL.")
            }
        }
        .alert("Enter Model ID", isPresented: $showCustomModelPrompt) {
            TextField("Model ID", text: $customModelDraft)
            Button("Save") {
                let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    byokModel = trimmed
                }
                customModelDraft = ""
            }
            Button("Cancel", role: .cancel) {
                customModelDraft = ""
            }
        } message: {
            Text("Use a custom model ID that isn't in the list.")
        }
        .task {
            loadStateIfNeeded()
        }
        .onChange(of: appBackend) { _, newValue in
            guard didLoad else { return }
            appBackendStore.saveSelectedBackend(newValue)
            scheduleByokConnectionTest()
        }
        .onChange(of: extensionBackend) { _, newValue in
            guard didLoad else { return }
            extensionBackendStore.saveSelectedBackend(newValue)
        }
        .onChange(of: autoLocalPreference) { _, newValue in
            guard didLoad else { return }
            autoStrategyStore.setLocalModelPreference(newValue)
        }
        .onChange(of: longDocumentChunkTokenSize) { _, newValue in
            guard didLoad else { return }
            longDocumentSettingsStore.setChunkTokenSize(newValue)
        }
        .onChange(of: longDocumentMaxChunkCount) { _, newValue in
            guard didLoad else { return }
            longDocumentSettingsStore.setMaxChunkCount(newValue)
        }
        .onChange(of: byokProviderOptionID) { _, newValue in
            guard didLoad else { return }
            guard !suppressProviderOptionChange else { return }
            guard newValue != lastConfirmedProviderOptionID else { return }
            guard let option = BYOKProvider.httpOptions.first(where: { $0.id == newValue }) else {
                return
            }
            let trimmedURL = byokApiURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let presetURL = option.preset?.apiURL,
               !trimmedURL.isEmpty,
               trimmedURL != presetURL {
                pendingProviderOptionID = newValue
                showOverwriteAPIAlert = true
                suppressProviderOptionChange = true
                byokProviderOptionID = lastConfirmedProviderOptionID
                suppressProviderOptionChange = false
                return
            }
            applyProviderOption(option)
        }
        .onChange(of: byokProvider) { _, _ in
            if didLoad {
                validateBYOK()
                resetByokPing()
                scheduleByokConnectionTest()
            }
        }
        .onChange(of: byokApiURL) { _, _ in
            if didLoad {
                validateBYOK()
                resetByokPing()
                scheduleByokConnectionTest()
            }
        }
        .onChange(of: byokApiKey) { _, _ in
            if didLoad {
                validateBYOK()
                resetByokPing()
                scheduleByokConnectionTest()
            }
        }
        .onChange(of: byokModel) { _, _ in
            if didLoad {
                validateBYOK()
                resetByokPing()
                scheduleByokConnectionTest()
            }
            }
    }

    @ViewBuilder
    private var displayedPage: some View {
        if startInMLXManagement {
            mlxManagementPage
        } else {
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                Picker("App Backend", selection: $appBackend) {
                    ForEach(GenerationBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                Picker("Extension Backend", selection: $extensionBackend) {
                    ForEach(ExtensionGenerationBackendSelection.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
            } header: {
                Text("Execution")
            } footer: {
                Text(backendFooterText)
                    .foregroundStyle(.secondary)
            }

            Section {
                InstalledMemoryView()
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)

                Picker("Preferred Local Model", selection: $autoLocalPreference) {
                    ForEach(AutoStrategySettingsStore.LocalModelPreference.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            } header: {
                Text("Local Routing")
            } footer: {
                Text("The app can use Apple Intelligence or a selected MLX repo. Auto still switches to BYOK for long inputs.")
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    mlxManagementPage
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MLX Models")
                        Text(mlxManagementSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Model Library")
            } footer: {
                Text("Manage installed MLX repos, browse the `mlx-community` catalog, or install a custom Hugging Face MLX repo.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Provider", selection: $byokProviderOptionID) {
                    ForEach(BYOKProvider.httpOptions) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }

                TextField("API Base URL", text: $byokApiURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("API Key (optional)", text: $byokApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker(
                    "Model",
                    selection: Binding(
                        get: {
                            let trimmed = byokModel.trimmingCharacters(in: .whitespacesAndNewlines)
                            return trimmed.isEmpty ? Self.modelPickerPlaceholderTag : trimmed
                        },
                        set: { newValue in
                            switch newValue {
                            case Self.modelPickerCustomTag:
                                customModelDraft = byokModel
                                showCustomModelPrompt = true
                            case Self.modelPickerPlaceholderTag:
                                break
                            default:
                                byokModel = newValue
                            }
                        }
                    )
                ) {
                    ForEach(byokModelPickerOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            } header: {
                Text("BYOK")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let docsURL = selectedProviderDocsURL {
                        Link("Documentation", destination: docsURL)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(byokFooterIsError ? byokFooterMessage : "Saved after Verify & Save.")
                        .foregroundStyle(byokFooterIsError ? .red : .secondary)
                }
            }

            Section {
                HStack {
                    Text("Connection")
                    Spacer()
                    Circle()
                        .fill(byokConnectionStatus.color)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(byokConnectionStatus.accessibilityLabel)
                }

                Button {
                    runByokPingAndSave()
                } label: {
                    HStack(spacing: 12) {
                        Text("Verify & Save")
                        if byokPingStatus == .testing {
                            ProgressView()
                        }
                    }
                }
                .disabled(byokPingStatus == .testing)
            } header: {
                Text("BYOK Verification")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model list first; otherwise ping.")
                        .foregroundStyle(.secondary)
                    if !byokConnectionMessage.isEmpty {
                        Text("Connection: \(byokConnectionMessage)")
                            .foregroundStyle(.secondary)
                    }
                    if byokConnectionStatus == .failed, !byokConnectionError.isEmpty {
                        Text("Connection error: \(byokConnectionError)")
                            .foregroundStyle(.red)
                    }
                    Text("Verify status: \(byokPingStatus.label)")
                        .foregroundStyle(.secondary)
                    if !byokPingResponse.isEmpty {
                        Text("Response: \(byokPingResponse)")
                            .foregroundStyle(.secondary)
                    }
                    if !byokPingError.isEmpty {
                        Text("Error: \(byokPingError)")
                            .foregroundStyle(.red)
                    }
                }
            }

            if appBackend != .byok {
                Section {
                    Picker("Chunk Size", selection: $longDocumentChunkTokenSize) {
                        ForEach(longDocumentChunkSizeOptions, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }

                    Picker("Max Chunks", selection: $longDocumentMaxChunkCount) {
                        ForEach(longDocumentMaxChunkOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                } header: {
                    Text("Long Document")
                } footer: {
                    Text("Chunking only runs on the app's local path. BYOK still handles overflow when routing decides to use the cloud.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var backendFooterText: String {
        var lines: [String] = []
        switch aiStatus {
        case .available:
            lines.append("Apple Intelligence: available.")
        case .notSupported:
            lines.append("Apple Intelligence: requires iOS 26+ and enabled.")
        case let .unavailable(reason):
            lines.append("Apple Intelligence: \(reason)")
        }

        if let selectedMLXModelID {
            lines.append("Selected MLX: \(selectedMLXModelID)")
        } else {
            lines.append("Selected MLX: none.")
        }

        lines.append("Extension local execution has been removed. Safari uses Apple Intelligence or BYOK.")
        return lines.joined(separator: "\n")
    }

    private var mlxManagementSummary: String {
        var parts: [String] = []
        parts.append("\(installedModels.count) installed")
        if let selectedMLXModelID {
            parts.append("Selected: \(selectedMLXModelID)")
        } else {
            parts.append("No selected repo")
        }
        if isRefreshingCatalog {
            parts.append("Refreshing catalog")
        } else if !catalogModels.isEmpty {
            parts.append("\(catalogModels.count) catalog items cached")
        }
        return parts.joined(separator: " · ")
    }

    private var deviceRAMGiB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    }

    private var filteredCatalogModels: [MLXCatalogModel] {
        guard !showAllCatalogModels else { return catalogModels }
        return catalogModels.filter { model in
            model.recommendation(forRAMGiB: deviceRAMGiB) != .likelyTooLarge
        }
    }

    private var hiddenCatalogModelCount: Int {
        max(catalogModels.count - filteredCatalogModels.count, 0)
    }

    private var currentDownloadJob: MLXDownloadJob? {
        downloadCoordinator.currentJob
    }

    private var activeDownloadJob: MLXDownloadJob? {
        guard let currentDownloadJob, currentDownloadJob.isActive else { return nil }
        return currentDownloadJob
    }

    private var mlxCommunityFooterText: String {
        var parts: [String] = [
            "Catalog items come from `mlx-community` and include `text-generation`, `image-text-to-text`, and `any-to-any`."
        ]

        if hiddenCatalogModelCount > 0 {
            parts.append(
                showAllCatalogModels
                    ? "Showing all models, including \(hiddenCatalogModelCount) likely too large for this device."
                    : "\(hiddenCatalogModelCount) likely too large models are hidden. Use the toolbar to reveal them."
            )
        }

        return parts.joined(separator: " ")
    }

    private var mlxManagementPage: some View {
        Form {
            if showCustomRepoSection {
                Section {
                    HStack {
                        TextField("huggingface repo, e.g. mlx-community/Qwen3-1.7B-4bit", text: $customRepoDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("Install") {
                            installCustomRepo()
                        }
                        .disabled(
                            customRepoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                activeDownloadJob != nil
                        )
                    }

                    if let customDownloadJob,
                       customDownloadJob.source == .custom
                    {
                        MLXDownloadJobStatusView(
                            job: customDownloadJob,
                            onCancel: cancelCurrentDownloadJob,
                            onDismiss: dismissCurrentDownloadJob
                        )
                    }
                } header: {
                    Text("Custom MLX Repo")
                } footer: {
                    Text("Only Hugging Face MLX repos are supported. GGUF and llama.cpp models are not supported.")
                        .foregroundStyle(.secondary)
                }
            }

            if !installedModels.isEmpty {
                Section {
                    ForEach(installedModels, id: \.id) { model in
                        MLXInstalledModelRow(
                            model: model,
                            metadataLine: installedMetadataLine(model),
                            isSelected: selectedMLXModelID == model.id,
                            isBusy: activeModelOperationIDs.contains(model.id),
                            onSelect: { selectInstalledModel(id: model.id) },
                            onDelete: { deleteInstalledModel(id: model.id) }
                        )
                        .onAppear {
                            logInstalledRowState(model, context: "appear")
                        }
                        .onChange(of: activeModelOperationIDs) { _, _ in
                            logInstalledRowState(model, context: "activeModelOperationIDs changed")
                        }
                        .onChange(of: selectedMLXModelID) { _, _ in
                            logInstalledRowState(model, context: "selectedMLXModelID changed")
                        }
                    }
                } header: {
                    Text("Installed")
                }
            }

            Section {
                if let activeDownloadJob,
                   activeDownloadJob.modelID != customRepoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                {
                    MLXActiveDownloadBanner(
                        job: activeDownloadJob,
                        onCancel: cancelCurrentDownloadJob
                    )
                } else if let blockingTerminalJob = currentDownloadJob,
                          !blockingTerminalJob.isActive
                {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(blockingTerminalJob.displayName) is \(blockingTerminalJob.state.displayLabel.lowercased()).")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Dismiss") {
                            dismissCurrentDownloadJob()
                        }
                        .font(.footnote)
                    }
                }

                if !modelOperationMessage.isEmpty {
                    Text(modelOperationMessage)
                        .foregroundStyle(modelOperationIsError ? .red : .secondary)
                }

                if !catalogError.isEmpty {
                    Text(catalogError)
                        .foregroundStyle(.red)
                }

                ForEach(filteredCatalogModels, id: \.id) { model in
                    MLXCatalogModelRow(
                        model: model,
                        metadataLine: catalogMetadataLine(model),
                        recommendation: model.recommendation(forRAMGiB: deviceRAMGiB),
                        isInstalled: installedModels.contains(where: { $0.id == model.id }),
                        isSelected: selectedMLXModelID == model.id,
                        job: downloadJob(for: model.id),
                        isInstallDisabled: activeDownloadJob != nil,
                        onSelect: { selectInstalledModel(id: model.id) },
                        onInstall: { installCatalogModel(model) },
                        onCancelDownload: cancelCurrentDownloadJob,
                        onDismissJob: dismissCurrentDownloadJob
                    )
                }
            } header: {
                Text("mlx-community")
            } footer: {
                Text(mlxCommunityFooterText)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("MLX Models")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isRefreshingCatalog {
                    ProgressView()
                }

                Menu {
                    Toggle(isOn: $showCustomRepoSection) {
                        Label("Show Custom MLX Repo", systemImage: "text.cursor")
                    }

                    Button {
                        refreshCatalog()
                    } label: {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshingCatalog)

                    Button {
                        showAllCatalogModels.toggle()
                    } label: {
                        Label(
                            showAllCatalogModels ? "Hide Likely Too Large" : "Show All Models",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                    .disabled(!showAllCatalogModels && hiddenCatalogModelCount == 0)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .task {
            downloadCoordinator.refreshState()
            if catalogModels.isEmpty {
                refreshCatalog()
            }
            logMLXUIState("mlxManagementPage.task")
            await runDebugAutomationIfNeeded()
        }
        .onReceive(downloadCoordinator.$currentJob) { job in
            installedModels = modelStore.loadInstalledModels()
            selectedMLXModelID = modelStore.loadSelectedModelID()
            logMLXUIState(
                "downloadCoordinator.currentJob=\(job?.state.rawValue ?? "nil")",
                observedJob: job
            )

            guard let job else { return }
            guard !job.isActive else { return }

            switch job.state {
            case .completed:
                modelOperationMessage = "Installed \(job.modelID)."
                modelOperationIsError = false
            case .failed, .cancelled:
                modelOperationMessage = job.errorMessage ?? "\(job.displayName) download failed."
                modelOperationIsError = true
            case .queued, .running, .finishing:
                break
            }
        }
    }

    private func installedMetadataLine(_ model: InstalledMLXModel) -> String {
        let params = model.estimatedParameterCount.map { parameterLabel($0) } ?? "Unknown size"
        let date = model.lastModified.map { Self.relativeDateFormatter.localizedString(for: $0, relativeTo: .now) } ?? "unknown date"
        return [model.pipelineTag, params, date].joined(separator: " · ")
    }

    private func catalogMetadataLine(_ model: MLXCatalogModel) -> String {
        let params = model.estimatedParameterLabel
        let size = model.rawSafeTensorTotal.map { Self.fileSizeFormatter.string(fromByteCount: $0) }
        let base = model.baseModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = model.lastModified.map { Self.relativeDateFormatter.localizedString(for: $0, relativeTo: .now) } ?? "unknown date"
        let fields: [String] = [model.pipelineTag, size, params, base, date].compactMap { value in
            guard let value else { return nil }
            return value.isEmpty ? nil : value
        }
        return fields.joined(separator: " · ")
    }

    private func parameterLabel(_ value: Double) -> String {
        let billion = value / 1_000_000_000
        if billion >= 1 {
            return String(format: "~%.1fB", billion)
        }
        return String(format: "~%.0fM", value / 1_000_000)
    }

    private func loadStateIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        appBackend = appBackendStore.loadSelectedBackend()
        extensionBackend = extensionBackendStore.loadSelectedBackend()
        autoLocalPreference = autoStrategyStore.localModelPreference()
        longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
        longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()
        installedModels = modelStore.loadInstalledModels()
        selectedMLXModelID = modelStore.loadSelectedModelID()
        downloadCoordinator.refreshState()

        let byokSettings = byokStore.loadSettings()
        byokProvider = byokSettings.provider
        byokApiURL = byokSettings.apiURL
        byokApiKey = byokSettings.apiKey
        byokModel = byokSettings.model
        let optionID = BYOKProvider.ProviderPresets.optionID(
            provider: byokProvider,
            apiURL: byokApiURL
        )
        byokProviderOptionID = optionID
        lastConfirmedProviderOptionID = optionID

        validateBYOK()
        scheduleByokConnectionTest()
        logMLXUIState("loadStateIfNeeded")
    }

    private func refreshCatalog() {
        guard !isRefreshingCatalog else { return }
        isRefreshingCatalog = true
        catalogError = ""

        Task {
            do {
                let models = try await catalogService.fetchCatalog(limit: 100)
                await MainActor.run {
                    catalogModels = models
                    isRefreshingCatalog = false
                }
            } catch {
                await MainActor.run {
                    catalogError = error.localizedDescription
                    isRefreshingCatalog = false
                }
            }
        }
    }

    private func installCatalogModel(_ model: MLXCatalogModel) {
        Task {
            do {
                try await downloadCoordinator.startInstall(
                    model: model,
                    source: .catalog,
                    autoSelect: true
                )
                await MainActor.run {
                    modelOperationMessage = "Downloading \(model.id)…"
                    modelOperationIsError = false
                }
            } catch {
                await MainActor.run {
                    modelOperationMessage = error.localizedDescription
                    modelOperationIsError = true
                }
            }
        }
    }

    @MainActor
    private func runDebugAutomationIfNeeded() async {
        guard let request = debugAutomationRequest else { return }
        guard !didRunDebugAutomation else { return }
        didRunDebugAutomation = true

        Self.logger.xcodeNotice(
            "mlxUI automation start repo=\(request.repoID) source=\(request.source.rawValue) autoSelect=\(request.autoSelect) purgeExisting=\(request.purgeExisting)"
        )

        showAllCatalogModels = true
        if request.source == .custom {
            showCustomRepoSection = true
            customRepoDraft = request.repoID
        }

        if request.purgeExisting {
            await purgeDebugAutomationArtifacts(for: request.repoID)
        }

        do {
            let model = try await catalogService.fetchModel(repoID: request.repoID)
            if !catalogModels.contains(where: { $0.id == model.id }) {
                catalogModels.insert(model, at: 0)
            }

            switch request.source {
            case .catalog:
                installCatalogModel(model)
            case .custom:
                customRepoDraft = model.id
                installCustomRepo()
            }
        } catch {
            modelOperationMessage = "Automation failed for \(request.repoID): \(error.localizedDescription)"
            modelOperationIsError = true
            Self.logger.xcodeError(
                "mlxUI automation failed repo=\(request.repoID) error=\(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func purgeDebugAutomationArtifacts(for repoID: String) async {
        if let currentJob = currentDownloadJob, currentJob.modelID == repoID {
            if currentJob.isActive {
                await downloadCoordinator.cancelCurrentJob()
            }
            if let refreshedJob = downloadCoordinator.currentJob,
               refreshedJob.modelID == repoID,
               !refreshedJob.isActive
            {
                downloadCoordinator.dismissCurrentJob()
            }
        }

        do {
            try await client.deleteLocalModel(modelID: repoID)
        } catch {
            Self.logger.xcodeWarning(
                "mlxUI automation purge deleteLocalModel warning repo=\(repoID) error=\(error.localizedDescription)"
            )
        }

        modelStore.removeInstalledModel(id: repoID)
        installedModels = modelStore.loadInstalledModels()
        selectedMLXModelID = modelStore.loadSelectedModelID()
        downloadCoordinator.refreshState()
        Self.logger.xcodeNotice(
            "mlxUI automation purge completed repo=\(repoID) installedNow=\(installedModels.map { $0.id }.sorted()) selectedNow=\(selectedMLXModelID ?? "nil")"
        )
    }

    private func installCustomRepo() {
        let repoID = customRepoDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoID.isEmpty else { return }

        Task {
            do {
                let model = try await catalogService.fetchModel(repoID: repoID)
                try await downloadCoordinator.startInstall(
                    model: model,
                    source: .custom,
                    autoSelect: true
                )
                await MainActor.run {
                    customRepoDraft = ""
                    modelOperationMessage = "Downloading \(model.id)…"
                    modelOperationIsError = false
                }
            } catch {
                await MainActor.run {
                    modelOperationMessage = error.localizedDescription
                    modelOperationIsError = true
                }
            }
        }
    }

    private func selectInstalledModel(id: String) {
        modelStore.saveSelectedModelID(id)
        selectedMLXModelID = id
        modelOperationMessage = "Selected \(id)."
        modelOperationIsError = false
        logMLXUIState("selectInstalledModel id=\(id)")
    }

    private func deleteInstalledModel(id: String) {
        Self.logger.xcodeNotice(
            "deleteInstalledModel requested id=\(id) activeBefore=\(activeModelOperationIDs.sorted()) installed=\(installedModels.map { $0.id }.sorted()) selected=\(selectedMLXModelID ?? "nil")"
        )
        startModelOperation(for: id)
        Task {
            do {
                try await client.deleteLocalModel(modelID: id)
                await MainActor.run {
                    modelStore.removeInstalledModel(id: id)
                    installedModels = modelStore.loadInstalledModels()
                    selectedMLXModelID = modelStore.loadSelectedModelID()
                    modelOperationMessage = "Deleted \(id)."
                    modelOperationIsError = false
                    Self.logger.xcodeNotice(
                        "deleteInstalledModel succeeded id=\(id) installedNow=\(installedModels.map { $0.id }.sorted()) selectedNow=\(selectedMLXModelID ?? "nil")"
                    )
                    finishModelOperation(for: id)
                }
            } catch {
                await MainActor.run {
                    modelOperationMessage = "Failed to delete \(id): \(error.localizedDescription)"
                    modelOperationIsError = true
                    Self.logger.xcodeError(
                        "deleteInstalledModel failed id=\(id) error=\(error.localizedDescription) activeNow=\(activeModelOperationIDs.sorted())"
                    )
                    finishModelOperation(for: id)
                }
            }
        }
    }

    private func startModelOperation(for id: String) {
        activeModelOperationIDs.insert(id)
        Self.logger.xcodeNotice(
            "startModelOperation id=\(id) activeModelOperationIDs=\(activeModelOperationIDs.sorted())"
        )
    }

    private func finishModelOperation(for id: String) {
        activeModelOperationIDs.remove(id)
        Self.logger.xcodeNotice(
            "finishModelOperation id=\(id) activeModelOperationIDs=\(activeModelOperationIDs.sorted())"
        )
    }

    private func cancelCurrentDownloadJob() {
        Self.logger.xcodeNotice("cancelCurrentDownloadJob tapped currentJob=\(downloadCoordinator.currentJobLogSummary)")
        Task {
            await downloadCoordinator.cancelCurrentJob()
            await MainActor.run {
                modelOperationMessage = "Cancelling MLX download…"
                modelOperationIsError = false
            }
        }
    }

    private func dismissCurrentDownloadJob() {
        Self.logger.xcodeNotice("dismissCurrentDownloadJob tapped currentJob=\(downloadCoordinator.currentJobLogSummary)")
        downloadCoordinator.dismissCurrentJob()
        modelOperationMessage = ""
        modelOperationIsError = false
    }

    private func downloadJob(for modelID: String) -> MLXDownloadJob? {
        guard let currentDownloadJob else { return nil }
        guard currentDownloadJob.modelID == modelID else { return nil }
        guard currentDownloadJob.isActive || currentDownloadJob.state == .failed || currentDownloadJob.state == .cancelled else { return nil }
        return currentDownloadJob
    }

    private var customDownloadJob: MLXDownloadJob? {
        guard let currentDownloadJob else { return nil }
        guard currentDownloadJob.source == .custom else { return nil }
        guard currentDownloadJob.isActive || currentDownloadJob.state == .failed || currentDownloadJob.state == .cancelled else { return nil }
        guard !installedModels.contains(where: { $0.id == currentDownloadJob.modelID }) else { return nil }
        return currentDownloadJob
    }

    private func logInstalledRowState(_ model: InstalledMLXModel, context: String) {
        let isSelected = selectedMLXModelID == model.id
        let isActive = activeModelOperationIDs.contains(model.id)
        let visibleTrailingControl = isActive ? "progress" : "delete"
        Self.logger.xcodeNotice(
            "installedRow context=\(context) id=\(model.id) selected=\(isSelected) active=\(isActive) visibleTrailingControl=\(visibleTrailingControl) activeModelOperationIDs=\(activeModelOperationIDs.sorted())"
        )
    }

    private func logMLXUIState(_ context: String, observedJob: MLXDownloadJob? = nil) {
        let jobSummary = observedJob.map { job in
            "id=\(job.jobID) task=\(job.taskIdentifier) model=\(job.modelID) state=\(job.state.rawValue) completed=\(job.completedUnitCount) total=\(job.totalUnitCount) fraction=\(String(format: "%.3f", job.fractionCompleted)) source=\(job.source.rawValue) autoSelect=\(job.autoSelectOnCompletion) error=\(job.errorMessage ?? "nil")"
        } ?? downloadCoordinator.currentJobLogSummary
        Self.logger.xcodeNotice(
            "mlxUI context=\(context) installed=\(installedModels.map { $0.id }.sorted()) selected=\(selectedMLXModelID ?? "nil") activeModelOperationIDs=\(activeModelOperationIDs.sorted()) currentDownloadJob=\(jobSummary)"
        )
    }

    private func validateBYOK() {
        let settings = BYOKSettings(
            provider: byokProvider,
            apiURL: byokApiURL,
            apiKey: byokApiKey,
            model: byokModel
        )

        if let error = byokStore.validationError(for: settings) {
            byokFooterIsError = true
            byokFooterMessage = error.message
            return
        }
        byokFooterIsError = false
        byokFooterMessage = ""
    }

    private func applyProviderOption(_ option: BYOKProvider.ProviderOption) {
        byokProvider = option.provider
        if let preset = option.preset {
            byokApiURL = preset.apiURL
        }
        lastConfirmedProviderOptionID = option.id
    }

    private func resetByokPing() {
        byokPingTask?.cancel()
        byokPingTask = nil
        byokPingStatus = .idle
        byokPingError = ""
        byokPingResponse = ""
    }

    private func resetByokConnectionTest() {
        byokConnectionTask?.cancel()
        byokConnectionTask = nil
        byokConnectionStatus = .idle
        byokConnectionError = ""
        byokConnectionMessage = ""
        byokAvailableModels = []
    }

    private func scheduleByokConnectionTest() {
        byokConnectionTask?.cancel()
        byokConnectionTask = nil

        let settings = BYOKSettings(
            provider: byokProvider,
            apiURL: byokApiURL,
            apiKey: byokApiKey,
            model: byokModel
        )
        let trimmedURL = settings.trimmedApiURL
        let trimmedModel = settings.trimmedModel
        guard !trimmedURL.isEmpty else {
            byokConnectionStatus = .idle
            byokConnectionError = ""
            byokConnectionMessage = ""
            byokAvailableModels = []
            return
        }

        guard URL(string: trimmedURL) != nil else {
            byokConnectionStatus = .failed
            byokConnectionError = "Invalid URL."
            byokConnectionMessage = ""
            byokAvailableModels = []
            return
        }

        let supportsModelList = settings.provider.supportsModelList
        if !supportsModelList {
            byokAvailableModels = []
        }

        if !supportsModelList, trimmedModel.isEmpty {
            byokConnectionStatus = .idle
            byokConnectionError = ""
            byokConnectionMessage = "Enter a model ID to run the test."
            return
        }

        if supportsModelList {
            byokAvailableModels = []
        }

        byokConnectionStatus = .testing
        byokConnectionError = ""
        byokConnectionMessage = ""
        byokConnectionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                if supportsModelList {
                    let models = try await fetchByokModelList(settings)
                    byokAvailableModels = models
                    byokConnectionStatus = .success
                    byokConnectionMessage = models.isEmpty
                        ? "Model list returned no models."
                        : "Model list loaded (\(models.count) models)."
                } else {
                    try await performByokConnectionTest(settings)
                    byokConnectionStatus = .success
                    byokConnectionMessage = "Ping OK."
                }
                byokConnectionError = ""
            } catch is CancellationError {
                return
            } catch {
                byokConnectionStatus = .failed
                byokConnectionError = error.localizedDescription
                byokConnectionMessage = ""
                byokAvailableModels = supportsModelList ? [] : byokAvailableModels
            }
        }
    }

    private func performByokConnectionTest(_ settings: BYOKSettings) async throws {
        let stream = try await client.streamChat(
            systemPrompt: "You are a connection test.",
            userPrompt: "ping",
            temperature: 0.2,
            maximumResponseTokens: 1,
            backend: .byok,
            byok: settings
        )
        for try await _ in stream {
            break
        }
    }

    private func runByokPingAndSave() {
        byokPingTask?.cancel()
        byokPingTask = nil

        let settings = BYOKSettings(
            provider: byokProvider,
            apiURL: byokApiURL,
            apiKey: byokApiKey,
            model: byokModel
        )

        if let error = byokStore.validationError(for: settings) {
            byokPingStatus = .failed
            byokPingError = error.message
            byokPingResponse = ""
            return
        }

        byokPingStatus = .testing
        byokPingError = ""
        byokPingResponse = ""
        byokPingTask = Task { @MainActor in
            do {
                let response = try await performByokPing(settings)
                byokStore.saveSettings(settings)
                byokPingStatus = .success
                byokPingResponse = response.isEmpty ? "No response body." : response
                byokPingError = ""
            } catch is CancellationError {
                return
            } catch {
                byokPingStatus = .failed
                byokPingError = error.localizedDescription
                byokPingResponse = ""
            }
        }
    }

    private func performByokPing(_ settings: BYOKSettings) async throws -> String {
        let stream = try await client.streamChat(
            systemPrompt: "You are a ping.",
            userPrompt: "ping",
            backend: .byok,
            byok: settings
        )
        var response = ""
        for try await delta in stream {
            response.append(delta)
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchByokModelList(_ settings: BYOKSettings) async throws -> [String] {
        let baseURL = try BYOKURLResolver.resolveBaseURL(
            for: settings.provider,
            rawValue: settings.apiURL
        )

        switch settings.provider {
        case .openAIChat, .openAIResponses:
            return try await fetchOpenAIModelList(baseURL: baseURL, apiKey: settings.apiKey)
        case .ollama:
            return try await fetchOllamaModelList(baseURL: baseURL)
        case .anthropic, .gemini:
            return []
        }
    }

    private func fetchOpenAIModelList(baseURL: URL, apiKey: String) async throws -> [String] {
        let modelsURL = openAIModelsURL(baseURL: baseURL)
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
        return decoded.data
            .map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fetchOllamaModelList(baseURL: URL) async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func openAIModelsURL(baseURL: URL) -> URL {
        let lowercasedPath = baseURL.path.lowercased()
        if lowercasedPath.hasSuffix("/v1") || lowercasedPath.hasSuffix("/v1/") {
            return baseURL.appendingPathComponent("models")
        }
        return baseURL.appendingPathComponent("v1").appendingPathComponent("models")
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BYOKHTTPError(statusCode: nil, body: nil)
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw BYOKHTTPError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct ModelPickerOption: Identifiable {
    let value: String
    let label: String

    var id: String { value }
}

private struct OpenAIModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct BYOKHTTPError: LocalizedError {
    let statusCode: Int?
    let body: String?

    var errorDescription: String? {
        if let statusCode {
            let trimmedBody = body?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(200)
            if let trimmedBody, !trimmedBody.isEmpty {
                return "HTTP \(statusCode): \(trimmedBody)"
            }
            return "HTTP \(statusCode)."
        }
        return "Unexpected response."
    }
}

private enum BYOKConnectionStatus {
    case idle
    case testing
    case success
    case failed

    var color: Color {
        switch self {
        case .idle: return .gray
        case .testing: return .yellow
        case .success: return .green
        case .failed: return .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return "Connection idle"
        case .testing: return "Connection testing"
        case .success: return "Connection passed"
        case .failed: return "Connection failed"
        }
    }
}

private enum BYOKPingStatus {
    case idle
    case testing
    case success
    case failed

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .testing: return "Testing"
        case .success: return "Success"
        case .failed: return "Failed"
        }
    }
}
