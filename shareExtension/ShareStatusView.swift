import Combine
import SwiftUI

@MainActor
final class ShareStatusViewModel: ObservableObject {
    @Published var status: String
    @Published var detail: String?

    init(status: String = "Processing…", detail: String? = "Please wait") {
        self.status = status
        self.detail = detail
    }
}

struct ShareStatusView: View {
    @ObservedObject var viewModel: ShareStatusViewModel

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(viewModel.status)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            if let detail = viewModel.detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}
