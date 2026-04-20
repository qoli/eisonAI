import Drops
import SwiftUI

struct DropsDebugView: View {
    private enum Route: Hashable {
        case detail
    }

    @State private var path: [Route] = [.detail]
    @State private var progress: Double = 0.18

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
                    Drops.show(queuedDrop)
                }

                Button("Show Downloading") {
                    Drops.show(downloadingDrop(progress: progress))
                }

                Button("Advance Download") {
                    progress = min(progress + 0.22, 0.96)
                    Drops.show(downloadingDrop(progress: progress))
                }

                Button("Show Finalizing") {
                    Drops.show(finalizingDrop)
                }

                Button("Show Completed") {
                    Drops.show(completedDrop)
                }

                Button("Show Failed") {
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
                Drops.hideCurrent()
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
                Drops.hideCurrent()
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
                Drops.hideCurrent()
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
                Drops.hideCurrent()
            },
            position: .top,
            duration: .untilHidden,
            accentColor: .systemRed
        )
    }
}

#Preview("Drops Debug") {
    DropsDebugView()
}
