import AVFoundation
import Combine
import SwiftUI
import UIKit

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
    @State private var progress = 0.0
    @State private var offCircleProgressView = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ZStack {
            Color.black

            MeshGradientOverview()

            Circle()
                .fill(Color(red: 1, green: 201.0 / 255.0, blue: 63.0 / 255.0))
                .frame(width: 22 + 6, height: 22 + 6)
                .opacity(offCircleProgressView ? 1 : 0)

            CircleProgressView(value: progress)
                .frame(width: 22, height: 22)
                .opacity(offCircleProgressView ? 0.0 : 1)

            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.black)
                .opacity(offCircleProgressView ? 1 : 0)
        }
        .ignoresSafeArea(.all)
        .task {
            progress = 0

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                playEmbeddedAudio()
                progress = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeInOut) {
                    offCircleProgressView = true
                }
            }
        }
    }

    private func playEmbeddedAudio() {
        guard let asset = NSDataAsset(name: "audio") else {
            print("Missing audio asset named \"audio\".")
            return
        }

        do {
            let player = try AVAudioPlayer(data: asset.data)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            print("Failed to play embedded audio: \(error)")
        }
    }
}

private struct CircleProgressView: View {
    static let progressColor = Color(
        red: 1,
        green: 201.0 / 255.0,
        blue: 63.0 / 255.0
    )

    // The current progress value in the range 0...1
    var value: Double

    private let lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Self.progressColor.opacity(0.2), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0.0, to: clampedProgress(value))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .foregroundStyle(Self.progressColor)
                .rotationEffect(.degrees(-90))
                .animation(
                    .easeInOut(duration: 0.25),
                    value: clampedProgress(value)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text("\(Int(clampedProgress(value) * 100))%"))
    }

    private func clampedProgress(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
