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

    @State private var didLoad = false
    @State private var backend: GenerationBackend = .mlc

    @State private var byokProvider: BYOKProvider = .openAIChat
    @State private var byokApiURL = ""
    @State private var byokApiKey = ""
    @State private var byokModel = ""
    @State private var byokFooterMessage = ""
    @State private var byokFooterIsError = false

    @State private var byokLongDocPreset: BYOKLongDocumentPreset = .safe
    @State private var longDocumentChunkTokenSize: Int = 2000
    @State private var longDocumentMaxChunkCount: Int = 5
    @State private var tokenEstimatorEncoding: Encoding = .cl100k

    private var aiStatus: AppleIntelligenceAvailability.Status {
        AppleIntelligenceAvailability.currentStatus()
    }

    private var availableBackends: [GenerationBackend] {
        var options: [GenerationBackend] = [.mlc, .byok]
        if aiStatus == .available {
            options.insert(.appleIntelligence, at: 1)
        }
        return options
    }

    private var backendFooterText: String {
        switch aiStatus {
        case .available:
            return "Apple Intelligence available on this device."
        case .notSupported:
            return "Requires iOS 26+ and Apple Intelligence enabled."
        case let .unavailable(reason):
            return reason
        }
    }

    private var byokLongDocFooterText: String {
        """
        \(byokLongDocPreset.contextLabel)
        • Chunk Size: \(byokLongDocPreset.chunkSize)
        • Routing Threshold: \(byokLongDocPreset.routingThreshold)
        """
    }

    var body: some View {
        Form {
            Section {
                Picker("Backend", selection: $backend) {
                    ForEach(availableBackends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Generation Backend")
            } footer: {
                Text(backendFooterText)
                    .foregroundStyle(.secondary)
            }

            if backend == .byok {
                Section {
                    Picker("Provider", selection: $byokProvider) {
                        ForEach(BYOKProvider.httpOptions, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("API URL", text: $byokApiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("API Key", text: $byokApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Model", text: $byokModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("HTTP Provider")
                } footer: {
                    Text(byokFooterMessage)
                        .foregroundStyle(byokFooterIsError ? .red : .secondary)
                }

                Section {
                    HStack {
                        Text("Strategy")
                            .font(.headline)

                        Spacer()

                        Menu {
                            ForEach(BYOKLongDocumentPreset.allCases) { preset in
                                Button {
                                    byokLongDocPreset = preset
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                        Text(preset.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(byokLongDocPreset.title)
                                Text(byokLongDocPreset.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Long Document")
                } footer: {
                    Text(byokLongDocFooterText)
                        .foregroundStyle(.secondary)
                }
            }

            if backend != .byok {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Long Document Processing")
                            .font(.headline)

                        Text("eisonAI estimates token count with the selected tokenizer. If a document exceeds the routing threshold, it is split into fixed-size chunks. The app extracts key points per chunk, then generates a short summary from those key points.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Overview")
                }

                Section {
                    Picker(
                        "Chunk size for long documents",
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
                    Text("Chunk size is measured in tokens. Routing threshold is fixed at 2600 tokens.")
                }
            }

            Section {
                Picker(
                    "Max number of chunks",
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
                Text("Chunk Limit")
            } footer: {
                Text("Chunks beyond the limit are discarded to keep processing time predictable.")
            }

            Section {
                Picker(
                    "Token counting model",
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
                Text("Token Counting")
            } footer: {
                Text("Applies to token estimation and chunking in both the app and Safari extension.")
            }
        }
        .navigationTitle("AI Models")
        .onAppear {
            loadStateIfNeeded()
        }
        .onChange(of: backend) { _, newValue in
            guard didLoad else { return }
            backendStore.saveSelectedBackend(newValue)
        }
        .onChange(of: byokProvider) { _, _ in
            if didLoad { validateAndSaveBYOK() }
        }
        .onChange(of: byokApiURL) { _, _ in
            if didLoad { validateAndSaveBYOK() }
        }
        .onChange(of: byokApiKey) { _, _ in
            if didLoad { validateAndSaveBYOK() }
        }
        .onChange(of: byokModel) { _, _ in
            if didLoad { validateAndSaveBYOK() }
        }
        .onChange(of: byokLongDocPreset) { _, newValue in
            if didLoad { applyByokLongDocPreset(newValue) }
        }
    }

    private func loadStateIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let selected = backendStore.loadSelectedBackend()
        if selected == .appleIntelligence, aiStatus != .available {
            backend = .mlc
            backendStore.saveSelectedBackend(.mlc)
        } else {
            backend = selected
        }

        let byokSettings = byokStore.loadSettings()
        byokProvider = byokSettings.provider
        byokApiURL = byokSettings.apiURL
        byokApiKey = byokSettings.apiKey
        byokModel = byokSettings.model

        let storedChunkSize = byokLongDocStore.chunkTokenSize()
        let storedRoutingThreshold = byokLongDocStore.routingThreshold()
        byokLongDocPreset = BYOKLongDocumentPreset.match(
            chunkSize: storedChunkSize,
            routingThreshold: storedRoutingThreshold
        )

        longDocumentChunkTokenSize = longDocumentSettingsStore.chunkTokenSize()
        longDocumentMaxChunkCount = longDocumentSettingsStore.maxChunkCount()
        tokenEstimatorEncoding = tokenEstimatorSettingsStore.selectedEncoding()

        validateAndSaveBYOK(updateStorage: false)
        applyByokLongDocPreset(byokLongDocPreset, updateStorage: false)
    }

    private func validateAndSaveBYOK(updateStorage: Bool = true) {
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

        if updateStorage {
            byokStore.saveSettings(settings)
        }
        byokFooterIsError = false
        byokFooterMessage = "自動保存完畢"
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

#Preview {
    NavigationStack {
        AIModelsSettingsView()
    }
}
