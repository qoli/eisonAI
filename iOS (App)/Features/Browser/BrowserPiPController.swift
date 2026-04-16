import SwiftUI

#if os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import AVKit
import MetalKit

extension Notification.Name {
    static let browserAgentRestoreUI = Notification.Name("browserAgentRestoreUI")
}

@MainActor
final class BrowserPiPDisplayModel: ObservableObject {
    @Published var snapshot: UIImage?
    @Published var title = "Browser Agent"
    @Published var urlString = ""
    @Published var statusTitle = "Idle"
    @Published var statusDetail = "Ready for a same-tab browser task."
}

@MainActor
final class BrowserPiPController: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published private(set) var isActive = false

    let sourceView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    let displayModel = BrowserPiPDisplayModel()

    private let contentViewController = AVPictureInPictureVideoCallViewController()
    private var hostingController: UIHostingController<BrowserPiPMonitorView>?
    private var pictureInPictureController: AVPictureInPictureController?

    override init() {
        super.init()
        sourceView.isOpaque = false
        sourceView.backgroundColor = .clear
        sourceView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        configure()
    }

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported() && pictureInPictureController != nil
    }

    func update(snapshot: UIImage?, title: String, urlString: String, statusTitle: String, statusDetail: String) {
        displayModel.snapshot = snapshot
        displayModel.title = title.isEmpty ? "Browser Agent" : title
        displayModel.urlString = urlString
        displayModel.statusTitle = statusTitle
        displayModel.statusDetail = statusDetail
    }

    func start() {
        guard let pictureInPictureController else { return }
        configureAudioSession()
        pictureInPictureController.startPictureInPicture()
    }

    func stop() {
        pictureInPictureController?.stopPictureInPicture()
        deactivateAudioSession()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        deactivateAudioSession()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        NotificationCenter.default.post(name: .browserAgentRestoreUI, object: nil)
        completionHandler(true)
    }

    private func configure() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let hostingController = UIHostingController(rootView: BrowserPiPMonitorView(model: displayModel))
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController

        contentViewController.view.backgroundColor = .clear
        contentViewController.addChild(hostingController)
        hostingController.view.frame = contentViewController.view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentViewController.view.addSubview(hostingController.view)
        hostingController.didMove(toParent: contentViewController)

        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentViewController
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPictureController = controller
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

struct BrowserPiPSourceAnchorView: UIViewRepresentable {
    @ObservedObject var controller: BrowserPiPController

    func makeUIView(context: Context) -> MTKView {
        controller.sourceView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

private struct BrowserPiPMonitorView: View {
    @ObservedObject var model: BrowserPiPDisplayModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let snapshot = model.snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.black.opacity(0.85), .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(model.statusTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(model.statusDetail)
                    .font(.caption)
                    .lineLimit(2)
                if !model.urlString.isEmpty {
                    Text(model.urlString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(Color.black)
    }
}

#else

import UIKit

@MainActor
final class BrowserPiPController: ObservableObject {
    @Published private(set) var isActive = false

    let sourceView = UIView(frame: .zero)
    var isSupported: Bool { false }

    func update(snapshot: UIImage?, title: String, urlString: String, statusTitle: String, statusDetail: String) {}
    func start() {}
    func stop() {}
}

struct BrowserPiPSourceAnchorView: UIViewRepresentable {
    @ObservedObject var controller: BrowserPiPController

    func makeUIView(context: Context) -> UIView {
        controller.sourceView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#endif
