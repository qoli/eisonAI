import Foundation
import SwiftUI

struct AIModelsSettingsView: View {
    private let backendStore = GenerationBackendSettingsStore()
    private let byokStore = BYOKSettingsStore()
    private let byokLongDocStore = BYOKLongDocumentSettingsStore.shared
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let tokenEstimatorSettingsStore = TokenEstimatorSettingsStore.shared
    private let longDocumentChunkSizeOptions: [Int] = [2000, 2200, 2600, 3000, 3200]
    private let longDocumentMaxChunkOptions: [Int] = [4, 5, 6, 7]
    private let tokenEstimatorOptions: [Encoding] = [.cl100k, .o200k, .p50k, .r50k]
    private static let modelPickerPlaceholderTag = "__byok_model_placeholder__"
    private static let modelPickerCustomTag = "__byok_model_custom__"

    @State private var didLoad = false
    @State private var backend: GenerationBackend = .mlc
    @AppStorage(AppConfig.localQwenEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var localQwenEnabled = false

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

    @State private var byokLongDocPreset: BYOKLongDocumentPreset = .safe
    @State private var longDocumentChunkTokenSize: Int = 2000
    @State private var longDocumentMaxChunkCount: Int = 5
    @State private var tokenEstimatorEncoding: Encoding = .cl100k

    private var aiStatus: AppleIntelligenceAvailability.Status {
        AppleIntelligenceAvailability.currentStatus()
    }

    private var availableBackends: [GenerationBackend] {
        var options: [GenerationBackend] = []
        if localQwenEnabled {
            options.append(.mlc)
        }
        if aiStatus == .available {
            options.append(.appleIntelligence)
        }
        options.append(.byok)
        return options
    }

    private var backendFooterText: String {
        switch aiStatus {
        case .available:
            return "Apple Intelligence is available on this device."
        case .notSupported:
            return "Requires iOS 26+ with Apple Intelligence enabled."
        case let .unavailable(reason):
            return reason
        }
    }

    private var byokLongDocFooterText: String {
        """
        \(byokLongDocPreset.contextLabel) · Chunk \(byokLongDocPreset.chunkSize) · Route \(byokLongDocPreset.routingThreshold)
        Recommended: Safe (8K)
        """
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
            options.append(ModelPickerOption(value: trimmedModel, label: "Custom: \(trimmedModel)"))
        }

        options.append(ModelPickerOption(
            value: Self.modelPickerCustomTag,
            label: "Enter Model ID"
        ))
        return options
    }

    var body: some View {
        Form {
            Section {
                Picker("Backend", selection: $backend) {
                    ForEach(availableBackends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

            } header: {
                Text("Generation Engine")
            } footer: {
                Text(backendFooterText)
                    .foregroundStyle(.secondary)
            }

            if backend == .byok {
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
                    Text("Provider Configuration")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let docsURL = selectedProviderDocsURL {
                            Link("Documentation", destination: docsURL)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if byokFooterIsError, !byokFooterMessage.isEmpty {
                            Text(byokFooterMessage)
                                .foregroundStyle(.red)
                        } else {
                            Text("Saved after Verify & Save.")
                                .foregroundStyle(.secondary)
                        }
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

                    HStack {
                        Text("Verify")
                        Spacer()
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
                    }

                } header: {
                    Text("Verify")
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

                Section {
                    Picker("Context Strategy", selection: $byokLongDocPreset) {
                        ForEach(BYOKLongDocumentPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                } header: {
                    Text("Long-Document Strategy")
                } footer: {
                    Text(byokLongDocFooterText)
                        .foregroundStyle(.secondary)
                }
            }

            if backend != .byok {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Long-Document Processing")
                            .font(.headline)

                        Text("We estimate tokens with the selected tokenizer. If content exceeds the routing threshold, we split it into chunks, summarize each chunk, then combine key points into a final summary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Overview")
                }

                Section {
                    Picker(
                        "Chunk Size",
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
                } header: {
                    Text("Chunk Size")
                } footer: {
                    Text("Chunk size is in tokens. Routing threshold is fixed at 2,600.")
                }
            }

            Section {
                Picker(
                    "Max Chunks",
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
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("Max Chunks")
            } footer: {
                Text("Extra chunks are skipped to keep processing time predictable.")
            }

            Section {
                Picker(
                    "Tokenizer",
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

            } header: {
                Text("Tokenization")
            } footer: {
                Text("Used for token estimates and chunking in the app and Safari extension.")
                    .padding(.bottom)
            }
        }

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
        .onAppear {
            loadStateIfNeeded()
        }
        .onChange(of: backend) { _, newValue in
            guard didLoad else { return }
            backendStore.saveSelectedBackend(newValue)
            if newValue == .byok {
                scheduleByokConnectionTest()
            } else {
                resetByokConnectionTest()
                resetByokPing()
            }
        }
        .onChange(of: localQwenEnabled) { _, _ in
            guard didLoad else { return }
            let resolved = resolveBackendSelection(backend)
            if resolved != backend {
                backend = resolved
                backendStore.saveSelectedBackend(resolved)
            }
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
        .onChange(of: byokLongDocPreset) { _, newValue in
            if didLoad { applyByokLongDocPreset(newValue) }
        }
    }

    private func loadStateIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let selected = backendStore.loadSelectedBackend()
        let resolved = resolveBackendSelection(selected)
        backend = resolved
        if resolved != selected {
            backendStore.saveSelectedBackend(resolved)
        }

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

        let storedChunkSize = byokLongDocStore.chunkTokenSize()
        let storedRoutingThreshold = byokLongDocStore.routingThreshold()
        byokLongDocPreset = BYOKLongDocumentPreset.match(
            chunkSize: storedChunkSize,
            routingThreshold: storedRoutingThreshold
        )

        longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
        longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()
        tokenEstimatorEncoding = tokenEstimatorSettingsStore.selectedEncoding()

        validateBYOK()
        applyByokLongDocPreset(byokLongDocPreset, updateStorage: false)
        if backend == .byok {
            scheduleByokConnectionTest()
        }
    }

    private func resolveBackendSelection(_ selected: GenerationBackend) -> GenerationBackend {
        if selected == .mlc, !localQwenEnabled {
            return aiStatus == .available ? .appleIntelligence : .byok
        }
        if selected == .appleIntelligence, aiStatus != .available {
            return localQwenEnabled ? .mlc : .byok
        }
        return selected
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

    private func applyByokLongDocPreset(
        _ preset: BYOKLongDocumentPreset,
        updateStorage: Bool = true
    ) {
        if updateStorage {
            byokLongDocStore.setChunkTokenSize(preset.chunkSize)
            byokLongDocStore.setRoutingThreshold(preset.routingThreshold)
        }
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

        guard backend == .byok else {
            resetByokConnectionTest()
            return
        }

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
                try await Task.sleep(nanoseconds: 350000000)
                try Task.checkCancellation()
                if supportsModelList {
                    let models = try await fetchByokModelList(settings)
                    byokAvailableModels = models
                    byokConnectionStatus = .success
                    if models.isEmpty {
                        byokConnectionMessage = "Model list returned no models."
                    } else {
                        byokConnectionMessage = "Model list loaded (\(models.count) models)."
                    }
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
        let client = AnyLanguageModelClient()
        let stream = try await client.streamChat(
            systemPrompt: "You are a connection test.",
            userPrompt: "ping",
            temperature: 0,
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

        let hasKey = !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        print("[BYOK] Verify & Save start provider=\(settings.provider.rawValue) apiURL=\(settings.trimmedApiURL) model=\(settings.trimmedModel) hasKey=\(hasKey)")

        if let error = byokStore.validationError(for: settings) {
            byokPingStatus = .failed
            byokPingError = error.message
            byokPingResponse = ""
            print("[BYOK] Verify & Save validation failed error=\(error.message)")
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
                let preview = response.prefix(200)
                print("[BYOK] Verify & Save success responsePreview=\(preview)")
            } catch is CancellationError {
                print("[BYOK] Verify & Save cancelled")
                return
            } catch {
                byokPingStatus = .failed
                byokPingError = error.localizedDescription
                byokPingResponse = ""
                print("[BYOK] Verify & Save failed error=\(error)")
            }
        }
    }

    private func performByokPing(_ settings: BYOKSettings) async throws -> String {
        let client = AnyLanguageModelClient()
        let stream = try await client.streamChat(
            systemPrompt: "You are a ping.",
            userPrompt: "ping",
//            temperature: 0, 部分模型會不認可 temperature = 0
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

private enum BYOKLongDocumentPreset: String, CaseIterable, Identifiable {
    case safe
    case balanced
    case large
    case ultra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: return "Safe"
        case .balanced: return "Balanced"
        case .large: return "Large Context"
        case .ultra: return "Ultra"
        }
    }

    var subtitle: String {
        switch self {
        case .safe: return "8K Context Windows"
        case .balanced: return "16K Context Windows"
        case .large: return "32K Context Windows"
        case .ultra: return "128K Context Windows"
        }
    }

    var contextLabel: String {
        switch self {
        case .safe: return "8K Context Windows"
        case .balanced: return "16K Context Windows"
        case .large: return "32K Context Windows"
        case .ultra: return "128K Context Windows"
        }
    }

    var chunkSize: Int {
        switch self {
        case .safe: return 4096
        case .balanced: return 6144
        case .large: return 12288
        case .ultra: return 32768
        }
    }

    var routingThreshold: Int {
        switch self {
        case .safe: return 7168
        case .balanced: return 14336
        case .large: return 28672
        case .ultra: return 114688
        }
    }

    static func match(chunkSize: Int, routingThreshold: Int) -> BYOKLongDocumentPreset {
        for preset in allCases {
            if preset.chunkSize == chunkSize && preset.routingThreshold == routingThreshold {
                return preset
            }
        }
        return .safe
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

#Preview {
    NavigationStack {
        AIModelsSettingsView()
    }
}
