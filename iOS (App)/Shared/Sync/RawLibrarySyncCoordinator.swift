import Combine
import Foundation

@MainActor
final class RawLibrarySyncCoordinator: ObservableObject {
    static let shared = RawLibrarySyncCoordinator()

    @Published private(set) var isSyncing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressState: RawLibrarySyncProgressState = .waiting
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastCompletedAt: Date?

    private var syncTask: Task<Void, Never>?

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        progress = 0
        progressState = .waiting
        lastErrorMessage = nil

        syncTask?.cancel()
        syncTask = Task {
            do {
                try await RawLibrarySyncService.shared.syncNow { progress in
                    Task { @MainActor in
                        self.updateProgress(progress)
                    }
                }
                progress = 1
                progressState = .progress(1)
                isSyncing = false
                lastCompletedAt = Date()
            } catch {
                isSyncing = false
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func updateProgress(_ value: RawLibrarySyncProgress) {
        guard value.total > 0 else {
            progressState = .waiting
            progress = 0
            return
        }
        let ratio = min(1, max(0, Double(value.completed) / Double(value.total)))
        progress = ratio
        progressState = .progress(ratio)
    }
}

enum RawLibrarySyncProgressState: Sendable, Equatable {
    case waiting
    case progress(Double)
}
