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
    private var modelContainer: ModelContainer?

    func run() async throws -> String {
        if #available(iOS 26.0, *) {
            return try await runAnyLanguageModelDemo()
        } else {
            return try await runMLXDemo()
        }
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

    private func runMLXDemo() async throws -> String {
        let container = try await getModelContainer()
        let generateParameters = GenerateParameters(maxTokens: 200, temperature: 0.2)

        let session = ChatSession(container, instructions: "你是一個簡潔的助手。", generateParameters: generateParameters)
        return try await session.respond(to: "用一句話介紹你自己。")
    }

    private func getModelContainer() async throws -> ModelContainer {
        if let modelContainer {
            return modelContainer
        }

        let repoId = "lmstudio-community/Qwen3-0.6B-MLX-4bit"
        let revision = "75429955681c1850a9c8723767fe4252da06eb57"
        let appGroupID = "group.com.qoli.eisonAI"

        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw NSError(domain: "EisonAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 容器不可用"])
        }

        let modelDir = container
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(repoId, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)

        let configuration = ModelConfiguration(directory: modelDir)
        let loaded = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        modelContainer = loaded
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
