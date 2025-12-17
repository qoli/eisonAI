//
//  AppDelegate.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    #if targetEnvironment(macCatalyst)
        private var sceneObserverTokens: [NSObjectProtocol] = []
    #endif

    deinit {
        #if targetEnvironment(macCatalyst)
            for token in sceneObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
        #endif
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                DispatchQueue.main.async { [weak self] in
                    self?.configureIOSAppOnMacWindowTitles(for: application)
                }
            }
        #endif
        #if targetEnvironment(macCatalyst)
            sceneObserverTokens.append(
                NotificationCenter.default.addObserver(
                    forName: UIScene.willConnectNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let windowScene = notification.object as? UIWindowScene else { return }
                    self?.configureMacCatalystTitlebar(for: windowScene)
                }
            )

            sceneObserverTokens.append(
                NotificationCenter.default.addObserver(
                    forName: UIScene.didActivateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let windowScene = notification.object as? UIWindowScene else { return }
                    self?.configureMacCatalystTitlebar(for: windowScene)
                }
            )

            DispatchQueue.main.async { [weak self] in
                self?.configureMacCatalystTitlebars(for: application)
            }
        #endif
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        #if !targetEnvironment(macCatalyst)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                configureIOSAppOnMacWindowTitles(for: application)
            }
        #endif
        #if targetEnvironment(macCatalyst)
            configureMacCatalystTitlebars(for: application)
        #endif
    }

    #if !targetEnvironment(macCatalyst)
        private func configureIOSAppOnMacWindowTitles(for application: UIApplication) {
            for scene in application.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windowScene.title = ""
            }
        }
    #endif

    #if targetEnvironment(macCatalyst)
        private func configureMacCatalystTitlebars(for application: UIApplication) {
            for scene in application.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                configureMacCatalystTitlebar(for: windowScene)
            }
        }

        private func configureMacCatalystTitlebar(for windowScene: UIWindowScene) {
            guard let titlebar = windowScene.titlebar else { return }
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
    #endif
}

@main
struct EisonAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private enum AppConfig {
    static let appGroupIdentifier = "group.com.qoli.eisonAI"
    static let systemPromptKey = "eison.systemPrompt"
    static let rawLibraryItemsPathComponents = ["RawLibrary", "Items"]

    static let defaultSystemPrompt = """
你是一個資料整理員。

Summarize this post in 5-6 sentences.
Emphasize the key insights and main takeaways.

以繁體中文輸出。
"""
}

private struct SystemPromptStore {
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppConfig.appGroupIdentifier) }

    func load() -> String {
        guard let stored = defaults?.string(forKey: AppConfig.systemPromptKey) else {
            return AppConfig.defaultSystemPrompt
        }
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppConfig.defaultSystemPrompt
        }
        return stored
    }

    func save(_ value: String?) {
        guard let defaults else { return }
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppConfig.systemPromptKey)
        } else {
            defaults.set(trimmed, forKey: AppConfig.systemPromptKey)
        }
    }
}

private struct RootView: View {
    private let store = SystemPromptStore()

    @State private var draftPrompt = ""
    @State private var status = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Safari Extension") {
                    Text("Enable eisonAI’s Safari extension in Settings → Safari → Extensions.")
                    Text("Summaries run in the extension popup via WebLLM (bundled assets).")
                        .foregroundStyle(.secondary)
                }

                Section("History") {
                    NavigationLink("View history") {
                        HistoryView()
                    }
                    Text("Saved summaries are stored in the shared App Group folder.")
                        .foregroundStyle(.secondary)
                }

                Section("System prompt") {
                    Text("Used by the Safari extension popup summary.")
                        .foregroundStyle(.secondary)

                    TextEditor(text: $draftPrompt)
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    HStack {
                        Button("Save") {
                            store.save(draftPrompt)
                            draftPrompt = store.load()
                            status = "Saved."
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset to default") {
                            store.save(nil)
                            draftPrompt = store.load()
                            status = "Reset to default."
                        }
                        .buttonStyle(.bordered)
                    }

                    if !status.isEmpty {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("eisonAI")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draftPrompt = store.load()
        }
    }
}

private struct RawHistoryItemMetadata: Codable, Identifiable {
    var v: Int
    var id: String
    var createdAt: Date
    var url: String
    var title: String
    var summaryText: String
    var modelId: String
}

private struct RawHistoryItem: Codable, Identifiable {
    var v: Int
    var id: String
    var createdAt: Date
    var url: String
    var title: String
    var articleText: String
    var summaryText: String
    var systemPrompt: String
    var userPrompt: String
    var modelId: String
}

private struct RawHistoryEntry: Identifiable {
    var fileURL: URL
    var metadata: RawHistoryItemMetadata

    var id: String { fileURL.lastPathComponent }
}

private struct RawLibraryStore {
    private let fileManager = FileManager.default

    func itemsDirectoryURL() throws -> URL {
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier
            )
        else {
            throw NSError(
                domain: "EisonAI.RawLibrary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container is unavailable."]
            )
        }

        var url = containerURL
        for component in AppConfig.rawLibraryItemsPathComponents {
            url.appendPathComponent(component, isDirectory: true)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    func listEntries() throws -> [RawHistoryEntry] {
        let directoryURL = try itemsDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = fileURLs
            .filter { $0.pathExtension.lowercased() == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [RawHistoryEntry] = []
        entries.reserveCapacity(jsonFiles.count)

        for fileURL in jsonFiles {
            do {
                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                let metadata = try decoder.decode(RawHistoryItemMetadata.self, from: data)
                entries.append(RawHistoryEntry(fileURL: fileURL, metadata: metadata))
            } catch {
                // Ignore malformed entries; they can be deleted from the filesystem if needed.
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.metadata.createdAt != rhs.metadata.createdAt {
                return lhs.metadata.createdAt > rhs.metadata.createdAt
            }
            return lhs.fileURL.lastPathComponent > rhs.fileURL.lastPathComponent
        }
    }

    func loadItem(fileURL: URL) throws -> RawHistoryItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try decoder.decode(RawHistoryItem.self, from: data)
    }

    func deleteItem(fileURL: URL) throws {
        try fileManager.removeItem(at: fileURL)
    }

    func clearAll() throws {
        let directoryURL = try itemsDirectoryURL()
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "json" {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

@MainActor
private final class HistoryViewModel: ObservableObject {
    @Published var entries: [RawHistoryEntry] = []
    @Published var errorMessage: String?

    private let store = RawLibraryStore()

    func reload() {
        do {
            errorMessage = nil
            entries = try store.listEntries()
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
    }

    func delete(at offsets: IndexSet) {
        let targets = offsets.map { entries[$0] }
        for entry in targets {
            do {
                try store.deleteItem(fileURL: entry.fileURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reload()
    }

    func clearAll() {
        do {
            try store.clearAll()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDetail(for entry: RawHistoryEntry) -> RawHistoryItem? {
        do {
            return try store.loadItem(fileURL: entry.fileURL)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(viewModel.entries) { entry in
                    NavigationLink {
                        HistoryDetailView(entry: entry, viewModel: viewModel)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                                .font(.headline)
                                .lineLimit(2)

                            if !entry.metadata.url.isEmpty {
                                Text(entry.metadata.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(entry.metadata.summaryText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: viewModel.delete)
            } header: {
                Text("Saved summaries (\(viewModel.entries.count))")
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear All", role: .destructive) {
                    showClearConfirmation = true
                }
                .disabled(viewModel.entries.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
        }
        .refreshable {
            viewModel.reload()
        }
        .task {
            viewModel.reload()
        }
        .onAppear {
            viewModel.reload()
        }
    }
}

private struct HistoryDetailView: View {
    var entry: RawHistoryEntry
    @ObservedObject var viewModel: HistoryViewModel

    @State private var item: RawHistoryItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                    .font(.title3)
                    .bold()

                VStack(alignment: .leading, spacing: 6) {
                    if !entry.metadata.url.isEmpty {
                        Text(entry.metadata.url)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Model: \(entry.metadata.modelId)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let item {
                    GroupBox("Summary") {
                        Text(item.summaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Article") {
                        Text(item.articleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            item = viewModel.loadDetail(for: entry)
        }
    }
}
