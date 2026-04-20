import SwiftUI

struct MLXLibraryHeroCard: View {
    let installedCount: Int
    let selectedModelID: String?
    let deviceRAMGiB: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MLX Models")
                .font(.title2.weight(.semibold))

            Text("Start with a smaller curated list instead of the full catalog. This makes local models easier to browse and less overwhelming for most users.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                MLXLibraryPill(
                    title: "\(installedCount)",
                    subtitle: installedCount == 1 ? "Installed" : "Installed Models",
                    tint: .blue
                )
                MLXLibraryPill(
                    title: String(format: "%.0f GB", deviceRAMGiB.rounded()),
                    subtitle: "Device RAM",
                    tint: .orange
                )
            }

            if let selectedModelID {
                Label(selectedModelID, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            } else {
                Label("No MLX model selected yet", systemImage: "circle.dashed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }
}

struct MLXLibraryPill: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MLXSectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MLXTagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct MLXCuratedGroupCard: View {
    let group: MLXCuratedModelGroup
    let installedCount: Int
    let selectedModelID: String?

    private var previewTitles: [String] {
        Array(group.models.prefix(3).map(\.title))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(group.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
                MLXTagChip(text: "\(group.models.count) model\(group.models.count == 1 ? "" : "s")")

                if installedCount > 0 {
                    MLXTagChip(text: "\(installedCount) installed")
                }
            }

            if !previewTitles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(previewTitles, id: \.self) { title in
                            MLXTagChip(text: title)
                        }
                    }
                }
            }

            if let selectedModelID,
               group.models.contains(where: { $0.repoID == selectedModelID })
            {
                Label("Selected model is in this family", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }
}

struct MLXCuratedModelRow: View {
    let curatedModel: MLXCuratedModel
    let metadataLine: String?
    let recommendation: MLXCatalogModel.Recommendation?
    let isInstalled: Bool
    let isSelected: Bool
    let job: MLXDownloadJob?
    let isInstallDisabled: Bool
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onCancelDownload: () -> Void
    let onDismissJob: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(curatedModel.title)
                        .font(.headline.weight(.semibold))

                    Text(curatedModel.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let metadataLine, !metadataLine.isEmpty {
                        Text(metadataLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                trailingControl
            }

            HStack(spacing: 8) {
                if let recommendation {
                    MLXRecommendationBadge(recommendation: recommendation)
                }

                if isInstalled {
                    MLXSelectionBadge(isSelected: isSelected)
                }
            }

            if let job {
                MLXDownloadJobStatusView(
                    job: job,
                    onCancel: onCancelDownload,
                    onDismiss: onDismissJob
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var trailingControl: some View {
        if let job {
            if job.isActive {
                VStack(alignment: .trailing, spacing: 6) {
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
                .buttonStyle(.borderedProminent)
                .disabled(isSelected)
        } else {
            Button("Install", action: onInstall)
                .buttonStyle(.borderedProminent)
                .disabled(isInstallDisabled)
        }
    }
}

struct MLXSelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Label(isSelected ? "Selected" : "Installed", systemImage: isSelected ? "checkmark.circle.fill" : "arrow.down.circle.fill")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isSelected ? Color.green : Color.blue).opacity(0.12))
            .foregroundStyle(isSelected ? .green : .blue)
            .clipShape(Capsule())
    }
}

struct MLXCuratedGroupDetailPage: View {
    let group: MLXCuratedModelGroup
    let selectedModelID: String?
    let rows: [MLXCuratedModelRowContext]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MLXSectionTitle(
                    title: group.title,
                    subtitle: group.summary
                )

                if let selectedModelID,
                   group.models.contains(where: { $0.repoID == selectedModelID })
                {
                    Label("Your selected MLX model is in this family.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                ForEach(rows) { row in
                    MLXCuratedModelRow(
                        curatedModel: row.curatedModel,
                        metadataLine: row.metadataLine,
                        recommendation: row.recommendation,
                        isInstalled: row.isInstalled,
                        isSelected: row.isSelected,
                        job: row.job,
                        isInstallDisabled: row.isInstallDisabled,
                        onSelect: row.onSelect,
                        onInstall: row.onInstall,
                        onCancelDownload: row.onCancelDownload,
                        onDismissJob: row.onDismissJob
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MLXCuratedModelRowContext: Identifiable {
    let curatedModel: MLXCuratedModel
    let metadataLine: String?
    let recommendation: MLXCatalogModel.Recommendation?
    let isInstalled: Bool
    let isSelected: Bool
    let job: MLXDownloadJob?
    let isInstallDisabled: Bool
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onCancelDownload: () -> Void
    let onDismissJob: () -> Void

    var id: String { curatedModel.id }
}

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
