import SwiftUI
import WebKit

struct BrowserRootView: View {
    @StateObject private var session = BrowserAgentSession()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            BrowserWebViewContainer(webView: session.webView)
            Divider()
            stepLog
        }
        .navigationTitle("Browser")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            composer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    session.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!session.canGoBack)

                Button {
                    session.goForward()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!session.canGoForward)

                TextField("Enter URL", text: $session.addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        session.submitAddress()
                    }

                Button("Go") {
                    session.submitAddress()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    session.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }

            HStack(spacing: 12) {
                Label(session.runState.title, systemImage: session.runState.isRunning ? "bolt.circle.fill" : "circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(session.runState.isRunning ? Color.accentColor : Color.primary)

                if !session.currentURLString.isEmpty {
                    Text(session.currentURLString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if session.canStartPictureInPicture {
                    Button(session.pipController.isActive ? "Stop PiP" : "PiP") {
                        if session.pipController.isActive {
                            session.stopPictureInPicture()
                        } else {
                            session.startPictureInPicture()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                BrowserPiPSourceAnchorView(controller: session.pipController)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }

            if let lastError = session.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Ask the browser agent", text: $session.agentPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            HStack {
                Text(session.runState.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button(session.runState.isRunning ? "Stop" : "Run") {
                    if session.runState.isRunning {
                        session.stopAgent()
                    } else {
                        session.runAgent()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var stepLog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !session.taskState.goal.isEmpty {
                    BrowserTaskStateCard(taskState: session.taskState)
                }
                ForEach(session.logEntries.suffix(10)) { entry in
                    BrowserLogCard(entry: entry)
                }
            }
            .padding()
        }
        .frame(height: 220)
        .background(Color(.secondarySystemBackground))
    }
}

private struct BrowserWebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct BrowserLogCard: View {
    let entry: BrowserAgentLogEntry

    private var tint: Color {
        switch entry.kind {
        case .decision:
            return .blue
        case .action:
            return .orange
        case .result:
            return .green
        case .error:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(entry.step)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(entry.detail)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BrowserTaskStateCard: View {
    let taskState: BrowserAgentTaskState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task State")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(taskState.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            Text(taskState.goal)
                .font(.footnote.weight(.medium))

            if !taskState.pendingObjective.isEmpty {
                Text("Next: \(taskState.pendingObjective)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let page = taskState.currentPage,
               !page.url.isEmpty || !page.title.isEmpty {
                Text("Page: \(page.title.isEmpty ? page.url : page.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let lastAction = taskState.lastAction {
                Text("Last action: \(lastAction.summary) · \(lastAction.outcome.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let milestone = taskState.completedMilestones.last {
                Text("Completed: \(milestone)")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            }

            if let failure = taskState.knownFailures.last {
                Text("Latest issue: \(failure)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusTint: Color {
        switch taskState.status {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

#Preview {
    BrowserRootView()
}
