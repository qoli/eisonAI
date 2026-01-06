import SwiftUI

struct AboutView: View {
    @State private var showOnboarding = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()

                    VStack {
                        Image("ImageLogo")
                        Image("TextLogo")

                        Color.clear.frame(height: 12)

                        Text("Version \(appVersion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 28)
            }

            Section {
                HStack {
                    Image(systemName: "viewfinder.circle")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Cognitive Index")
                        Text("Make structure visible at a glance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "viewfinder.circle")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Cognitive Index")
                        Text("Make structure visible at a glance.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Long Document")
                        Text("Chunked processing keeps long reads stable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "puzzlepiece.extension")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Safari Extension")
                        Text("Summarize and read right inside Safari.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "lock.square")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Local-First")
                        Text("On-device processing keeps your data private.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Source Trust")
                        Text("Verify sources, not slogans.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "books.vertical")
                        .padding(.trailing, 6)

                    VStack(alignment: .leading) {
                        Text("Library & Tags")
                        Text("Save, tag, and revisit what matters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Highlights")
            } footer: {
                Text("Highlights are designed to keep reading fast, clear, and reliable.")
            }

            Section {
                NavigationLink("View onboarding again") {
                    OnboardingView(defaultPage: 0)
                }
            } header: {
                Text("Experience")
            } footer: {
                Text("Revisit the full onboarding walkthrough anytime.")
            }

            Section {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
            } header: {
                Text("Links")
            }

            Section {
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Terms_of_Service.md")!) {
                    Text("Terms of Service")
                }
                Link(destination: URL(string: "https://github.com/qoli/eisonAI/blob/main/Docs/Privacy_Policy.md")!) {
                    Text("Privacy Policy")
                }
            } header: {
                Text("Legal")
            }

            #if DEBUG
                Section {
                    NavigationLink("Debug") {
                        DebugSettingsView()
                    }
                } header: {
                    Text("Debug")
                }
            #endif
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
