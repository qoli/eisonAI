import SwiftUI

struct ClipboardKeyPointSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ClipboardKeyPointViewModel

    init(input: KeyPointInput) {
        _model = StateObject(wrappedValue: ClipboardKeyPointViewModel(input: input))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.status)
                        .foregroundStyle(.secondary)

                    if !model.pipelineStatus.isEmpty {
                        Text(model.pipelineStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let tokenEstimate = model.tokenEstimate {
                        Text("Token 長度：\(tokenEstimate)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    Text(model.output.isEmpty ? "—" : model.output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .defaultScrollAnchor(.bottom)
            }
            .padding()
            .navigationTitle("Key-point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        model.cancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.isRunning ? "Stop" : "Run") {
                        if model.isRunning {
                            model.cancel()
                        } else {
                            model.run()
                        }
                    }
                }
            }
            .task {
                model.run()
            }
            .onChange(of: model.shouldDismiss) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }
}
