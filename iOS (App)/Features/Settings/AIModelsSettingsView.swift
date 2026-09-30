import Foundation
import SwiftUI

struct AIModelsSettingsView: View {
    private let appBackendStore = GenerationBackendSettingsStore()
    private let extensionBackendStore = ExtensionGenerationBackendSettingsStore()
    private let byokStore = BYOKSettingsStore()
    private let longDocumentSettingsStore = LongDocumentSettingsStore.shared
    private let client = AnyLanguageModelClient()
    private let longDocumentChunkSizeOptions: [Int] = LongDocumentDefaults.allowedChunkSizes
    private let longDocumentMaxChunkOptions: [Int] = LongDocumentDefaults.allowedMaxChunkCounts
    private static let modelPickerPlaceholderTag = "__byok_model_placeholder__"
    private static let modelPickerCustomTag = "__byok_model_custom__"

    @State private var didLoad = false
    @State private var appBackend: GenerationBackend = .local
    @State private var extensionBackend: ExtensionGenerationBackendSelection = .auto
    @State private var longDocumentChunkTokenSize = LongDocumentDefaults.fallbackChunkSize
    @State private var longDocumentMaxChunkCount = LongDocumentDefaults.fallbackMaxChunkCount

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

    private var aiStatus: AppleIntelligenceAvailability.Status {
        AppleIntelligenceAvailability.currentStatus()
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
        settingsForm
            .navigationTitle("Models")
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

    private var settingsForm: some View {
        Form {
            Section {
                Picker("In-App Model", selection: $appBackend) {
                    ForEach(GenerationBackend.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }

                Picker("Safari Model", selection: $extensionBackend) {
                    ForEach(ExtensionGenerationBackendSelection.allCases, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
            } header: {
                Text("Where Models Run")
            } footer: {
                Text(backendFooterText)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    byokSettingsPage
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BYOK Settings")
                                .foregroundStyle(.primary)
                            Text(byokSectionSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            } header: {
                Text("BYOK")
            } footer: {
                Text("Configure your provider, model, and verification flow in a separate page.")
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink {
                    longDocumentSettingsPage
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Long Document")
                        Text(longDocumentSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Advanced options for Apple Intelligence, including chunking for long inputs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var byokSettingsPage: some View {
        Form {
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
                Text("Provider")
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
                Text("Verification")
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
        }
        .navigationTitle("BYOK Settings")
    }

    private var longDocumentSettingsPage: some View {
        Form {
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
            } footer: {
                Text("These settings control how long inputs are split for Apple Intelligence before routing falls back to BYOK when needed.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Long Document")
    }

    private var backendFooterText: String {
        var lines: [String] = []
        switch aiStatus {
        case .available:
            lines.append("Apple Intelligence is available on this device.")
        case .notSupported:
            lines.append("Apple Intelligence requires iOS 26 or later and must be enabled.")
        case let .unavailable(reason):
            lines.append("Apple Intelligence is unavailable: \(reason)")
        }

        lines.append("Downloaded local models are no longer supported. The app and Safari use Apple Intelligence or BYOK.")
        return lines.joined(separator: "\n")
    }

    private var byokSectionSummary: String {
        var parts: [String] = []
        if let option = selectedProviderOption {
            parts.append(option.displayName)
        }

        let trimmedModel = byokModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            parts.append(trimmedModel)
        }

        switch byokPingStatus {
        case .success:
            parts.append("Verified")
        case .failed:
            parts.append("Verify Failed")
        case .testing:
            parts.append("Verifying")
        case .idle:
            break
        }

        return parts.isEmpty ? "Provider, model, and verification" : parts.joined(separator: " · ")
    }

    private var longDocumentSummary: String {
        "Chunking and limits for Apple Intelligence"
    }

    private func loadStateIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        appBackend = appBackendStore.loadSelectedBackend()
        extensionBackend = extensionBackendStore.loadSelectedBackend()
        longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
        longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()

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

#Preview("Models") {
    NavigationStack {
        AIModelsSettingsView()
    }
}
