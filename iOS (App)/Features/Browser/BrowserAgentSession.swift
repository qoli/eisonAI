import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserAgentSession: NSObject, ObservableObject, WKNavigationDelegate {
    private static let defaultHomeURL = URL(string: "https://www.wikipedia.org")!
    private static let defaultPageZoom: CGFloat = 1.0

    @Published var addressText = ""
    @Published var agentPrompt = ""
    @Published private(set) var pageTitle = ""
    @Published private(set) var currentURLString = ""
    @Published private(set) var isLoading = false
    @Published private(set) var runState: BrowserAgentRunState = .idle
    @Published private(set) var logEntries: [BrowserAgentLogEntry] = []
    @Published private(set) var taskState = BrowserAgentTaskState.idle(maxSteps: 30)
    @Published private(set) var latestSnapshot: UIImage?
    @Published var lastError: String?

    let webView: WKWebView
    let pipController = BrowserPiPController()

    private let pageBridge = BrowserPageBridge()
    private let anyLanguageModelClient = AnyLanguageModelClient()
    private let backendSettings = GenerationBackendSettingsStore()
    private let byokSettingsStore = BYOKSettingsStore()
    private let mlxModelStore = MLXModelStore()
    private let tokenEstimator = GPTTokenEstimator.shared
    private let modelLanguageStore = ModelLanguageStore()

    private var runTask: Task<Void, Never>?
    private var rollingHistorySummary = ""
    private var summarizedLogEntryCount = 0
    private let maxSteps = 30
    private let recentLogWindowSize = 6
    private let rollingSummaryCharacterLimit = 1_600
    private let browserResponseRetryLimit = 2

    override init() {
        let contentController = WKUserContentController()
        let bridge = BrowserPageBridge()
        bridge.configure(userContentController: contentController)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.pageZoom = Self.defaultPageZoom
        self.webView = webView
        super.init()

        self.webView.navigationDelegate = self
        addressText = Self.defaultHomeURL.absoluteString
        load(url: Self.defaultHomeURL)
        ConsoleErrorReporter.logInfo(
            "Initialized browser session.",
            context: "BrowserAgentSession.init",
            metadata: [
                "defaultHomeURL": Self.defaultHomeURL.absoluteString,
                "defaultPageZoom": String(format: "%.2f", Self.defaultPageZoom),
            ]
        )
        syncPiPState()
    }

    deinit {
        runTask?.cancel()
    }

    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }
    var canStartPictureInPicture: Bool { pipController.isSupported }

    func submitAddress() {
        guard let url = normalizedURL(from: addressText) else {
            lastError = "Enter a valid URL."
            ConsoleErrorReporter.logMessage(
                "Rejected invalid address input.",
                context: "BrowserAgentSession.submitAddress",
                metadata: ["addressText": addressText]
            )
            return
        }
        load(url: url)
    }

    func load(url: URL) {
        lastError = nil
        addressText = url.absoluteString
        ConsoleErrorReporter.logInfo(
            "Loading URL.",
            context: "BrowserAgentSession.load",
            metadata: [
                "url": url.absoluteString,
            ]
        )
        webView.load(URLRequest(url: url))
    }

    func reload() {
        ConsoleErrorReporter.logInfo(
            "Reload requested.",
            context: "BrowserAgentSession.reload",
            metadata: [
                "url": currentURLString,
            ]
        )
        webView.reload()
    }

    func goBack() {
        ConsoleErrorReporter.logInfo(
            "Back navigation requested.",
            context: "BrowserAgentSession.goBack",
            metadata: [
                "currentURL": currentURLString,
            ]
        )
        webView.goBack()
    }

    func goForward() {
        ConsoleErrorReporter.logInfo(
            "Forward navigation requested.",
            context: "BrowserAgentSession.goForward",
            metadata: [
                "currentURL": currentURLString,
            ]
        )
        webView.goForward()
    }

    func startPictureInPicture() {
        ConsoleErrorReporter.logInfo(
            "Starting Picture in Picture.",
            context: "BrowserAgentSession.startPictureInPicture",
            metadata: [
                "title": pageTitle,
                "url": currentURLString,
            ]
        )
        pipController.start()
    }

    func stopPictureInPicture() {
        ConsoleErrorReporter.logInfo(
            "Stopping Picture in Picture.",
            context: "BrowserAgentSession.stopPictureInPicture",
            metadata: [
                "title": pageTitle,
                "url": currentURLString,
            ]
        )
        pipController.stop()
    }

    func runAgent() {
        let prompt = agentPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            lastError = "Enter a browser task first."
            ConsoleErrorReporter.logMessage(
                "Rejected empty browser-agent prompt.",
                context: "BrowserAgentSession.runAgent"
            )
            return
        }
        guard !currentURLString.isEmpty else {
            lastError = "Open a page before starting the browser agent."
            ConsoleErrorReporter.logMessage(
                "Rejected browser-agent run without an active page.",
                context: "BrowserAgentSession.runAgent",
                metadata: ["prompt": prompt]
            )
            return
        }
        guard !runState.isRunning else { return }

        lastError = nil
        runState = .running(step: 1)
        logEntries = []
        rollingHistorySummary = ""
        summarizedLogEntryCount = 0
        taskState = .starting(
            goal: prompt,
            pageURL: currentURLString,
            pageTitle: pageTitle,
            maxSteps: maxSteps
        )
        ConsoleErrorReporter.logInfo(
            "Starting browser-agent run.",
            context: "BrowserAgentSession.runAgent",
            metadata: [
                "goal": prompt,
                "title": pageTitle,
                "url": currentURLString,
            ]
        )
        syncPiPState()

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.executeRunLoop(goal: prompt)
        }
    }

    func stopAgent() {
        runTask?.cancel()
        runTask = nil
        if runState.isRunning {
            runState = .cancelled
            taskState.status = .cancelled
            taskState.nextGoal = ""
            taskState.lastStepSummary = "Cancelled the current browser-agent run."
            appendLog(step: 0, title: "Stopped", detail: "Cancelled the current browser-agent run.", kind: .result)
            ConsoleErrorReporter.logInfo(
                "Cancelled browser-agent run.",
                context: "BrowserAgentSession.stopAgent",
                metadata: [
                    "title": pageTitle,
                    "url": currentURLString,
                ]
            )
            syncPiPState()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastError = nil
        syncLocation()
        ConsoleErrorReporter.logInfo(
            "Started provisional navigation.",
            context: "BrowserAgentSession.didStartProvisionalNavigation",
            metadata: [
                "title": webView.title ?? pageTitle,
                "url": webView.url?.absoluteString ?? currentURLString,
            ]
        )
        syncPiPState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isLoading = true
        syncLocation()
        ConsoleErrorReporter.logInfo(
            "Navigation committed.",
            context: "BrowserAgentSession.didCommitNavigation",
            metadata: [
                "title": webView.title ?? pageTitle,
                "url": webView.url?.absoluteString ?? currentURLString,
            ]
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncLocation()
        ConsoleErrorReporter.logInfo(
            "Navigation finished.",
            context: "BrowserAgentSession.didFinishNavigation",
            metadata: [
                "title": webView.title ?? pageTitle,
                "url": webView.url?.absoluteString ?? currentURLString,
            ]
        )
        Task {
            await refreshSnapshot()
            syncPiPState()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        lastError = error.localizedDescription
        ConsoleErrorReporter.log(
            error,
            context: "BrowserAgentSession.didFailNavigation",
            metadata: [
                "url": webView.url?.absoluteString ?? currentURLString,
                "title": webView.title ?? pageTitle,
            ]
        )
        syncLocation()
        syncPiPState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        lastError = error.localizedDescription
        ConsoleErrorReporter.log(
            error,
            context: "BrowserAgentSession.didFailProvisionalNavigation",
            metadata: [
                "url": webView.url?.absoluteString ?? currentURLString,
                "title": webView.title ?? pageTitle,
            ]
        )
        syncLocation()
        syncPiPState()
    }

    private func executeRunLoop(goal: String) async {
        for step in 1 ... maxSteps {
            if Task.isCancelled {
                return
            }

            do {
                runState = .running(step: step)
                ConsoleErrorReporter.logInfo(
                    "Starting browser-agent step.",
                    context: "BrowserAgentSession.executeRunLoop",
                    metadata: [
                        "goal": goal,
                        "step": String(step),
                        "url": currentURLString,
                    ]
                )
                taskState.status = .running
                taskState.currentStep = step
                await refreshRollingSummaryIfNeeded(goal: goal)
                syncPiPState()

                let observation = try await pageBridge.observe(in: webView)
                taskState.recordObservation(observation, step: step)
                ConsoleErrorReporter.logInfo(
                    "Collected page observation.",
                    context: "BrowserAgentSession.observe",
                    metadata: observationMetadata(observation, step: step)
                )
                let response = try await requestNextStep(goal: goal, observation: observation, step: step)
                taskState.recordModelResponse(response, step: step)

                var responseMetadata: [String: String] = [
                    "status": response.status.rawValue,
                    "step": String(step),
                    "evaluationPreviousGoal": response.evaluationPreviousGoal,
                    "nextGoal": response.nextGoal,
                ]
                if let summary = response.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    responseMetadata["summary"] = summary
                }
                if let action = response.action {
                    responseMetadata["action"] = action.summary
                }
                ConsoleErrorReporter.logInfo(
                    "Received model response.",
                    context: "BrowserAgentSession.modelResponse",
                    metadata: responseMetadata
                )

                appendLog(
                    step: step,
                    title: "Decision",
                    detail: formatDecisionLog(for: response),
                    kind: .decision
                )

                switch response.status {
                case .done:
                    let summary = response.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Task complete."
                    runState = .completed(summary)
                    taskState.status = .completed
                    taskState.nextGoal = ""
                    taskState.lastStepSummary = summary
                    taskState.appendUniqueLine(summary, to: \.completedMilestones)
                    appendLog(step: step, title: "Done", detail: summary, kind: .result)
                    ConsoleErrorReporter.logInfo(
                        "Browser-agent run completed.",
                        context: "BrowserAgentSession.executeRunLoop",
                        metadata: [
                            "step": String(step),
                            "summary": summary,
                            "url": currentURLString,
                        ]
                    )
                    syncPiPState()
                    return
                case .failed:
                    let summary = response.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "The browser agent could not complete the task."
                    runState = .failed(summary)
                    taskState.status = .failed
                    taskState.nextGoal = ""
                    taskState.lastStepSummary = summary
                    taskState.recordRuntimeIssue(summary)
                    appendLog(step: step, title: "Failed", detail: summary, kind: .error)
                    ConsoleErrorReporter.logInfo(
                        "Browser-agent run failed gracefully.",
                        context: "BrowserAgentSession.executeRunLoop",
                        metadata: [
                            "step": String(step),
                            "summary": summary,
                            "url": currentURLString,
                        ]
                    )
                    syncPiPState()
                    return
                case .continue:
                    guard let action = response.action else {
                        throw BrowserRunError.missingAction
                    }
                    taskState.recordPlannedAction(action, step: step)
                    appendLog(
                        step: step,
                        title: action.summary,
                        detail: response.summary ?? response.nextGoal,
                        kind: .action
                    )
                    ConsoleErrorReporter.logInfo(
                        "Executing browser action.",
                        context: "BrowserAgentSession.executeAction",
                        metadata: actionMetadata(action, step: step)
                    )

                    let result = try await pageBridge.perform(action, in: webView)
                    taskState.recordActionResult(result, for: action, step: step)
                    appendLog(
                        step: step,
                        title: result.success ? "Result" : "Action Error",
                        detail: result.message,
                        kind: result.success ? .result : .error
                    )
                    if !result.success {
                        ConsoleErrorReporter.logMessage(
                            result.message,
                            context: "BrowserAgentSession.actionResult",
                            metadata: [
                                "step": String(step),
                                "action": action.summary,
                                "url": currentURLString,
                            ]
                        )
                    } else {
                        ConsoleErrorReporter.logInfo(
                            "Browser action completed.",
                            context: "BrowserAgentSession.executeAction",
                            metadata: [
                                "action": action.summary,
                                "message": result.message,
                                "step": String(step),
                                "url": currentURLString,
                            ]
                        )
                    }

                    try Task.checkCancellation()
                    try await waitForPageStability(after: action)
                    await refreshSnapshot()
                    syncPiPState()
                }
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                lastError = message
                runState = .failed(message)
                taskState.status = .failed
                taskState.nextGoal = ""
                taskState.lastStepSummary = message
                taskState.recordRuntimeIssue(message)
                appendLog(step: step, title: "Run Error", detail: message, kind: .error)
                ConsoleErrorReporter.log(
                    error,
                    context: "BrowserAgentSession.executeRunLoop",
                    metadata: [
                        "step": String(step),
                        "goal": goal,
                        "url": currentURLString,
                        "runState": runState.title,
                    ]
                )
                syncPiPState()
                return
            }
        }

        let summary = "Reached the step limit (\(maxSteps)) before completing the task."
        runState = .failed(summary)
        taskState.status = .failed
        taskState.nextGoal = ""
        taskState.lastStepSummary = summary
        taskState.recordRuntimeIssue(summary)
        appendLog(step: maxSteps, title: "Stopped", detail: summary, kind: .error)
        syncPiPState()
    }

    private func requestNextStep(goal: String, observation: BrowserPageObservation, step: Int) async throws -> BrowserAgentResponse {
        let systemPrompt = browserAgentSystemPrompt(languageTag: modelLanguageStore.loadOrRecommended())
        let userPrompt = browserAgentUserPrompt(goal: goal, observation: observation, step: step)
        let tokenEstimate = await tokenEstimator.estimateTokenCount(for: "\(systemPrompt)\n\n\(userPrompt)")
        let backend = backendSettings.resolveExecutionBackend(tokenCount: tokenEstimate)
        var modelRequestMetadata: [String: String] = [
            "backend": backend.rawValue,
            "goal": goal,
            "step": String(step),
            "tokenEstimate": String(tokenEstimate),
        ]
        if backend == .mlx {
            modelRequestMetadata["mlxModelID"] = mlxModelStore.loadSelectedModelID()
        }
        if backend == .byok {
            modelRequestMetadata["byokProvider"] = byokSettingsStore.loadSettings().provider.rawValue
        }
        ConsoleErrorReporter.logInfo(
            "Requesting next browser-agent step from model.",
            context: "BrowserAgentSession.requestNextStep",
            metadata: modelRequestMetadata
        )

        if backend == .appleIntelligence {
            anyLanguageModelClient.prewarm(
                systemPrompt: systemPrompt,
                promptPrefix: String(userPrompt.prefix(900)),
                backend: backend
            )
        }

        return try await requestBrowserAgentResponse(
            goal: goal,
            step: step,
            backend: backend,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
    }

    private func refreshRollingSummaryIfNeeded(goal: String) async {
        let summaryCutoff = max(0, logEntries.count - recentLogWindowSize)
        guard summaryCutoff > summarizedLogEntryCount else { return }

        let entriesToSummarize = Array(logEntries[summarizedLogEntryCount ..< summaryCutoff])
        guard !entriesToSummarize.isEmpty else { return }

        ConsoleErrorReporter.logInfo(
            "Condensing older browser-agent history.",
            context: "BrowserAgentSession.refreshRollingSummary",
            metadata: [
                "entriesToSummarize": String(entriesToSummarize.count),
                "existingSummaryLength": String(rollingHistorySummary.count),
                "goal": goal,
            ]
        )

        do {
            let updatedSummary = try await requestRollingSummaryUpdate(
                goal: goal,
                existingSummary: rollingHistorySummary,
                newEntries: entriesToSummarize
            )
            rollingHistorySummary = normalizedRollingSummary(updatedSummary)
            taskState.rollingSummary = rollingHistorySummary
            summarizedLogEntryCount = summaryCutoff
            ConsoleErrorReporter.logInfo(
                "Updated rolling browser-agent summary.",
                context: "BrowserAgentSession.refreshRollingSummary",
                metadata: [
                    "summaryLength": String(rollingHistorySummary.count),
                    "summarizedLogEntryCount": String(summarizedLogEntryCount),
                ]
            )
        } catch {
            rollingHistorySummary = fallbackRollingSummary(
                goal: goal,
                existingSummary: rollingHistorySummary,
                newEntries: entriesToSummarize
            )
            taskState.rollingSummary = rollingHistorySummary
            summarizedLogEntryCount = summaryCutoff
            ConsoleErrorReporter.log(
                error,
                context: "BrowserAgentSession.refreshRollingSummary",
                metadata: [
                    "fallbackUsed": "true",
                    "goal": goal,
                    "summarizedLogEntryCount": String(summarizedLogEntryCount),
                ]
            )
        }
    }

    private func requestRollingSummaryUpdate(
        goal: String,
        existingSummary: String,
        newEntries: [BrowserAgentLogEntry]
    ) async throws -> String {
        let systemPrompt = rollingSummarySystemPrompt(languageTag: modelLanguageStore.loadOrRecommended())
        let userPrompt = rollingSummaryUserPrompt(
            goal: goal,
            existingSummary: existingSummary,
            newEntries: newEntries
        )
        let tokenEstimate = await tokenEstimator.estimateTokenCount(for: "\(systemPrompt)\n\n\(userPrompt)")
        let backend = backendSettings.resolveExecutionBackend(tokenCount: tokenEstimate)

        ConsoleErrorReporter.logInfo(
            "Requesting rolling summary update.",
            context: "BrowserAgentSession.requestRollingSummaryUpdate",
            metadata: [
                "backend": backend.rawValue,
                "existingSummaryLength": String(existingSummary.count),
                "newEntries": String(newEntries.count),
                "tokenEstimate": String(tokenEstimate),
            ]
        )

        if backend == .appleIntelligence {
            anyLanguageModelClient.prewarm(
                systemPrompt: systemPrompt,
                promptPrefix: String(userPrompt.prefix(900)),
                backend: backend
            )
        }

        let stream = try await makeModelStream(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            backend: backend,
            maximumResponseTokens: 220,
            temperature: 0.1
        )
        let output = try await collectOutput(from: stream)
        ConsoleErrorReporter.logMessage(
            output,
            context: "BrowserAgentSession.requestRollingSummaryUpdate.rawOutput",
            metadata: [
                "backend": backend.rawValue,
                "existingSummaryLength": String(existingSummary.count),
                "goal": goal,
                "newEntries": String(newEntries.count),
                "outputLength": String(output.count),
            ]
        )
        return output
    }

    private func makeModelStream(
        systemPrompt: String,
        userPrompt: String,
        backend: ExecutionBackend,
        maximumResponseTokens: Int,
        temperature: Double
    ) async throws -> AsyncThrowingStream<String, Error> {
        switch backend {
        case .mlx:
            return try await anyLanguageModelClient.streamChat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens,
                backend: backend,
                mlxModelID: mlxModelStore.loadSelectedModelID()
            )
        case .appleIntelligence:
            return try await anyLanguageModelClient.streamChat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens,
                backend: backend
            )
        case .byok:
            return try await anyLanguageModelClient.streamChat(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens,
                backend: backend,
                byok: byokSettingsStore.loadSettings()
            )
        }
    }

    private func collectOutput(from stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var output = ""
        for try await chunk in stream {
            if Task.isCancelled { break }
            output += chunk
        }
        return output
    }

    private func requestBrowserAgentResponse(
        goal: String,
        step: Int,
        backend: ExecutionBackend,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> BrowserAgentResponse {
        var lastError: Error = BrowserAgentModelOutputError.emptyResponse

        for attempt in 1 ... browserResponseRetryLimit {
            let attemptPrompt = browserAgentRetryPrompt(base: userPrompt, attempt: attempt)
            let output = try await requestModelOutput(
                systemPrompt: systemPrompt,
                userPrompt: attemptPrompt,
                backend: backend,
                maximumResponseTokens: 700,
                temperature: 0.2
            )

            logBrowserAgentRawOutput(
                output,
                context: "BrowserAgentSession.requestNextStep.rawOutput",
                goal: goal,
                step: step,
                backend: backend,
                phase: attempt == 1 ? "primary" : "retry-\(attempt)"
            )

            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOutput.isEmpty else {
                lastError = BrowserAgentModelOutputError.emptyResponse
                ConsoleErrorReporter.logInfo(
                    attempt < browserResponseRetryLimit
                        ? "Browser agent model returned an empty response. Retrying with a stricter reminder."
                        : "Browser agent model returned an empty response.",
                    context: "BrowserAgentSession.requestNextStep.retry",
                    metadata: [
                        "attempt": String(attempt),
                        "backend": backend.rawValue,
                        "goal": goal,
                        "step": String(step),
                    ]
                )
                continue
            }

            do {
                let response = try BrowserAgentResponseParser.parse(output)
                logBrowserAgentNormalizedResponse(
                    response,
                    goal: goal,
                    step: step,
                    backend: backend,
                    phase: attempt == 1 ? "primary" : "retry-\(attempt)"
                )
                return response
            } catch let parseError as BrowserAgentResponseParserError {
                lastError = parseError

                do {
                    if let repairedResponse = try await attemptBrowserAgentResponseRepair(
                        rawOutput: output,
                        parseError: parseError,
                        goal: goal,
                        step: step,
                        backend: backend
                    ) {
                        return repairedResponse
                    }
                } catch {
                    ConsoleErrorReporter.log(
                        error,
                        context: "BrowserAgentSession.requestNextStep.repairRequest",
                        metadata: [
                            "attempt": String(attempt),
                            "backend": backend.rawValue,
                            "goal": goal,
                            "step": String(step),
                        ]
                    )
                }

                ConsoleErrorReporter.logInfo(
                    attempt < browserResponseRetryLimit
                        ? "Browser agent response was not parseable. Retrying the original step request."
                        : "Browser agent response was not parseable.",
                    context: "BrowserAgentSession.requestNextStep.retry",
                    metadata: [
                        "attempt": String(attempt),
                        "backend": backend.rawValue,
                        "goal": goal,
                        "reason": parseError.localizedDescription,
                        "step": String(step),
                    ]
                )
            }
        }

        throw lastError
    }

    private func requestModelOutput(
        systemPrompt: String,
        userPrompt: String,
        backend: ExecutionBackend,
        maximumResponseTokens: Int,
        temperature: Double
    ) async throws -> String {
        let stream = try await makeModelStream(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            backend: backend,
            maximumResponseTokens: maximumResponseTokens,
            temperature: temperature
        )
        return try await collectOutput(from: stream)
    }

    private func attemptBrowserAgentResponseRepair(
        rawOutput: String,
        parseError: BrowserAgentResponseParserError,
        goal: String,
        step: Int,
        backend: ExecutionBackend
    ) async throws -> BrowserAgentResponse? {
        let repairedOutput = try await requestModelOutput(
            systemPrompt: browserAgentRepairSystemPrompt(languageTag: modelLanguageStore.loadOrRecommended()),
            userPrompt: browserAgentRepairUserPrompt(rawOutput: rawOutput, parseError: parseError),
            backend: backend,
            maximumResponseTokens: 700,
            temperature: 0
        )

        logBrowserAgentRawOutput(
            repairedOutput,
            context: "BrowserAgentSession.requestNextStep.repairOutput",
            goal: goal,
            step: step,
            backend: backend,
            phase: "repair"
        )

        let trimmedOutput = repairedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            ConsoleErrorReporter.logInfo(
                "Browser agent response repair returned empty output.",
                context: "BrowserAgentSession.requestNextStep.repair",
                metadata: [
                    "backend": backend.rawValue,
                    "goal": goal,
                    "step": String(step),
                ]
            )
            return nil
        }

        do {
            let response = try BrowserAgentResponseParser.parse(repairedOutput)
            logBrowserAgentNormalizedResponse(
                response,
                goal: goal,
                step: step,
                backend: backend,
                phase: "repair"
            )
            return response
        } catch {
            ConsoleErrorReporter.log(
                error,
                context: "BrowserAgentSession.requestNextStep.repair",
                metadata: [
                    "backend": backend.rawValue,
                    "goal": goal,
                    "step": String(step),
                ]
            )
            return nil
        }
    }

    private func logBrowserAgentRawOutput(
        _ output: String,
        context: String,
        goal: String,
        step: Int,
        backend: ExecutionBackend,
        phase: String
    ) {
        ConsoleErrorReporter.logMessage(
            output,
            context: context,
            metadata: [
                "backend": backend.rawValue,
                "goal": goal,
                "outputLength": String(output.count),
                "phase": phase,
                "step": String(step),
            ]
        )
    }

    private func logBrowserAgentNormalizedResponse(
        _ response: BrowserAgentResponse,
        goal: String,
        step: Int,
        backend: ExecutionBackend,
        phase: String
    ) {
        guard let normalizedData = try? JSONEncoder().encode(response) else { return }
        let json = String(decoding: normalizedData, as: UTF8.self)
        ConsoleErrorReporter.logMessage(
            json,
            context: "BrowserAgentSession.requestNextStep.extractedJSON",
            metadata: [
                "backend": backend.rawValue,
                "goal": goal,
                "jsonLength": String(json.count),
                "phase": phase,
                "step": String(step),
            ]
        )
    }

    private func waitForPageStability(after action: BrowserAgentAction) async throws {
        switch action.type {
        case .wait:
            return
        case .input, .select, .pressEnter:
            try await Task.sleep(nanoseconds: 350_000_000)
        case .click, .navigate, .scroll:
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }
            if webView.isLoading {
                try await Task.sleep(nanoseconds: 250_000_000)
                continue
            }
            let readyState = (try? await webView.evaluateJavaScriptAsync("document.readyState")) as? String
            if readyState == "complete" || readyState == "interactive" {
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func refreshSnapshot() async {
        do {
            let image = try await webView.takeSnapshotAsync()
            latestSnapshot = image
            ConsoleErrorReporter.logInfo(
                "Captured browser snapshot.",
                context: "BrowserAgentSession.refreshSnapshot",
                metadata: [
                    "height": String(Int(image.size.height)),
                    "url": currentURLString,
                    "width": String(Int(image.size.width)),
                ]
            )
            syncPiPState()
        } catch {
            ConsoleErrorReporter.log(
                error,
                context: "BrowserAgentSession.refreshSnapshot",
                metadata: ["url": currentURLString]
            )
        }
    }

    private func syncLocation() {
        pageTitle = webView.title ?? ""
        currentURLString = webView.url?.absoluteString ?? currentURLString
        if !currentURLString.isEmpty {
            addressText = currentURLString
        }
        taskState.updateLocation(url: currentURLString, title: pageTitle)
    }

    private func syncPiPState() {
        pipController.update(
            snapshot: latestSnapshot,
            title: pageTitle,
            urlString: currentURLString,
            statusTitle: runState.title,
            statusDetail: runState.detail
        )
    }

    private func appendLog(step: Int, title: String, detail: String, kind: BrowserAgentLogEntry.Kind) {
        logEntries.append(
            BrowserAgentLogEntry(
                step: step,
                title: title,
                detail: detail,
                kind: kind
            )
        )
        syncPiPState()
    }

    private func observationMetadata(_ observation: BrowserPageObservation, step: Int) -> [String: String] {
        [
            "contentLength": String(observation.content.count),
            "footerLength": String(observation.footer.count),
            "headerLength": String(observation.header.count),
            "step": String(step),
            "title": observation.title,
            "url": observation.url,
        ]
    }

    private func actionMetadata(_ action: BrowserAgentAction, step: Int) -> [String: String] {
        var metadata: [String: String] = [
            "action": action.summary,
            "step": String(step),
        ]
        if let index = action.index {
            metadata["index"] = String(index)
        }
        if let url = action.url, !url.isEmpty {
            metadata["targetURL"] = url
        }
        if let text = action.text, !text.isEmpty {
            metadata["textLength"] = String(text.count)
        }
        if let option = action.option, !option.isEmpty {
            metadata["option"] = option
        }
        if let direction = action.direction, !direction.isEmpty {
            metadata["direction"] = direction
        }
        if let pages = action.pages {
            metadata["pages"] = String(pages)
        }
        if let milliseconds = action.milliseconds {
            metadata["milliseconds"] = String(milliseconds)
        }
        return metadata
    }

    private func browserAgentSystemPrompt(languageTag: String) -> String {
        """
        You are eisonAI's in-app browser agent.

        You must choose exactly one same-tab browser step at a time.
        You can only use these action types:
        - click { "index": number }
        - input { "index": number, "text": string }
        - select { "index": number, "option": string }
        - scroll { "direction": "up" | "down", "pages": number, "index": number? }
        - wait { "milliseconds": number }
        - navigate { "url": string }
        - pressEnter { "index": number? }

        Rules:
        - Stay in the current tab. Never ask for multi-tab or popup workflows.
        - Prefer indexed click/input/select actions when the target already exists on the page.
        - Use navigate only when you truly need a new URL.
        - Always evaluate the previous step, preserve working memory, and state the next goal before choosing an action.
        - If the task is complete, return status "done" and omit action.
        - If the task is blocked or unsafe, return status "failed" and omit action.
        - Only return action when status is "continue".
        - Never output Markdown. Return JSON only.
        - Keep the reflection fields and "summary" concise.
        - Write all string fields in language tag \(languageTag) when practical.

        JSON schema:
        {
          "evaluationPreviousGoal": "short evaluation of the previous step",
          "memory": "short working memory",
          "nextGoal": "the next immediate goal",
          "status": "continue" | "done" | "failed",
          "summary": "short status summary",
          "action": {
            "type": "click" | "input" | "select" | "scroll" | "wait" | "navigate" | "pressEnter",
            "index": 12,
            "text": "value",
            "option": "label",
            "direction": "down",
            "pages": 1,
            "milliseconds": 800,
            "url": "https://example.com"
          }
        }
        """
    }

    private func browserAgentRetryPrompt(base: String, attempt: Int) -> String {
        guard attempt > 1 else { return base }

        return """
        \(base)

        Important retry instruction:
        - Your previous response was empty or could not be parsed.
        - Return exactly one JSON object that matches the schema.
        - Do not add prose, Markdown fences, comments, or explanations.
        """
    }

    private func browserAgentUserPrompt(goal: String, observation: BrowserPageObservation, step: Int) -> String {
        let recentLogText = logEntries.suffix(recentLogWindowSize).map { entry in
            "[step \(entry.step)] \(entry.title): \(entry.detail)"
        }.joined(separator: "\n")

        let pageState = [
            observation.header,
            observation.content,
            observation.footer,
        ]
        .joined(separator: "\n")

        let trimmedState = String(pageState.prefix(18_000))
        let structuredTaskState = taskStatePromptJSON()

        return """
        Goal:
        \(goal)

        Current step:
        \(step) / \(maxSteps)

        Current URL:
        \(observation.url)

        Current title:
        \(observation.title)

        Earlier summarized context:
        \(rollingHistorySummary.isEmpty ? "(none yet)" : rollingHistorySummary)

        Recent steps:
        \(recentLogText.isEmpty ? "(none yet)" : recentLogText)

        Structured task state (JSON):
        \(structuredTaskState)

        Page state:
        \(trimmedState)
        """
    }

    private func browserAgentRepairSystemPrompt(languageTag: String) -> String {
        """
        You repair eisonAI browser-agent outputs into valid JSON.

        Requirements:
        - Return exactly one JSON object.
        - Preserve the intended action and fields when possible.
        - Use only this schema:
          {
            "evaluationPreviousGoal": string,
            "memory": string,
            "nextGoal": string,
            "status": "continue" | "done" | "failed",
            "summary": string,
            "action": {
              "type": "click" | "input" | "select" | "scroll" | "wait" | "navigate" | "pressEnter",
              "index": number?,
              "text": string?,
              "option": string?,
              "direction": "up" | "down"?,
              "pages": number?,
              "milliseconds": number?,
              "url": string?
            }
          }
        - If status is "done" or "failed", omit action.
        - If status is "continue", include action.
        - Do not use Markdown fences.
        - Write string fields in language tag \(languageTag) when practical.
        """
    }

    private func browserAgentRepairUserPrompt(
        rawOutput: String,
        parseError: BrowserAgentResponseParserError
    ) -> String {
        """
        The previous browser-agent response was not valid enough to parse.

        Parse failure:
        \(parseError.localizedDescription)

        Raw response:
        \(rawOutput)

        Return the repaired JSON object only.
        """
    }

    private func rollingSummarySystemPrompt(languageTag: String) -> String {
        """
        You maintain the rolling memory for eisonAI's in-app browser agent.

        Rewrite the browser-agent history into a compact working summary.

        Requirements:
        - Keep the summary concise and action-oriented.
        - Preserve completed milestones, failed attempts, current page state, and the next unresolved subgoal.
        - Prefer semantic descriptions over raw element indexes unless an index is still important.
        - Mention repeated loops or dead ends if they occurred.
        - Output plain text only, no bullets required, no Markdown fences.
        - Write in language tag \(languageTag) when practical.
        """
    }

    private func rollingSummaryUserPrompt(
        goal: String,
        existingSummary: String,
        newEntries: [BrowserAgentLogEntry]
    ) -> String {
        let newEntriesText = newEntries.map { entry in
            "[step \(entry.step)] \(entry.title): \(entry.detail)"
        }.joined(separator: "\n")

        return """
        Goal:
        \(goal)

        Existing rolling summary:
        \(existingSummary.isEmpty ? "(none yet)" : existingSummary)

        New entries to fold in:
        \(newEntriesText)

        Return the updated rolling summary only.
        """
    }

    private func normalizedRollingSummary(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return rollingHistorySummary }
        return String(cleaned.prefix(rollingSummaryCharacterLimit))
    }

    private func fallbackRollingSummary(
        goal: String,
        existingSummary: String,
        newEntries: [BrowserAgentLogEntry]
    ) -> String {
        let fallbackLines = newEntries.map { entry in
            "Step \(entry.step) \(entry.title): \(entry.detail)"
        }
        let merged = [
            existingSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            "Goal: \(goal)",
            fallbackLines.joined(separator: " "),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return String(merged.prefix(rollingSummaryCharacterLimit))
    }

    private func taskStatePromptJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(taskState),
              let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func formatDecisionLog(for response: BrowserAgentResponse) -> String {
        [
            "Evaluation: \(response.evaluationPreviousGoal)",
            "Memory: \(response.memory)",
            "Next: \(response.nextGoal)",
            response.summary?.isEmpty == false ? "Summary: \(response.summary!)" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

private enum BrowserRunError: LocalizedError {
    case missingAction

    var errorDescription: String? {
        switch self {
        case .missingAction:
            return "The browser agent did not return a next action."
        }
    }
}

private enum BrowserAgentModelOutputError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "The browser agent model returned an empty response."
        }
    }
}
