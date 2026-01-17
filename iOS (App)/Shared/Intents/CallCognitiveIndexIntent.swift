import _AppIntents_SwiftUI
import AppIntents
import Foundation
import SwiftUI

struct CallCognitiveIndexIntent: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Cognitive Index"
    static var description = IntentDescription(
        "Generate a Cognitive Index (key points) from input text, matching the in-app Clipboard Key Point flow."
    )
    static var openAppWhenRun: Bool = false
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes {
        IntentModes.foreground(.dynamic)
    }

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Generate Cognitive Index for \(\.$text)")
    }

    func perform() async throws -> some ReturnsValue<String> & ShowsSnippetView {
        log("perform start")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stateStore = ClipboardKeyPointIntentStateStore()
        let runId = UUID().uuidString
        log("state reset runId=\(runId) textLength=\(trimmed.count)")
        stateStore.reset(runId: runId)

        progress.totalUnitCount = 100
        progress.completedUnitCount = 0
        log("progress initialized total=100 completed=0")

        guard !trimmed.isEmpty else {
            log("input empty; returning early")
            stateStore.update(
                status: "Empty",
                output: "Input is empty.",
                progress: 1.0
            )
            return .result(
                value: "Input is empty.",
                view: ClipboardKeyPointSnippetView()
            )
        }

        let payload = SharePayload(
            id: UUID().uuidString,
            createdAt: Date(),
            url: nil,
            text: trimmed,
            title: nil
        )
        log("payload created id=\(payload.id)")
        let model = await MainActor.run {
            ClipboardKeyPointViewModel(input: .share(payload), saveMode: .createNew)
        }
        log("view model created")

        await MainActor.run {
            model.run()
        }
        log("model run triggered")

        await streamStatusUpdates(model: model, stateStore: stateStore)
        log("status streaming completed")

        let finalStatus = await MainActor.run { model.status }
        let finalOutput = await MainActor.run { model.output }
        let finalToken = await MainActor.run { model.tokenEstimate }
        let finalChunk = await MainActor.run { model.chunkStatus }

        log("final status=\(finalStatus) tokenEstimate=\(finalToken ?? 0) chunkStatus=\(finalChunk)")
        stateStore.update(
            status: finalStatus,
            output: finalOutput,
            tokenEstimate: finalToken,
            chunkStatus: finalChunk,
            progress: 1.0
        )

        let message = resultMessage(forStatus: finalStatus)
        log("perform finished message=\(message)")
        return .result(value: message, view: ClipboardKeyPointSnippetView())
    }

    private func streamStatusUpdates(
        model: ClipboardKeyPointViewModel,
        stateStore: ClipboardKeyPointIntentStateStore
    ) async {
        var lastStatus = ""
        var lastOutput = ""
        var lastToken: Int?
        var lastChunk = ""
        var didStart = false
        var iteration = 0

        while true {
            if Task.isCancelled {
                log("task cancelled; canceling model")
                await MainActor.run {
                    model.cancel()
                }
                stateStore.update(status: "Canceled", progress: 1.0)
                break
            }

            let snapshot = await MainActor.run {
                (
                    isRunning: model.isRunning,
                    status: model.status,
                    output: model.output,
                    tokenEstimate: model.tokenEstimate,
                    chunkStatus: model.chunkStatus
                )
            }
            iteration += 1
            if iteration % 20 == 0 {
                log("heartbeat isRunning=\(snapshot.isRunning) status=\(snapshot.status) outputLength=\(snapshot.output.count)")
            }

            if snapshot.isRunning || snapshot.status != "Ready" {
                didStart = true
            }

            if snapshot.status != lastStatus {
                lastStatus = snapshot.status
                let progressValue = progressUnits(
                    forStatus: snapshot.status,
                    chunkStatus: snapshot.chunkStatus
                )
                progress.completedUnitCount = progressValue
                log("status=\(snapshot.status) progress=\(progressValue)")
                stateStore.update(
                    status: snapshot.status,
                    progress: Double(progressValue) / 100.0
                )
            }

            if snapshot.output != lastOutput {
                lastOutput = snapshot.output
                log("output updated length=\(snapshot.output.count)")
                stateStore.update(output: snapshot.output)
            }

            if snapshot.tokenEstimate != lastToken {
                lastToken = snapshot.tokenEstimate
                log("tokenEstimate updated \(snapshot.tokenEstimate ?? 0)")
                stateStore.update(tokenEstimate: snapshot.tokenEstimate)
            }

            if snapshot.chunkStatus != lastChunk {
                lastChunk = snapshot.chunkStatus
                log("chunkStatus updated \(snapshot.chunkStatus)")
                stateStore.update(chunkStatus: snapshot.chunkStatus)
                if snapshot.status.lowercased().contains("chunk") {
                    let progressValue = progressUnits(
                        forStatus: snapshot.status,
                        chunkStatus: snapshot.chunkStatus
                    )
                    progress.completedUnitCount = progressValue
                    stateStore.update(progress: Double(progressValue) / 100.0)
                }
            }

            if didStart, !snapshot.isRunning {
                log("model finished running")
                break
            }

            try? await Task.sleep(nanoseconds: 150000000)
        }
    }

    private func progressUnits(forStatus status: String, chunkStatus: String) -> Int64 {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasPrefix("error") || normalized == "canceled" || normalized == "done" {
            return 100
        }
        if normalized.contains("prepar") { return 5 }
        if normalized.contains("read") { return 10 }
        if normalized.contains("url") { return 15 }
        if normalized.contains("extract") { return 20 }
        if normalized.contains("clipboard") || normalized.contains("shared") { return 20 }
        if normalized.contains("chunk") {
            if let chunkProgress = chunkProgressUnits(from: chunkStatus) {
                return chunkProgress
            }
            return 35
        }
        if normalized.contains("model") { return 30 }
        if normalized.contains("generat") { return 55 }
        if normalized.contains("summary") { return 70 }
        if normalized.contains("save") { return 85 }
        if normalized.contains("title") { return 95 }
        if normalized.contains("invalid") || normalized.contains("empty") { return 100 }

        return progress.completedUnitCount
    }

    private func chunkProgressUnits(from chunkStatus: String) -> Int64? {
        let parts = chunkStatus.split(separator: "/")
        guard parts.count == 2,
              let index = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0
        else {
            return nil
        }

        let ratio = min(max(Double(index) / Double(total), 0), 1)
        return 35 + Int64(ratio * 35)
    }

    private func resultMessage(forStatus status: String) -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "done" {
            return "Saved."
        }
        if normalized == "canceled" {
            return "Canceled."
        }
        if normalized.hasPrefix("error") {
            return status
        }
        if normalized.contains("empty") {
            return "Input is empty."
        }

        return "Finished."
    }

    private func log(_ message: String) {
        #if DEBUG
            print("[KeyPointIntent] \(message)")
        #endif
    }
}

private enum ClipboardKeyPointIntentSnippetKeys {
    static let runId = "eison.intent.keypoint.runId"
    static let status = "eison.intent.keypoint.status"
    static let output = "eison.intent.keypoint.output"
    static let tokenEstimate = "eison.intent.keypoint.tokenEstimate"
    static let chunkStatus = "eison.intent.keypoint.chunkStatus"
    static let progress = "eison.intent.keypoint.progress"
    static let updatedAt = "eison.intent.keypoint.updatedAt"
}

private struct ClipboardKeyPointIntentStateStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConfig.appGroupIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func reset(runId: String) {
        defaults.set(runId, forKey: ClipboardKeyPointIntentSnippetKeys.runId)
        defaults.set("Preparing", forKey: ClipboardKeyPointIntentSnippetKeys.status)
        defaults.set("", forKey: ClipboardKeyPointIntentSnippetKeys.output)
        defaults.set(0, forKey: ClipboardKeyPointIntentSnippetKeys.tokenEstimate)
        defaults.set("", forKey: ClipboardKeyPointIntentSnippetKeys.chunkStatus)
        defaults.set(0.0, forKey: ClipboardKeyPointIntentSnippetKeys.progress)
        defaults.set(Date().timeIntervalSince1970, forKey: ClipboardKeyPointIntentSnippetKeys.updatedAt)
    }

    func update(
        status: String? = nil,
        output: String? = nil,
        tokenEstimate: Int? = nil,
        chunkStatus: String? = nil,
        progress: Double? = nil
    ) {
        if let status {
            defaults.set(status, forKey: ClipboardKeyPointIntentSnippetKeys.status)
        }
        if let output {
            defaults.set(output, forKey: ClipboardKeyPointIntentSnippetKeys.output)
        }
        if let tokenEstimate {
            defaults.set(tokenEstimate, forKey: ClipboardKeyPointIntentSnippetKeys.tokenEstimate)
        }
        if let chunkStatus {
            defaults.set(chunkStatus, forKey: ClipboardKeyPointIntentSnippetKeys.chunkStatus)
        }
        if let progress {
            defaults.set(progress, forKey: ClipboardKeyPointIntentSnippetKeys.progress)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: ClipboardKeyPointIntentSnippetKeys.updatedAt)
    }
}

struct ClipboardKeyPointSnippetView: View {
    @AppStorage(
        ClipboardKeyPointIntentSnippetKeys.status,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    )
    private var status: String = "Preparing"

    @AppStorage(
        ClipboardKeyPointIntentSnippetKeys.output,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    )
    private var output: String = ""

    @AppStorage(
        ClipboardKeyPointIntentSnippetKeys.tokenEstimate,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    )
    private var tokenEstimate: Int = 0

    @AppStorage(
        ClipboardKeyPointIntentSnippetKeys.chunkStatus,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    )
    private var chunkStatus: String = ""

    @AppStorage(
        ClipboardKeyPointIntentSnippetKeys.progress,
        store: UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    )
    private var progressValue: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cognitive Index")
                    .font(.headline)

                Spacer()

                Text(status.isEmpty ? "-" : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if progressValue > 0 && progressValue < 1 {
                ProgressView(value: progressValue)
            }

            HStack(spacing: 12) {
                if tokenEstimate > 0 {
                    Text("~\(tokenEstimate) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !chunkStatus.isEmpty {
                    Text("Chunk \(chunkStatus)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(output.isEmpty ? "Generating..." : output)
                .font(.caption)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .onAppear {
            #if DEBUG
                print("[KeyPointIntent] snippet view appeared")
            #endif
        }
    }
}
