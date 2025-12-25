import Foundation
import SwiftUI

struct LibraryRootView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var syncCoordinator = RawLibrarySyncCoordinator.shared

    @State private var searchText: String = ""
    @State private var selection: Int = LibraryMode.all.rawValue
    @State private var selectedTag: String?
    @FocusState private var isSearchFocused: Bool
    @State private var deepLinkEntry: RawHistoryEntry?

    @State private var segmentedTransitionEdge: Edge = .trailing
    @State private var activeKeyPointInput: KeyPointInput?
    @State private var pollingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppConfig.sharePollingEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var sharePollingEnabled = false
    @State private var isSyncErrorSheetPresented = false

    private let sharePayloadStore = SharePayloadStore()

    private var mode: LibraryMode {
        LibraryMode(rawValue: selection) ?? .all
    }

    private var baseEntries: [RawHistoryEntry] {
        switch mode {
        case .all:
            return viewModel.entries
        case .favorites:
            return viewModel.entries.filter { viewModel.isFavorited($0) }
        }
    }

    private var availableTags: [String] {
        var counts: [String: Int] = [:]
        for entry in baseEntries {
            for tag in entry.metadata.tags {
                counts[tag, default: 0] += 1
            }
        }

        return counts.keys.sorted { lhs, rhs in
            let leftCount = counts[lhs, default: 0]
            let rightCount = counts[rhs, default: 0]
            if leftCount != rightCount {
                return leftCount > rightCount
            }
            return lhs < rhs
        }
    }

    private var visibleEntries: [RawHistoryEntry] {
        var base = baseEntries
        if let selectedTag, !selectedTag.isEmpty {
            base = base.filter { $0.metadata.tags.contains(selectedTag) }
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
            libraryContent
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        searchPlacement(transitionContent)
            .navigationTitle("Library")
            .toolbar {
                toolbarContent
            }
            .sheet(item: $activeKeyPointInput, onDismiss: {
                viewModel.reload()
            }) { input in
                ClipboardKeyPointSheet(input: input)
            }
            .sheet(isPresented: $isSyncErrorSheetPresented) {
                syncErrorSheet
            }
            .refreshable {
                viewModel.reload()
                syncCoordinator.syncNow()
            }
            .task {
                viewModel.reload()
            }
            .onAppear {
                viewModel.reload()
                refreshPolling(for: scenePhase)
                triggerSyncIfNeeded(for: scenePhase)
            }
            .onOpenURL { url in
                handleShareURL(url)
                handleNoteURL(url)
            }
            .onChange(of: scenePhase) { _, newValue in
                refreshPolling(for: newValue)
                triggerSyncIfNeeded(for: newValue)
            }
            .onChange(of: sharePollingEnabled) { _, _ in
                refreshPolling(for: scenePhase)
            }
            .onChange(of: syncCoordinator.lastCompletedAt) { _, _ in
                viewModel.reload()
            }
            .navigationDestination(item: $deepLinkEntry) { entry in
                LibraryItemDetailView(
                    viewModel: viewModel,
                    entry: entry
                )
            }
            .onChange(of: viewModel.entries) { _, newEntries in
                if let selectedTag, !newEntries.contains(where: { $0.metadata.tags.contains(selectedTag) }) {
                    self.selectedTag = nil
                }
            }
    }

    private var transitionContent: some View {
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                activeKeyPointInput = .clipboard
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Key-point from Clipboard")
        }

        ToolbarItem(placement: .title) {
            ZStack {
                Picker("", selection: $selection) {
                    if !syncCoordinator.isSyncing {
                        Image(systemName: "tray.full").tag(LibraryMode.all.rawValue)
                            .transition(.move(edge: .leading))
                        Image(systemName: "star").tag(LibraryMode.favorites.rawValue)
                            .transition(.move(edge: .trailing))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                CircleProgressView(state: syncCoordinator.progressState)
                    .frame(width: 16, height: 16, alignment: .center)
                    .opacity(syncCoordinator.isSyncing ? 1 : 0)
            }
            .animation(.easeInOut, value: syncCoordinator.isSyncing)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                syncStatusButton

                Divider()

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Label("Menu", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
        }

        #if !targetEnvironment(macCatalyst)
            // List Filter
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button {
                        selectedTag = nil
                    } label: {
                        if selectedTag == nil {
                            Label("All Tags", systemImage: "checkmark")
                        } else {
                            Text("All Tags")
                        }
                    }

                    Divider()

                    if availableTags.isEmpty {
                        Button("No tags") {}
                            .disabled(true)
                    } else {
                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                if selectedTag == tag {
                                    Label(tag, systemImage: "checkmark")
                                } else {
                                    Text(tag)
                                }
                            }
                        }
                    }
                } label: {
                    Label(
                        "Filter",
                        systemImage: selectedTag == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
                    )
                }
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .bottomBar)
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        #endif
    }

    private func triggerSyncIfNeeded(for phase: ScenePhase) {
        guard phase == .active else { return }
        Task {
            syncCoordinator.syncNow()
        }
    }

    @ViewBuilder
    private var syncStatusButton: some View {
        Button {
            if syncCoordinator.isSyncing {
                return
            }
            if syncCoordinator.lastErrorMessage != nil {
                isSyncErrorSheetPresented = true
            } else {
                syncCoordinator.syncNow()
            }
        } label: {
            Label {
                Text(syncCoordinator.isSyncing ? "Syncing" : (syncCoordinator.lastErrorMessage != nil ? "Sync error" : "Sync now"))
            } icon: {
                if syncCoordinator.isSyncing {
                    CircleProgressView(state: syncCoordinator.progressState)
                        .frame(width: 16, height: 16, alignment: .center)
                } else if syncCoordinator.lastErrorMessage != nil {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    Image(systemName: "checkmark")
                }
            }
            .labelStyle(.iconOnly)
            .frame(width: 24, height: 24)
        }
    }

    private var syncErrorSheet: some View {
        VStack(spacing: 16) {
            Text("Sync Failed")
                .font(.headline)
            Text(syncCoordinator.lastErrorMessage ?? "Unknown error.")
                .font(.callout)
                .multilineTextAlignment(.leading)

            HStack(spacing: 12) {
                Button("Dismiss") {
                    isSyncErrorSheetPresented = false
                    syncCoordinator.clearError()
                }
                .buttonStyle(.bordered)

                Button("Retry") {
                    isSyncErrorSheetPresented = false
                    syncCoordinator.syncNow()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func searchPlacement<Content: View>(_ content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
            content.safeAreaInset(edge: .bottom) {
                searchBar
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
                }
            } else if isPad {
                // On iPad, keep consistent bottom padding and a wider layout
                content.searchable(text: $searchText, placement: .toolbar, prompt: "Search")

            } else {
                // On iPhone, adjust bottom padding with focus to avoid jumping with keyboard
                content.searchable(text: $searchText, placement: .toolbar, prompt: "Search")
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
                #if targetEnvironment(macCatalyst)
                    VariableBlurView(maxBlurRadius: 1, direction: .blurredBottomClearTop)
                        .ignoresSafeArea()
                        .frame(height: 1)
                #endif
            }
        }
    }

    // 只有 macCatalyst 使用
    private var searchBar: some View {
        HStack {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassedEffect(in: .capsule, interactive: true)
            .frame(maxWidth: isSearchFocused ? .infinity : 180)
            .padding(.horizontal, 16)
            .padding(.trailing, 120)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
        .animation(.easeInOut(duration: 0.15), value: searchText)
        .padding(.bottom, 24)
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

    private func handleNoteURL(_ url: URL) {
        guard url.scheme?.lowercased() == "eisonai" else { return }
        guard url.host?.lowercased() == "note" else { return }
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
            !id.isEmpty
        else { return }

        Task { @MainActor in
            selection = LibraryMode.all.rawValue
            searchText = ""
            viewModel.reload()
            if let match = viewModel.entries.first(where: { $0.metadata.id == id }) {
                deepLinkEntry = nil
                deepLinkEntry = match
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

private struct CircleProgressView: View {
    static let progressColor = Color(
        red: 1,
        green: 201.0 / 255.0,
        blue: 63.0 / 255.0
    )

    let state: RawLibrarySyncProgressState
    private let lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.progressColor.opacity(0.2), lineWidth: lineWidth)

            switch state {
            case .waiting:
                CircleProgressForeverView(
                    color: Self.progressColor,
                    lineWidth: lineWidth,
                    progressForever: 0.25
                )
                .equatable()
            case let .progress(value):
                Circle()
                    .trim(from: 0.0, to: clampedProgress(value))
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(Self.progressColor)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func clampedProgress(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

private struct CircleProgressForeverView: View, Equatable {
    let color: Color
    let lineWidth: CGFloat
    let progressForever: CGFloat

    @State private var rotationForever: Angle = .degrees(0)

    var body: some View {
        Circle()
            .trim(from: 0.0, to: progressForever)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .foregroundStyle(color)
            .rotationEffect(rotationForever)
            .task {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    rotationForever = .degrees(360)
                }
            }
    }

    static func == (lhs: CircleProgressForeverView, rhs: CircleProgressForeverView) -> Bool {
        lhs.color == rhs.color &&
            lhs.lineWidth == rhs.lineWidth &&
            lhs.progressForever == rhs.progressForever
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
