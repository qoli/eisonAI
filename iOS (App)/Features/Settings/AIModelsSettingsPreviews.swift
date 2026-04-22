import Drops
import SwiftUI

#Preview("AI Models") {
    NavigationStack {
        AIModelsSettingsView()
    }
}

#Preview("MLX Download Style") {
    MLXModelsDownloadStylePreview()
}

#Preview("MLX Family Index") {
    NavigationStack {
        MLXCuratedFamilyIndexPreview()
    }
}

#Preview("Manage Models Downloading") {
    NavigationStack {
        MLXManageModelsDownloadingPreview()
    }
}

#Preview("Drops States") {
    DropsDebugView()
}

#Preview("MLX Family Detail") {
    NavigationStack {
        MLXCuratedFamilyDetailPreview()
    }
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

private struct MLXCuratedFamilyIndexPreview: View {
    private let group = MLXCuratedModelGroup(
        id: "lfm2_5",
        title: "LFM 2.5",
        summary: "Small Liquid AI models that stay lightweight while covering chat, reasoning, Japanese, and vision use cases.",
        models: [
            MLXCuratedModel(
                id: "lfm2_5-1_2b-instruct-4bit",
                title: "LFM 2.5 (1.2B Instruct)",
                repoID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
                summary: "A lightweight general chat model focused on fast on-device instruction following."
            ),
            MLXCuratedModel(
                id: "lfm2_5-1_2b-thinking-4bit",
                title: "LFM 2.5 (1.2B Thinking)",
                repoID: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
                summary: "A small reasoning-oriented variant for users who want more deliberate answers without leaving the lightweight tier."
            ),
            MLXCuratedModel(
                id: "lfm2_5-vl-1_6b-4bit",
                title: "LFM 2.5 VL (1.6B)",
                repoID: "mlx-community/LFM2.5-VL-1.6B-4bit",
                summary: "A compact vision-language model for image-aware prompts while staying in the lightweight local range."
            )
        ]
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MLXLibraryHeroCard(
                    installedCount: 1,
                    selectedModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
                    deviceRAMGiB: 6
                )

                MLXSectionTitle(
                    title: "Models",
                    subtitle: "Choose a model family first. The next page shows the actual models in that family."
                )

                MLXCuratedGroupCard(
                    group: group,
                    installedCount: 1,
                    selectedModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("MLX Models")
    }
}

private struct MLXCuratedFamilyDetailPreview: View {
    private let group = MLXCuratedModelGroup(
        id: "lfm2_5",
        title: "LFM 2.5",
        summary: "Small Liquid AI models that stay lightweight while covering chat, reasoning, Japanese, and vision use cases.",
        models: [
            MLXCuratedModel(
                id: "lfm2_5-1_2b-instruct-4bit",
                title: "LFM 2.5 (1.2B Instruct)",
                repoID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
                summary: "A lightweight general chat model focused on fast on-device instruction following."
            ),
            MLXCuratedModel(
                id: "lfm2_5-1_2b-thinking-4bit",
                title: "LFM 2.5 (1.2B Thinking)",
                repoID: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
                summary: "A small reasoning-oriented variant for users who want more deliberate answers without leaving the lightweight tier."
            ),
            MLXCuratedModel(
                id: "lfm2_5-vl-1_6b-4bit",
                title: "LFM 2.5 VL (1.6B)",
                repoID: "mlx-community/LFM2.5-VL-1.6B-4bit",
                summary: "A compact vision-language model for image-aware prompts while staying in the lightweight local range."
            )
        ]
    )

    var body: some View {
        MLXCuratedGroupDetailPage(
            group: group,
            selectedModelID: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            rows: [
                MLXCuratedModelRowContext(
                    curatedModel: group.models[0],
                    metadataLine: "text-generation · 659 MB · ~1.2B · updated recently",
                    recommendation: .recommended,
                    isInstalled: true,
                    isSelected: true,
                    job: nil,
                    isInstallDisabled: false,
                    onSelect: {},
                    onInstall: {},
                    onCancelDownload: {},
                    onDismissJob: {}
                ),
                MLXCuratedModelRowContext(
                    curatedModel: group.models[1],
                    metadataLine: "text-generation · 659 MB · ~1.2B · updated recently",
                    recommendation: .caution,
                    isInstalled: false,
                    isSelected: false,
                    job: nil,
                    isInstallDisabled: false,
                    onSelect: {},
                    onInstall: {},
                    onCancelDownload: {},
                    onDismissJob: {}
                ),
                MLXCuratedModelRowContext(
                    curatedModel: group.models[2],
                    metadataLine: "image-text-to-text · 1.49 GB · updated recently",
                    recommendation: .recommended,
                    isInstalled: false,
                    isSelected: false,
                    job: nil,
                    isInstallDisabled: false,
                    onSelect: {},
                    onInstall: {},
                    onCancelDownload: {},
                    onDismissJob: {}
                )
            ]
        )
    }
}

private struct MLXManageModelsDownloadingPreview: View {
    private let installedCatalogModel = MLXCatalogModel(
        id: "mlx-community/Qwen3-1.7B-4bit",
        pipelineTag: "text-generation",
        baseModel: "Qwen/Qwen3-1.7B",
        lastModified: .now.addingTimeInterval(-172_800),
        estimatedParameterCount: 1_700_000_000,
        rawSafeTensorTotal: 1_050_000_000
    )

    private let downloadingCatalogModel = MLXCatalogModel(
        id: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
        pipelineTag: "text-generation",
        baseModel: "LiquidAI/LFM2.5-1.2B-Thinking",
        lastModified: .now.addingTimeInterval(-86_400),
        estimatedParameterCount: 1_200_000_000,
        rawSafeTensorTotal: 659_000_000
    )

    private let activeJob: MLXDownloadJob
    private let groups: [MLXCuratedModelGroup]
    private let selectedModelID = "mlx-community/Qwen3-1.7B-4bit"

    init() {
        self.activeJob = MLXDownloadJob(
            taskIdentifier: "preview-manage-models-download",
            modelID: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
            displayName: "LFM2.5-1.2B-Thinking-4bit",
            source: .catalog,
            state: .running,
            completedUnitCount: 182,
            totalUnitCount: 1024,
            fractionCompleted: 0.18,
            autoSelectOnCompletion: true,
            catalogModel: downloadingCatalogModel
        )
        self.groups = MLXCuratedModelGroupsLoader.load()
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    Form {
                        Section {
                            MLXInstalledModelRow(
                                model: InstalledMLXModel(model: installedCatalogModel),
                                metadataLine: "text-generation · ~1.7B · 2d ago",
                                isSelected: true,
                                isBusy: false,
                                onSelect: {}
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {}
                            }
                        }
                    }
                    .navigationTitle("Installed Models")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Installed Models List")
                            .foregroundStyle(.primary)
                        Text("1 installed · Selected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Installed Models")
            } footer: {
                Text("Downloading \(activeJob.modelID)…")
                    .foregroundStyle(.secondary)
            }

            Section {
                MLXActiveDownloadBanner(job: activeJob, onCancel: {})

                ForEach(groups) { group in
                    NavigationLink {
                        MLXCuratedGroupDetailPage(
                            group: group,
                            selectedModelID: selectedModelID,
                            rows: previewRows(for: group)
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .foregroundStyle(.primary)
                            Text(groupSummary(group))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Choose a model family first. The next page shows the actual models in that family.")
            }
        }
        .navigationTitle("Manage Models")
        .navigationBarTitleDisplayMode(.large)
    }

    private func groupSummary(_ group: MLXCuratedModelGroup) -> String {
        var parts = [group.summary, "\(group.models.count) model" + (group.models.count == 1 ? "" : "s")]

        if group.models.contains(where: { $0.repoID == selectedModelID }) {
            parts.append("1 installed")
            parts.append("Selected")
        } else if group.models.contains(where: { $0.repoID == activeJob.modelID }) {
            parts.append(activeJob.progressText)
        }

        return parts.joined(separator: " · ")
    }

    private func previewRows(for group: MLXCuratedModelGroup) -> [MLXCuratedModelRowContext] {
        group.models.map { model in
            let isSelected = model.repoID == selectedModelID
            let isDownloading = model.repoID == activeJob.modelID
            let metadataLine: String

            if isSelected {
                metadataLine = "text-generation · 1.05 GB · ~1.7B · updated recently"
            } else if isDownloading {
                metadataLine = "text-generation · 659 MB · ~1.2B · updated recently"
            } else {
                metadataLine = "text-generation · 659 MB · ~1.2B · updated recently"
            }

            return MLXCuratedModelRowContext(
                curatedModel: model,
                metadataLine: metadataLine,
                recommendation: isSelected || isDownloading ? .recommended : .caution,
                isInstalled: isSelected,
                isSelected: isSelected,
                job: isDownloading ? activeJob : nil,
                isInstallDisabled: isDownloading,
                onSelect: {},
                onInstall: {},
                onCancelDownload: {},
                onDismissJob: {}
            )
        }
    }
}
