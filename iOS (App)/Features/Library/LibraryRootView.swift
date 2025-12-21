import Foundation
import SwiftUI

struct LibraryRootView: View {
    @StateObject private var viewModel = LibraryViewModel()

    @State private var searchText: String = ""
    @State private var selection: Int = LibraryMode.all.rawValue
    @FocusState private var isSearchFocused: Bool

    @State private var segmentedTransitionEdge: Edge = .trailing
    @State private var activeKeyPointInput: KeyPointInput?
    @State private var pollingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppConfig.sharePollingEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var sharePollingEnabled = false

    private let sharePayloadStore = SharePayloadStore()

    private var mode: LibraryMode {
        LibraryMode(rawValue: selection) ?? .all
    }

    private var visibleEntries: [RawHistoryEntry] {
        var base: [RawHistoryEntry]
        switch mode {
        case .all:
            base = viewModel.entries
        case .favorites:
            base = viewModel.entries.filter { viewModel.isFavorited($0) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }

        let needle = query.localizedLowercase
        return base.filter { entry in
            let blob = [
                entry.metadata.title,
                entry.metadata.url,
                entry.metadata.summaryText,
                entry.metadata.modelId,
            ]
            .joined(separator: "\n")
            .localizedLowercase
            return blob.contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            searchPlacement(
                ZStack {
                    mainContent
                        .id(mode)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: segmentedTransitionEdge).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
                .animation(.easeInOut(duration: 0.25), value: selection)
                .onChange(of: selection) { oldValue, newValue in
                    segmentedTransitionEdge = newValue >= oldValue ? .trailing : .leading
                }
            )
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        activeKeyPointInput = .clipboard
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Key-point from Clipboard")
                }

                ToolbarItem(placement: .title) {
                    Picker("", selection: $selection) {
                        Image(systemName: "tray.full").tag(LibraryMode.all.rawValue)
                        Image(systemName: "star").tag(LibraryMode.favorites.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $activeKeyPointInput, onDismiss: {
                viewModel.reload()
            }) { input in
                ClipboardKeyPointSheet(input: input)
            }
            .refreshable {
                viewModel.reload()
            }
            .task {
                viewModel.reload()
            }
            .onAppear {
                viewModel.reload()
                refreshPolling(for: scenePhase)
            }
            .onOpenURL { url in
                handleShareURL(url)
            }
            .onChange(of: scenePhase) { _, newValue in
                refreshPolling(for: newValue)
            }
            .onChange(of: sharePollingEnabled) { _, _ in
                refreshPolling(for: scenePhase)
            }
        }
    }

    @ViewBuilder
    private func searchPlacement<Content: View>(_ content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
//            content
//            .searchable(text: $searchText, placement: .toolbarPrincipal, prompt: "Search")
//            會歪的，https://x.com/llqoli/status/2001990991092531532

            content.safeAreaInset(edge: .bottom) {
                searchBar
                    .padding(.bottom, 26)
            }
        #else

            // iPad detection and handling: use a wider, non-collapsing search bar on iPad
            let isPad: Bool = {
                #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad { return true }
                #endif
                return false
            }()

            if #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac {
                content.safeAreaInset(edge: .bottom) {
                    searchBar
                        .padding(.bottom, 26)
                }
            } else if isPad {
                // On iPad, keep consistent bottom padding and a wider layout
                content.searchable(text: $searchText, placement: .toolbar, prompt: "Search")

            } else {
                // On iPhone, adjust bottom padding with focus to avoid jumping with keyboard
                content.searchable(text: $searchText, placement: .toolbar, prompt: "Search")
//                content.safeAreaInset(edge: .bottom) {
//                    searchBar
//                        .padding(.bottom, isSearchFocused ? 26 : 0)
//                }
            }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if let error = viewModel.errorMessage, !error.isEmpty {
            ContentUnavailableView {
                Label("Load Failed", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(error)
            } actions: {
                Button("Reload") { viewModel.reload() }
            }
        } else if visibleEntries.isEmpty {
            ContentUnavailableView {
                Label("No Material", systemImage: "tray.fill")
            } description: {
                Text("New materials you save will appear here.")
            } actions: {
                Button("Reload") { viewModel.reload() }
            }
        } else {
            List(visibleEntries) { entry in
                NavigationLink {
                    LibraryItemDetailView(
                        viewModel: viewModel,
                        entry: entry
                    )
                } label: {
                    LibraryItemRow(entry: entry, isFavorite: viewModel.isFavorited(entry))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        viewModel.toggleFavorite(entry)
                    } label: {
                        Text(viewModel.isFavorited(entry) ? "Unfavorite" : "Favorite")
                    }
                    .tint(viewModel.isFavorited(entry) ? .gray : .yellow)

                    Button(role: .destructive) {
                        viewModel.delete(entry)
                    } label: {
                        Text("Delete")
                    }
                }
            }
            .listStyle(.automatic)
            .animation(.easeInOut(duration: 0.15), value: visibleEntries.map(\.id))
            .overlay(alignment: .bottom) {
                VariableBlurView(maxBlurRadius: 1, direction: .blurredBottomClearTop)
                    .ignoresSafeArea()
                    .frame(height: 1)
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.done)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
//        .librarySearchBarBackground()
        .glassedEffect(in: .capsule, interactive: true)
        .frame(maxWidth: isSearchFocused ? .infinity : 260)
        .padding(.horizontal, isSearchFocused ? 12 : 80)
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
        .animation(.easeInOut(duration: 0.15), value: searchText)
        .offset(y: 10)
    }

    private func handleShareURL(_ url: URL) {
        guard url.scheme?.lowercased() == "eisonai" else { return }
        guard url.host?.lowercased() == "share" else { return }
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
            !id.isEmpty
        else { return }

        #if DEBUG
            print("[SharePayload] received url: \(url.absoluteString)")
        #endif

        Task {
            do {
                if let payload = try sharePayloadStore.loadAndDelete(id: id) {
                    #if DEBUG
                        let urlSummary = payload.url ?? "nil"
                        let textCount = payload.text?.count ?? 0
                        let titleSummary = payload.title ?? "nil"
                        print("[SharePayload] loaded id=\(payload.id) url=\(urlSummary) textCount=\(textCount) title=\(titleSummary)")
                    #endif
                    await MainActor.run {
                        activeKeyPointInput = .share(payload)
                    }
                } else {
                    #if DEBUG
                        print("[SharePayload] payload not found for id=\(id)")
                    #endif
                }
            } catch {
                #if DEBUG
                    print("[SharePayload] Failed to load payload: \(error)")
                #endif
            }
        }
    }

    @MainActor
    private func checkForSharePayloadOnce() async {
        guard activeKeyPointInput == nil else { return }
        do {
            if let payload = try sharePayloadStore.loadNextPending() {
                #if DEBUG
                    let urlSummary = payload.url ?? "nil"
                    let textCount = payload.text?.count ?? 0
                    let titleSummary = payload.title ?? "nil"
                    print("[SharePayload] polled id=\(payload.id) url=\(urlSummary) textCount=\(textCount) title=\(titleSummary)")
                #endif
                activeKeyPointInput = .share(payload)
            }
        } catch {
            #if DEBUG
                print("[SharePayload] poll failed: \(error)")
            #endif
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2000000000)
                if Task.isCancelled { break }
                await checkForSharePayloadOnce()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refreshPolling(for phase: ScenePhase) {
        guard phase == .active, sharePollingEnabled else {
            stopPolling()
            return
        }

        Task { await checkForSharePayloadOnce() }
        startPolling()
    }
}

private struct LibraryItemRow: View {
    var entry: RawHistoryEntry
    var isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                    .font(.headline)
                    .lineLimit(1)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Favorite")
                }

                Spacer(minLength: 0)
            }

            Text(entry.metadata.summaryText)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("·")
                Text(entry.metadata.modelId)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 6)
    }
}

extension View {
    @ViewBuilder
    func librarySearchBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular)

        } else {
            background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
