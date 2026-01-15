import MarkdownUI
import SwiftUI

struct ClipboardKeyPointSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ClipboardKeyPointViewModel
    @State private var showsTokenOverlay: Bool = true
    private let showsErrorAlert: Bool

    init(
        input: KeyPointInput,
        saveMode: ClipboardKeyPointViewModel.SaveMode = .createNew,
        showsErrorAlert: Bool = false
    ) {
        _model = StateObject(wrappedValue: ClipboardKeyPointViewModel(input: input, saveMode: saveMode))
        self.showsErrorAlert = showsErrorAlert
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Markdown(model.output.isEmpty ? "_" : model.output.thinkTagstoMarkdonw())
                    .markdownTheme(.librarySummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .ifMacCatalyst({ view in
                view.mask {
                    LinearGradient(
                        colors: [.clear, .black, .black, .black, .black],
                        startPoint: UnitPoint(x: 0.5, y: 0),
                        endPoint: UnitPoint(x: 0.5, y: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            })
            .overlay(alignment: .top) {
                if platform == .macCatalyst {
                    Text("Cognitive Index")
                        .font(.headline)
                        .padding(.top)
                }
            }
            .overlay(alignment: .bottom) { overlayView() }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .defaultScrollAnchor(.bottom)
            .ifIPad({ view in
                view.navigationTitle("Cognitive Index")
            })
            .ifIPhone({ view in
                view.navigationTitle("Cognitive Index")
            })
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent() }
            // KEYPOINT_CLIPBOARD_FLOW: auto-starts view model pipeline on sheet appear
            .task {
                model.run()
            }
            .alert("Generation Failed", isPresented: errorAlertBinding) {
                Button("OK") {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "Unknown error.")
            }
            .onChange(of: model.shouldDismiss) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
            .onChange(of: model.status) { _, newValue in
                print("→ New Status ...", newValue)
                if newValue == "Chunk" {
                    print("→ Chunk ...", model.chunkStatus)
                }
            }
        }
    }

    @ViewBuilder func overlayView() -> some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 2) {
                    Text(model.status.isEmpty ? "—" : model.status)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    Spacer()
                }

                Divider()

                HStack(spacing: 2) {
                    Text("Token")
                        .opacity(0.5)

                    Spacer()

                    Text(tokenEstimateLabel)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.secondary)

                if model.chunkStatus != "" {
                    HStack(spacing: 2) {
                        Text("Chunk")
                            .opacity(0.5)

                        Spacer()

                        Text(model.chunkStatus)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .fontDesign(.rounded)
            .font(.caption2)
            .multilineTextAlignment(.trailing)
            .frame(width: 96)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .ifMacCatalyst({ view in
                view
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(uiColor: UIColor.secondarySystemBackground).opacity(0.86))
                    }
            })
            .ifIPad({ view in
                view.glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            })
            .ifIPhone({ view in
                view.glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            })
//            .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            .opacity(showsTokenOverlay ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showsTokenOverlay)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                model.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) {
            IridescentOrbView()
        }

        ToolbarItem(placement: .bottomBar) {
            Spacer()
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsTokenOverlay.toggle()
                }
            } label: {
                Label(tokenEstimateLabel, systemImage: tokenEstimateLabelImage)
            }
            .accessibilityLabel("Toggle token estimate")
        }
    }

    private var tokenEstimateLabelImage: String {
        if model.chunkStatus == "" {
            return "quote.opening"
        } else {
            return "text.quote"
        }
    }

    private var tokenEstimateLabel: String {
        guard let tokenEstimate = model.tokenEstimate else {
            return "—"
        }
        return "~\(tokenEstimate)"
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { showsErrorAlert && model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
}
