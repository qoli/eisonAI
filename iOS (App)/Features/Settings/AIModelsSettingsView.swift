import SwiftUI

struct AIModelsSettingsView: View {
    private let backendStore = GenerationBackendSettingsStore()
    private let byokStore = BYOKSettingsStore()
    private let byokLongDocStore = BYOKLongDocumentSettingsStore.shared

    @State private var didLoad = false
    @State private var backend: GenerationBackend = .mlc

    @State private var byokProvider: BYOKProvider = .openAIChat
    @State private var byokApiURL = ""
    @State private var byokApiKey = ""
    @State private var byokModel = ""
    @State private var byokFooterMessage = ""
    @State private var byokFooterIsError = false

    @State private var byokChunkTokenSize = ""
    @State private var byokRoutingThreshold = ""
    @State private var byokLongDocFooterMessage = ""
    @State private var byokLongDocFooterIsError = false

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
                    TextField("Chunk size", text: $byokChunkTokenSize)
                        .keyboardType(.numberPad)
                    TextField("Routing threshold", text: $byokRoutingThreshold)
                        .keyboardType(.numberPad)
                } header: {
                    Text("BYOK Long Document")
                } footer: {
                    Text(byokLongDocFooterMessage)
                        .foregroundStyle(byokLongDocFooterIsError ? .red : .secondary)
                }
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
        .onChange(of: byokChunkTokenSize) { _, _ in
            if didLoad { validateAndSaveBYOKLongDoc() }
        }
        .onChange(of: byokRoutingThreshold) { _, _ in
            if didLoad { validateAndSaveBYOKLongDoc() }
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

        byokChunkTokenSize = String(byokLongDocStore.chunkTokenSize())
        byokRoutingThreshold = String(byokLongDocStore.routingThreshold())

        validateAndSaveBYOK(updateStorage: false)
        validateAndSaveBYOKLongDoc(updateStorage: false)
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

    private func validateAndSaveBYOKLongDoc(updateStorage: Bool = true) {
        let chunkSize = Int(byokChunkTokenSize) ?? 0
        let routingThreshold = Int(byokRoutingThreshold) ?? 0

        if chunkSize <= 0 {
            byokLongDocFooterIsError = true
            byokLongDocFooterMessage = "Chunk size 必須為正整數"
            return
        }

        if routingThreshold <= 0 {
            byokLongDocFooterIsError = true
            byokLongDocFooterMessage = "Routing threshold 必須為正整數"
            return
        }

        if updateStorage {
            byokLongDocStore.setChunkTokenSize(chunkSize)
            byokLongDocStore.setRoutingThreshold(routingThreshold)
        }

        byokLongDocFooterIsError = false
        byokLongDocFooterMessage = "自動保存完畢"
    }
}

#Preview {
    NavigationStack {
        AIModelsSettingsView()
    }
}
