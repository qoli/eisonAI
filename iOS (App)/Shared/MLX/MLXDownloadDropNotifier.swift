import Combine
import Drops
import Foundation
import OSLog
import UIKit

@MainActor
final class MLXDownloadDropNotifier {
    static let shared = MLXDownloadDropNotifier()

    private enum ProgressSnapshot: Equatable {
        case indeterminate
        case percent(Int)
    }

    private let coordinator: MLXDownloadCoordinator
    private let drops: Drops
    private let downloadsPresentation: MLXDownloadsPresentationController
    private let logger = Logger(subsystem: "com.qoli.eisonAI", category: "MLXDownloadDropNotifier")
    private var cancellable: AnyCancellable?
    private var hasStarted = false
    private var lastStateByJobID: [String: MLXDownloadJob.State] = [:]
    private var lastProgressSnapshotByJobID: [String: ProgressSnapshot] = [:]

    init(
        coordinator: MLXDownloadCoordinator = .shared,
        drops: Drops = Drops(delayBetweenDrops: 0.1),
        downloadsPresentation: MLXDownloadsPresentationController = .shared
    ) {
        self.coordinator = coordinator
        self.drops = drops
        self.downloadsPresentation = downloadsPresentation

        self.drops.willShowDrop = { [weak self] drop in
            self?.logDropLifecycle(event: "willShow", drop: drop)
        }
        self.drops.didShowDrop = { [weak self] drop in
            self?.logDropLifecycle(event: "didShow", drop: drop)
        }
        self.drops.willDismissDrop = { [weak self] drop in
            self?.logDropLifecycle(event: "willDismiss", drop: drop)
        }
        self.drops.didDismissDrop = { [weak self] drop in
            self?.logDropLifecycle(event: "didDismiss", drop: drop)
        }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        handle(job: coordinator.currentJob)
        cancellable = coordinator.$currentJob
            .receive(on: RunLoop.main)
            .sink { [weak self] job in
                self?.handle(job: job)
            }
    }

    private func handle(job: MLXDownloadJob?) {
        guard let job else { return }

        let previousState = lastStateByJobID[job.jobID]
        let previousProgressSnapshot = lastProgressSnapshotByJobID[job.jobID]

        switch job.state {
        case .queued:
            guard previousState != .queued else { break }
            show(
                title: "Queued MLX Download",
                subtitle: job.displayName,
                iconName: "clock.badge",
                duration: 1.4
            )

        case .running:
            if previousState != .running {
                logProgressDropStyle(for: job)
                showProgress(
                    title: "Downloading MLX Model",
                    subtitle: progressSubtitle(for: job, fallback: job.displayName),
                    iconName: "arrow.down.circle",
                    progress: progress(for: job),
                    id: progressDropID(for: job)
                )
            } else {
                let progressSnapshot = progressSnapshot(for: job)
                guard progressSnapshot != previousProgressSnapshot else { break }
                logProgressDropStyle(for: job)
                showProgress(
                    title: "Downloading MLX Model",
                    subtitle: progressSubtitle(for: job, fallback: job.displayName),
                    iconName: "arrow.down.circle",
                    progress: progress(for: job),
                    id: progressDropID(for: job)
                )
            }
            lastProgressSnapshotByJobID[job.jobID] = progressSnapshot(for: job)

        case .finishing:
            guard previousState != .finishing else { break }
            showProgress(
                title: "Finalizing MLX Model",
                subtitle: job.displayName,
                iconName: "hourglass",
                progress: .indeterminate,
                id: progressDropID(for: job)
            )

        case .completed:
            guard previousState != .completed else { break }
            show(
                title: "MLX Model Installed",
                subtitle: job.displayName,
                iconName: "checkmark.circle.fill",
                duration: 2.2,
                replacingCurrent: true
            )

        case .failed:
            guard previousState != .failed else { break }
            show(
                title: "MLX Download Failed",
                subtitle: job.errorMessage ?? job.displayName,
                iconName: "xmark.octagon.fill",
                duration: 3.0,
                replacingCurrent: true
            )

        case .cancelled:
            guard previousState != .cancelled else { break }
            show(
                title: "MLX Download Cancelled",
                subtitle: job.errorMessage ?? job.displayName,
                iconName: "xmark.circle.fill",
                duration: 2.4,
                replacingCurrent: true
            )
        }

        lastStateByJobID[job.jobID] = job.state
        if !job.isActive {
            lastProgressSnapshotByJobID.removeValue(forKey: job.jobID)
            lastStateByJobID.removeValue(forKey: job.jobID)
        }
    }

    private func progressPercent(for job: MLXDownloadJob) -> Int? {
        guard let fraction = normalizedProgress(for: job), fraction > 0 else { return nil }
        return min(100, Int((fraction * 100).rounded(.down)))
    }

    private func normalizedProgress(for job: MLXDownloadJob) -> Double? {
        if job.totalUnitCount > 0 {
            return min(1, max(0, Double(job.completedUnitCount) / Double(max(job.totalUnitCount, 1))))
        }
        guard job.fractionCompleted > 0 else { return nil }
        return min(1, max(0, job.fractionCompleted))
    }

    private func progressSubtitle(for job: MLXDownloadJob, fallback: String) -> String {
        guard let progressPercent = progressPercent(for: job) else { return fallback }
        return "\(job.displayName) · \(progressPercent)%"
    }

    private func progress(for job: MLXDownloadJob) -> Drop.Progress {
        if let normalizedProgress = normalizedProgress(for: job) {
            return .determinate(normalizedProgress)
        }
        return .indeterminate
    }

    private func progressSnapshot(for job: MLXDownloadJob) -> ProgressSnapshot {
        if let progressPercent = progressPercent(for: job) {
            return .percent(progressPercent)
        }
        return .indeterminate
    }

    private func progressDropID(for job: MLXDownloadJob) -> String {
        "mlx-download-\(job.jobID)"
    }

    private func logProgressDropStyle(for job: MLXDownloadJob) {
        let style: String
        switch progress(for: job) {
        case let .determinate(value):
            style = "determinate(\(String(format: "%.3f", value)))"
        case .indeterminate:
            style = "indeterminate"
        }

        logger.xcodeNotice(
            """
            MLX drop progress style jobID=\(job.jobID) model=\(job.modelID) state=\(job.state.rawValue) style=\(style) \
            completed=\(job.completedUnitCount) total=\(job.totalUnitCount) fraction=\(String(format: "%.3f", job.fractionCompleted)) \
            subtitle=\(progressSubtitle(for: job, fallback: job.displayName))
            """
        )
    }

    private func logDropLifecycle(event: String, drop: Drop) {
        logger.xcodeNotice(
            """
            MLX drop lifecycle event=\(event) id=\(drop.id ?? "nil") title=\(drop.title) \
            subtitle=\(drop.subtitle ?? "nil") progress=\(dropProgressDescription(drop.progress)) \
            duration=\(dropDurationDescription(drop.duration))
            """
        )
    }

    private func dropProgressDescription(_ progress: Drop.Progress?) -> String {
        switch progress {
        case let .determinate(value):
            return "determinate(\(String(format: "%.3f", value)))"
        case .indeterminate:
            return "indeterminate"
        case nil:
            return "nil"
        }
    }

    private func dropDurationDescription(_ duration: Drop.Duration) -> String {
        switch duration {
        case let .seconds(seconds):
            return "seconds(\(String(format: "%.2f", seconds)))"
        case .recommended:
            return "recommended"
        case .untilHidden:
            return "untilHidden"
        }
    }

    private func showProgress(
        title: String,
        subtitle: String,
        iconName: String,
        progress: Drop.Progress,
        id: String
    ) {
        let drop = Drop(
            title: title,
            subtitle: subtitle,
            icon: UIImage(systemName: iconName),
            action: .init { [weak downloadsPresentation] in
                downloadsPresentation?.present()
            },
            duration: .untilHidden,
            id: id,
            progress: progress
        )
        drops.show(drop)
    }

    private func show(
        title: String,
        subtitle: String,
        iconName: String,
        duration: TimeInterval,
        replacingCurrent: Bool = false
    ) {
        if replacingCurrent {
            drops.hideAll()
        }
        let drop = Drop(
            title: title,
            subtitle: subtitle,
            icon: UIImage(systemName: iconName),
            action: .init { [weak downloadsPresentation] in
                downloadsPresentation?.present()
            },
            duration: .seconds(duration)
        )
        drops.show(drop)
    }
}
