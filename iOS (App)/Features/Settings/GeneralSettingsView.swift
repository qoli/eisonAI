import SwiftUI

struct GeneralSettingsView: View {
    private let shareOpenAppStore = ShareOpenAppSettingsStore()
    private let sharePollingStore = SharePollingSettingsStore()
    private let modelLanguageStore = ModelLanguageStore()

    @State private var shareOpenAppEnabled = true
    @State private var sharePollingEnabled = true
    @State private var modelLanguageTag = ""
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $modelLanguageTag) {
                    ForEach(ModelLanguage.supported) { language in
                        Text(language.displayName).tag(language.tag)
                    }
                }
            } header: {
                Text("Language of Thought")
            } footer: {
                Text("Choose the language eisonAI uses to think and write.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Safari Extension")
                        .font(.headline)

                    Text("Enable eisonAI in Settings → Safari → Extensions. Cognitive Index™ renders structure using the model engine selected in AI Models.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Extensions")
            } footer: {
                Text("Visualize structure directly inside Safari.")
            }

            Section {
                Toggle(
                    "Open eisonAI after sharing",
                    isOn: Binding(
                        get: { shareOpenAppEnabled },
                        set: { newValue in
                            shareOpenAppEnabled = newValue
                            shareOpenAppStore.setEnabled(newValue)
                        }
                    )
                )
            } header: {
                Text("Share Extension")
            } footer: {
                Text("When enabled, eisonAI opens automatically after you share.")
            }

//            Section {
//                Toggle(
//                    "Share Polling",
//                    isOn: Binding(
//                        get: { sharePollingEnabled },
//                        set: { newValue in
//                            sharePollingEnabled = newValue
//                            sharePollingStore.setEnabled(newValue)
//                        }
//                    )
//                )
//            } header: {
//                Text("Share Extension")
//            } footer: {
//                Text("When enabled, the app checks every 2 seconds while it is in the foreground.")
//            }
        }
        .navigationTitle("General")
        .onAppear {
            if !didLoad {
                didLoad = true
                shareOpenAppEnabled = shareOpenAppStore.isEnabled()
                sharePollingEnabled = sharePollingStore.isEnabled()
                modelLanguageTag = modelLanguageStore.loadOrRecommended()
            }
        }
        .onChange(of: modelLanguageTag) { _, newValue in
            guard didLoad else { return }
            modelLanguageStore.save(newValue)
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
