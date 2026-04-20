import SwiftUI

#Preview("AI Models") {
    NavigationStack {
        AIModelsSettingsView()
    }
}

#Preview("MLX Download Style") {
    MLXModelsDownloadStylePreview()
}

private struct MLXModelsDownloadStylePreview: View {
    private let activeJob = MLXDownloadJob(
        taskIdentifier: "preview-task",
        modelID: "mlx-community/translategemma-4b-it-4bit_immersive-translate",
        displayName: "translategemma-4b-it-4bit_immersive-translate",
        source: .catalog,
        state: .running,
        completedUnitCount: 182,
        totalUnitCount: 1024,
        fractionCompleted: 0.18,
        autoSelectOnCompletion: true,
        catalogModel: MLXCatalogModel(
            id: "mlx-community/translategemma-4b-it-4bit_immersive-translate",
            pipelineTag: "text-generation",
            baseModel: "google/translategemma-4b-it",
            lastModified: .now.addingTimeInterval(-86_400),
            estimatedParameterCount: 4_000_000_000,
            rawSafeTensorTotal: 606_600_000
        )
    )

    private let otherModels: [MLXCatalogModel] = [
        MLXCatalogModel(
            id: "mlx-community/gemma-4-31B-it-The-DECKARD-HERETIC-UNCENSORED-Thinking-4.6bit-msq",
            pipelineTag: "image-text-to-text",
            baseModel: "google/gemma-4-31B-it",
            lastModified: .now.addingTimeInterval(-86_400),
            estimatedParameterCount: 31_000_000_000,
            rawSafeTensorTotal: 31_250_000_000
        ),
        MLXCatalogModel(
            id: "mlx-community/Qwen3.5-40B-Claude-4.6-Opus-Deckard-Heretic-Uncensored-Thinking-4.5bit-msq",
            pipelineTag: "image-text-to-text",
            baseModel: "DavidAU/Qwen3.5-27B-Deckard-PKD-Heretic-Uncensored-Thinking",
            lastModified: .now.addingTimeInterval(-86_400),
            estimatedParameterCount: 40_000_000_000,
            rawSafeTensorTotal: 39_530_000_000
        )
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("mlx-community") {
                    MLXActiveDownloadBanner(job: activeJob, onCancel: {})
                    previewCatalogRow(
                        model: activeJob.catalogModel ?? otherModels[0],
                        trailingTitle: "Downloading 18%",
                        progress: 0.18,
                        actionTitle: "Cancel Download",
                        actionRole: .destructive
                    )
                    previewCatalogRow(
                        model: otherModels[0],
                        trailingTitle: "Install",
                        progress: nil,
                        actionTitle: nil,
                        actionRole: nil
                    )
                    previewCatalogRow(
                        model: otherModels[1],
                        trailingTitle: "Install",
                        progress: nil,
                        actionTitle: nil,
                        actionRole: nil
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("MLX Models")
            .safeAreaInset(edge: .top, spacing: 12) {
                MLXDownloadToastPreview(job: activeJob)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    @ViewBuilder
    private func previewCatalogRow(
        model: MLXCatalogModel,
        trailingTitle: String,
        progress: Double?,
        actionTitle: String?,
        actionRole: ButtonRole?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(previewCatalogMetadataLine(model))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                MLXRecommendationBadge(recommendation: MLXCatalogModel.Recommendation.recommended)

                Spacer()

                if let progress {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(trailingTitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .frame(width: 96)
                    }
                } else {
                    Text(trailingTitle)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading 18%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                    if let actionTitle {
                        Button(actionTitle, role: actionRole) {}
                            .font(.footnote)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func previewCatalogMetadataLine(_ model: MLXCatalogModel) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.isAdaptive = true

        let size = model.rawSafeTensorTotal.map { formatter.string(fromByteCount: $0) } ?? "Unknown size"
        let params = model.estimatedParameterLabel
        let base = model.baseModel ?? "Unknown base"
        return [model.pipelineTag, size, params, base].joined(separator: " · ")
    }
}

private struct MLXDownloadToastPreview: View {
    let job: MLXDownloadJob

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            VStack(alignment: .center, spacing: 2) {
                Text("Downloading MLX Model")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(job.displayName) · 18%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .stroke(Color(uiColor: .tertiaryLabel).opacity(0.35), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.18)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 30, height: 30)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }
}
