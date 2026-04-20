import Drops
import SwiftUI

struct DropsDebugView: View {
    private enum Route: Hashable {
        case detail
    }

    @State private var path: [Route] = [.detail]
    @State private var progress: Double = 0.18
    @StateObject private var downloadsPresentation = MLXDownloadsPresentationController.shared

    private let observedModelID = "mlx-community/Qwen3-1.7B-4bit"
    private let observedModelName = "Qwen3-1.7B-4bit"

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Models") {
                    NavigationLink(value: Route.detail) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Models")
                                .foregroundStyle(.primary)
                            Text("Preview the active download notification in a pushed screen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Route.self) { _ in
                detailPage
            }
        }
    }

    private var detailPage: some View {
        List {
            Section {
                Text("This page helps inspect how Drops overlaps the back button and the top trailing action.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Preview")
            }

            Section {
                Button("Show Queued") {
                    prepareDebugJob(state: .queued)
                    Drops.show(queuedDrop)
                }

                Button("Show Downloading") {
                    prepareDebugJob(state: .running)
                    Drops.show(downloadingDrop(progress: progress))
                }

                Button("Advance Download") {
                    progress = min(progress + 0.22, 0.96)
                    prepareDebugJob(state: .running)
                    Drops.show(downloadingDrop(progress: progress))
                }

                Button("Show Finalizing") {
                    prepareDebugJob(state: .finishing)
                    Drops.show(finalizingDrop)
                }

                Button("Show Completed") {
                    prepareDebugJob(state: .completed)
                    Drops.show(completedDrop)
                }

                Button("Show Failed") {
                    prepareDebugJob(state: .failed)
                    Drops.show(failedDrop)
                }

                Button("Hide Current Drop") {
                    Drops.hideCurrent()
                }
            } header: {
                Text("States")
            } footer: {
                Text("Downloading and finalizing drops keep the same id so they update in place.")
            }

            Section {
                Button("Show Logged Queue") {
                    downloadsPresentation.debugJob = makeObservedJob(state: .queued)
                    Drops.show(observedQueuedDrop)
                }

                Button("Show Logged Downloading") {
                    downloadsPresentation.debugJob = makeObservedJob(state: .running)
                    Drops.show(observedDownloadingDrop)
                }

                Button("Replay Logged Queue -> Downloading") {
                    replayObservedDownloadSequence()
                }

                Button("Show Logged Cancelled") {
                    downloadsPresentation.debugJob = makeObservedJob(
                        state: .cancelled,
                        errorMessage: "Cancelled by user."
                    )
                    Drops.show(observedCancelledDrop)
                }
            } header: {
                Text("Observed Logs")
            } footer: {
                Text("These actions mirror the real MLX log sequence: queued notification, then an indeterminate downloading drop with the same Qwen subtitle.")
            }
        }
        .navigationTitle("Drops Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {}
            }
        }
    }

    private var queuedDrop: Drop {
        Drop(
            title: "Model queued",
            subtitle: "LFM 2.5 (1.2B Thinking) will start downloading shortly.",
            icon: UIImage(systemName: "clock.arrow.circlepath"),
            action: .init {
                downloadsPresentation.present(debugJob: makeDebugJob(state: .queued))
            },
            position: .top,
            duration: 2.5,
            accentColor: .systemBlue
        )
    }

    private func downloadingDrop(progress: Double) -> Drop {
        Drop(
            title: "Downloading model",
            subtitle: "LFM 2.5 (1.2B Thinking) · \(Int(progress * 100))%",
            icon: UIImage(systemName: "arrow.down.circle"),
            action: .init {
                downloadsPresentation.present(debugJob: makeDebugJob(state: .running, fractionCompleted: progress))
            },
            position: .top,
            duration: .untilHidden,
            accentColor: .systemBlue,
            id: "preview-download",
            progress: .determinate(progress)
        )
    }

    private var finalizingDrop: Drop {
        Drop(
            title: "Finalizing model",
            subtitle: "Preparing files before install completes.",
            icon: UIImage(systemName: "shippingbox"),
            action: .init {
                downloadsPresentation.present(
                    debugJob: makeDebugJob(
                        state: .finishing,
                        completedUnitCount: 1024,
                        totalUnitCount: 1024,
                        fractionCompleted: 1
                    )
                )
            },
            position: .top,
            duration: .untilHidden,
            accentColor: .systemBlue,
            id: "preview-download",
            progress: .indeterminate
        )
    }

    private var completedDrop: Drop {
        Drop(
            title: "Model ready",
            subtitle: "LFM 2.5 (1.2B Thinking) is installed.",
            icon: UIImage(systemName: "checkmark.circle.fill"),
            action: .init(icon: UIImage(systemName: "arrow.right")) {
                downloadsPresentation.present(
                    debugJob: makeDebugJob(
                        state: .completed,
                        completedUnitCount: 1024,
                        totalUnitCount: 1024,
                        fractionCompleted: 1
                    )
                )
            },
            position: .top,
            duration: 3.0,
            accentColor: .systemGreen
        )
    }

    private var failedDrop: Drop {
        Drop(
            title: "Download failed",
            subtitle: "The connection was interrupted. Try again.",
            icon: UIImage(systemName: "exclamationmark.triangle.fill"),
            action: .init(icon: UIImage(systemName: "arrow.clockwise")) {
                downloadsPresentation.present(
                    debugJob: makeDebugJob(
                        state: .failed,
                        errorMessage: "The connection was interrupted. Try again."
                    )
                )
            },
            position: .top,
            duration: .untilHidden,
            accentColor: .systemRed
        )
    }

    private var observedQueuedDrop: Drop {
        Drop(
            title: "Queued MLX Download",
            subtitle: observedModelName,
            icon: UIImage(systemName: "clock.badge"),
            action: .init {
                downloadsPresentation.present(debugJob: makeObservedJob(state: .queued))
            },
            position: .top,
            duration: 1.4
        )
    }

    private var observedDownloadingDrop: Drop {
        Drop(
            title: "Downloading MLX Model",
            subtitle: observedModelName,
            icon: UIImage(systemName: "arrow.down.circle"),
            action: .init {
                downloadsPresentation.present(debugJob: makeObservedJob(state: .running))
            },
            position: .top,
            duration: .untilHidden,
            id: "mlx-download-debug-observed",
            progress: .indeterminate
        )
    }

    private var observedCancelledDrop: Drop {
        Drop(
            title: "MLX Download Cancelled",
            subtitle: "Cancelled by user.",
            icon: UIImage(systemName: "xmark.circle.fill"),
            action: .init {
                downloadsPresentation.present(
                    debugJob: makeObservedJob(
                        state: .cancelled,
                        errorMessage: "Cancelled by user."
                    )
                )
            },
            position: .top,
            duration: 2.4
        )
    }

    private func prepareDebugJob(state: MLXDownloadJob.State) {
        switch state {
        case .queued:
            downloadsPresentation.debugJob = makeDebugJob(state: .queued)
        case .running:
            downloadsPresentation.debugJob = makeDebugJob(state: .running, fractionCompleted: progress)
        case .finishing:
            downloadsPresentation.debugJob = makeDebugJob(
                state: .finishing,
                completedUnitCount: 1024,
                totalUnitCount: 1024,
                fractionCompleted: 1
            )
        case .completed:
            downloadsPresentation.debugJob = makeDebugJob(
                state: .completed,
                completedUnitCount: 1024,
                totalUnitCount: 1024,
                fractionCompleted: 1
            )
        case .failed:
            downloadsPresentation.debugJob = makeDebugJob(
                state: .failed,
                errorMessage: "The connection was interrupted. Try again."
            )
        case .cancelled:
            downloadsPresentation.debugJob = makeDebugJob(
                state: .cancelled,
                errorMessage: "Cancelled by user."
            )
        }
    }

    private func makeDebugJob(
        state: MLXDownloadJob.State,
        completedUnitCount: Int64 = 182,
        totalUnitCount: Int64 = 1024,
        fractionCompleted: Double = 0.18,
        errorMessage: String? = nil
    ) -> MLXDownloadJob {
        MLXDownloadJob(
            taskIdentifier: "drops-debug-job",
            modelID: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
            displayName: "LFM 2.5 (1.2B Thinking)",
            source: .catalog,
            state: state,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            fractionCompleted: fractionCompleted,
            errorMessage: errorMessage,
            autoSelectOnCompletion: true
        )
    }

    private func makeObservedJob(
        state: MLXDownloadJob.State,
        errorMessage: String? = nil
    ) -> MLXDownloadJob {
        MLXDownloadJob(
            taskIdentifier: "drops-debug-observed-job",
            modelID: observedModelID,
            displayName: observedModelName,
            source: .catalog,
            state: state,
            completedUnitCount: 0,
            totalUnitCount: 0,
            fractionCompleted: 0,
            errorMessage: errorMessage,
            autoSelectOnCompletion: true
        )
    }

    private func replayObservedDownloadSequence() {
        downloadsPresentation.debugJob = makeObservedJob(state: .queued)
        Drops.show(observedQueuedDrop)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            downloadsPresentation.debugJob = makeObservedJob(state: .running)
            Drops.show(observedDownloadingDrop)
        }
    }
}

#Preview("Drops Debug") {
    DropsDebugView()
}
