import SwiftUI

@MainActor
final class MLXDownloadsPresentationController: ObservableObject {
    static let shared = MLXDownloadsPresentationController()

    @Published var isPresented = false
    @Published var debugJob: MLXDownloadJob?

    func present(debugJob: MLXDownloadJob? = nil) {
        self.debugJob = debugJob
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        debugJob = nil
    }
}

struct MLXDownloadsSheetView: View {
    @ObservedObject private var coordinator = MLXDownloadCoordinator.shared
    @ObservedObject private var presentation = MLXDownloadsPresentationController.shared

    var body: some View {
        NavigationStack {
            Group {
                if let job = presentation.debugJob ?? coordinator.currentJob {
                    downloadContent(job: job)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        presentation.dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func downloadContent(job: MLXDownloadJob) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(job.displayName)
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 8) {
                        statusChip(for: job.state)
                        sourceChip(for: job.source)
                    }

                    if job.isActive {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(job.progressText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView(value: progressValue(for: job))
                        }
                    } else if let errorMessage = job.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(job.state == .completed ? .secondary : .secondary)
                    } else {
                        Text(job.state.displayLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Current Job")
            }

            Section {
                if job.isActive {
                    Button("Cancel Download", role: .destructive) {
                        Task {
                            await coordinator.cancelCurrentJob()
                        }
                    }
                } else {
                    Button("Clear Status") {
                        coordinator.dismissCurrentJob()
                    }
                }
            } header: {
                Text("Actions")
            } footer: {
                Text(footerText(for: job))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Active Downloads",
            systemImage: "arrow.down.circle",
            description: Text("MLX download progress and results will appear here.")
        )
    }

    private func progressValue(for job: MLXDownloadJob) -> Double {
        if job.totalUnitCount > 0 {
            return min(1, max(0, Double(job.completedUnitCount) / Double(max(job.totalUnitCount, 1))))
        }
        return min(1, max(0, job.fractionCompleted))
    }

    private func footerText(for job: MLXDownloadJob) -> String {
        switch job.state {
        case .queued, .running, .finishing:
            return "This is a foreground MLX download. You can leave this sheet open or dismiss it and keep watching progress from Drops."
        case .completed:
            return "The model is installed. You can now select it from Manage Models."
        case .failed:
            return "The download ended with an error. Retry it from Manage Models."
        case .cancelled:
            return "The download was cancelled. You can restart it from Manage Models."
        }
    }

    private func statusChip(for state: MLXDownloadJob.State) -> some View {
        Text(state.displayLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusTint(for: state).opacity(0.12), in: Capsule())
            .foregroundStyle(statusTint(for: state))
    }

    private func sourceChip(for source: MLXDownloadJob.Source) -> some View {
        Text(source == .catalog ? "Catalog" : "Custom Repo")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func statusTint(for state: MLXDownloadJob.State) -> Color {
        switch state {
        case .queued, .running, .finishing:
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
