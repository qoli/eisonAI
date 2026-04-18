import Combine
import Drops
import Foundation
import UIKit

@MainActor
final class MLXDownloadDropNotifier {
    static let shared = MLXDownloadDropNotifier()

    private let coordinator: MLXDownloadCoordinator
    private let drops: Drops
    private var cancellable: AnyCancellable?
    private var hasStarted = false
    private var lastStateByJobID: [String: MLXDownloadJob.State] = [:]
    private var lastProgressBucketByJobID: [String: Int] = [:]

    init(
        coordinator: MLXDownloadCoordinator = .shared,
        drops: Drops = Drops(delayBetweenDrops: 0.1)
    ) {
        self.coordinator = coordinator
        self.drops = drops
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
        let previousBucket = lastProgressBucketByJobID[job.jobID] ?? -1

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
            let progressBucket = progressBucket(for: job)
            if previousState != .running {
                show(
                    title: "Starting MLX Download",
                    subtitle: progressSubtitle(for: job, fallback: job.displayName),
                    iconName: "arrow.down.circle",
                    duration: 1.6
                )
            } else if let progressBucket, progressBucket > previousBucket {
                show(
                    title: "Downloading MLX Model",
                    subtitle: "\(job.displayName) · \(progressBucket)%",
                    iconName: "arrow.down.circle",
                    duration: 1.4
                )
            }
            lastProgressBucketByJobID[job.jobID] = progressBucket ?? previousBucket

        case .finishing:
            guard previousState != .finishing else { break }
            show(
                title: "Finalizing MLX Model",
                subtitle: job.displayName,
                iconName: "hourglass",
                duration: 1.6,
                replacingCurrent: true
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
            lastProgressBucketByJobID[job.jobID] = progressBucket(for: job) ?? previousBucket
        }
    }

    private func progressBucket(for job: MLXDownloadJob) -> Int? {
        let fraction = normalizedProgress(for: job)
        guard fraction > 0 else { return nil }
        let percent = min(100, Int((fraction * 100).rounded(.down)))
        return min(100, (percent / 25) * 25)
    }

    private func normalizedProgress(for job: MLXDownloadJob) -> Double {
        if job.totalUnitCount > 0 {
            return min(1, max(0, Double(job.completedUnitCount) / Double(max(job.totalUnitCount, 1))))
        }
        return min(1, max(0, job.fractionCompleted))
    }

    private func progressSubtitle(for job: MLXDownloadJob, fallback: String) -> String {
        guard let progressBucket = progressBucket(for: job) else { return fallback }
        return "\(job.displayName) · \(progressBucket)%"
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
            duration: .seconds(duration)
        )
        drops.show(drop)
    }
}
