import SwiftUI

struct MLXInstalledModelRow: View {
    let model: InstalledMLXModel
    let metadataLine: String
    let isSelected: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.id)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(metadataLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                if isSelected {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Button("Select", action: onSelect)
                }

                Spacer()

                if isBusy {
                    ProgressView()
                } else {
                    Button("Delete", role: .destructive, action: onDelete)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MLXCatalogModelRow: View {
    let model: MLXCatalogModel
    let metadataLine: String
    let recommendation: MLXCatalogModel.Recommendation
    let isInstalled: Bool
    let isSelected: Bool
    let job: MLXDownloadJob?
    let isInstallDisabled: Bool
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onCancelDownload: () -> Void
    let onDismissJob: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(metadataLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                MLXRecommendationBadge(recommendation: recommendation)

                Spacer()

                trailingControl
            }

            if let job {
                MLXDownloadJobStatusView(
                    job: job,
                    onCancel: onCancelDownload,
                    onDismiss: onDismissJob
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let job {
            if job.isActive {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(job.progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    MLXDownloadProgressView(job: job, compact: true)
                }
            } else {
                Text(job.progressText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } else if isInstalled {
            Button(isSelected ? "Selected" : "Select", action: onSelect)
                .disabled(isSelected)
        } else {
            Button("Install", action: onInstall)
                .disabled(isInstallDisabled)
        }
    }
}

struct MLXActiveDownloadBanner: View {
    let job: MLXDownloadJob
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Another MLX download is in progress: \(job.displayName)")
                    .foregroundStyle(.secondary)

                MLXDownloadProgressView(job: job)
            }

            Spacer()

            Button("Cancel", role: .destructive, action: onCancel)
                .font(.footnote)
        }
    }
}

struct MLXDownloadJobStatusView: View {
    let job: MLXDownloadJob
    let onCancel: () -> Void
    let onDismiss: () -> Void

    private var isError: Bool {
        job.state == .failed || job.state == .cancelled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.progressText)
                .font(.footnote)
                .foregroundStyle(isError ? .red : .secondary)

            if job.isActive {
                MLXDownloadProgressView(job: job)
            }

            if let errorMessage = job.errorMessage,
               !errorMessage.isEmpty,
               isError
            {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if job.isActive {
                Button("Cancel Download", role: .destructive, action: onCancel)
                    .font(.footnote)
            } else if isError {
                Button("Dismiss", action: onDismiss)
                    .font(.footnote)
            }
        }
    }
}

struct MLXDownloadProgressView: View {
    let job: MLXDownloadJob
    var compact = false

    var body: some View {
        if let progressValue = normalizedProgress {
            ProgressView(value: progressValue)
                .frame(width: compact ? 88 : nil)
        } else {
            ProgressView()
                .controlSize(compact ? .mini : .small)
        }
    }

    private var normalizedProgress: Double? {
        if job.totalUnitCount > 0 {
            return min(1, max(0, Double(job.completedUnitCount) / Double(max(job.totalUnitCount, 1))))
        }
        guard job.fractionCompleted > 0 else { return nil }
        return min(1, max(0, job.fractionCompleted))
    }
}

struct MLXRecommendationBadge: View {
    let recommendation: MLXCatalogModel.Recommendation

    var body: some View {
        Text(recommendation.label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.12))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch recommendation {
        case .recommended:
            return .green
        case .caution:
            return .orange
        case .likelyTooLarge:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
