import SwiftUI

struct ClipboardKeyPointSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ClipboardKeyPointViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.status)
                        .foregroundStyle(.secondary)

                    if !model.sourceDescription.isEmpty {
                        Text(model.sourceDescription)
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
            }
            .padding()
            .navigationTitle("Key-point (Clipboard)")
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
                            model.runFromClipboard()
                        }
                    }
                }
            }
            .task {
                model.runFromClipboard()
            }
            .onChange(of: model.shouldDismiss) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }
}
