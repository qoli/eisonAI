//
//  llmView.swift
//  iOS
//
//  Created by 黃佁媛 on 12/14/25.
//

import SwiftUI

import EisonAIKit

struct llmView: View {
    @State private var statusText: String = "idle"
    @State private var outputText: String = ""
    @State private var isRunning: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LLM Demo")
                .font(.title2)

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(isRunning ? "Running..." : "Run") {
                Task { await runDemo() }
            }
            .disabled(isRunning)

            ScrollView {
                Text(outputText.isEmpty ? "—" : outputText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

private actor LLMDemoRunner {
    static let shared = LLMDemoRunner()
    @available(iOS 18.0, macOS 15.0, *)
    private var model: AnyLanguageModel.CoreMLLanguageModel?

    func run() async throws -> String {
        if #available(iOS 26.0, *) {
            return try await runAnyLanguageModelDemo()
        }
        return try await runCoreMLDemo()
    }

    @available(iOS 26.0, *)
    private func runAnyLanguageModelDemo() async throws -> String {
        let model = AnyLanguageModel.SystemLanguageModel.default
        let session = AnyLanguageModel.LanguageModelSession(model: model, tools: [WeatherTool()])

        let response = try await session.respond {
            AnyLanguageModel.Prompt("How's the weather in Cupertino?")
        }
        return response.content
    }

    private func runCoreMLDemo() async throws -> String {
        guard #available(iOS 18.0, macOS 15.0, *) else {
            throw NSError(domain: "EisonAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "CoreML model requires iOS 18 / macOS 15"])
        }

        let model = try await getModel()
        let session = AnyLanguageModel.LanguageModelSession(model: model, instructions: "你是一個簡潔的助手。")
        let options = AnyLanguageModel.GenerationOptions(temperature: 0.2, maximumResponseTokens: 200)
        let response: AnyLanguageModel.LanguageModelSession.Response<String> = try await session.respond(
            to: AnyLanguageModel.Prompt("用一句話介紹你自己。"),
            options: options
        )
        return response.content
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func getModel() async throws -> AnyLanguageModel.CoreMLLanguageModel {
        if let model {
            return model
        }

        let repoId = "XDGCC/coreml-Qwen3-0.6B"
        let revision = "fc6bdeb0b02573744ee2cba7e3f408f2851adf57"
        let appGroupID = "group.com.qoli.eisonAI"

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }

        let modelRoot = container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        let compiledURL = modelRoot.appendingPathComponent("Qwen3-0.6B.mlmodelc", isDirectory: true)
        let loaded = try await AnyLanguageModel.CoreMLLanguageModel(url: compiledURL, computeUnits: .all)
        self.model = loaded
        return loaded
    }
}

private struct WeatherTool: AnyLanguageModel.Tool {
    let name = "getWeather"
    let description = "Retrieve the latest weather information for a city"

    @AnyLanguageModel.Generable
    struct Arguments {
        @AnyLanguageModel.Guide(description: "The city to fetch the weather for")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        "The weather in \(arguments.city) is sunny and 72°F / 23°C"
    }
}

@MainActor
private extension llmView {
    func runDemo() async {
        isRunning = true
        statusText = "running"
        outputText = ""
        do {
            outputText = try await LLMDemoRunner.shared.run()
            statusText = "done"
        } catch {
            statusText = "error"
            outputText = error.localizedDescription
        }
        isRunning = false
    }
}

#Preview {
    llmView()
}
