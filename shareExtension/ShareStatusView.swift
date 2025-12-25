import Combine
import SwiftUI

private struct IconFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

@MainActor
final class ShareStatusViewModel: ObservableObject {
    @Published var status: String
    @Published var detail: String?
    @Published var isMinimized: Bool
    @Published var bounceTrigger: Bool

    init(status: String = "Processing…", detail: String? = "Please wait") {
        self.status = status
        self.detail = detail
        self.isMinimized = false
        self.bounceTrigger = false
    }
}

struct ShareStatusView: View {
    @ObservedObject var viewModel: ShareStatusViewModel
    @State private var iconFrame: CGRect = .zero

    private let windowSize = CGSize(width: 280, height: 180)
    private let minimizeDuration = 0.35
    private let minimizeScale: CGFloat = 0.08

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                windowView
                    .frame(width: windowSize.width, height: windowSize.height)
                    .scaleEffect(viewModel.isMinimized ? minimizeScale : 1.0)
                    .opacity(viewModel.isMinimized ? 0.0 : 1.0)
                    .position(viewModel.isMinimized ? targetPosition(in: proxy.size) : centerPosition(in: proxy.size))
                    .animation(minimizeAnimation, value: viewModel.isMinimized)

                VStack {
                    Spacer(minLength: 0)
                    iconView
                        .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "container")
            .onPreferenceChange(IconFrameKey.self) { iconFrame = $0 }
            .background(Color(UIColor.systemBackground))
        }
    }

    private var windowView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.2))
                )

            VStack(spacing: 10) {
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
            }
            .padding(16)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    private var iconView: some View {
        Image(systemName: "macwindow.stack")
            .font(.system(size: 28))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
            )
            .background(
                GeometryReader { iconProxy in
                    Color.clear
                        .preference(key: IconFrameKey.self, value: iconProxy.frame(in: .named("container")))
                }
            )
            .symbolEffect(.bounce.down, value: viewModel.bounceTrigger)
    }

    private var minimizeAnimation: Animation {
        .easeInOut(duration: minimizeDuration)
    }

    private func centerPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.45)
    }

    private func targetPosition(in size: CGSize) -> CGPoint {
        if iconFrame == .zero {
            return centerPosition(in: size)
        }
        return CGPoint(x: iconFrame.midX, y: iconFrame.midY)
    }
}
