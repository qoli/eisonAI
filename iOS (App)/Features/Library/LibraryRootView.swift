import Foundation
import MarkdownUI
import SwiftUI

struct LibraryRootView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @StateObject private var syncCoordinator = RawLibrarySyncCoordinator.shared
    @StateObject private var translationCoordinator = PromptTranslationCoordinator.shared

    @State private var searchText: String = ""
    @State private var selection: Int = LibraryMode.all.rawValue
    @State private var selectedTag: String?
    @FocusState private var isSearchFocused: Bool
    @State private var deepLinkEntry: RawHistoryEntry?

    @State private var segmentedTransitionEdge: Edge = .trailing
    @State private var activeKeyPointInput: KeyPointInput?
    @State private var pollingTask: Task<Void, Never>?
    @State private var fullReloadToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppConfig.sharePollingEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var sharePollingEnabled = true
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
        let content = NavigationStack {
            libraryContent
        }
        #if canImport(Translation)
            if #available(iOS 17.4, macOS 14.4, macCatalyst 26.0, *) {
                content.translationTask(translationCoordinator.configuration) { session in
                    print("[TranslationTask] translationTask started")
                    await translationCoordinator.handleTranslation(session: session)
                    print("[TranslationTask] translationTask finished")
                }
            } else {
                content
            }
        #else
            content
        #endif
    }

    @ViewBuilder
    private var libraryContent: some View {
        searchPlacement(transitionContent)
            .navigationTitle("Library")
            .toolbar {
                toolbarContent
            }
            // KEYPOINT_CLIPBOARD_FLOW: sheet entry point for .clipboard/.share inputs
            .sheet(item: $activeKeyPointInput, onDismiss: {
                viewModel.reload()
            }) { input in
                ClipboardKeyPointSheet(input: input)
            }
            .sheet(isPresented: $isSyncErrorSheetPresented) {
                syncErrorSheet
            }
            .refreshable {
                performFullReload()
            }
            .task {
                viewModel.reload()
                ModelLanguageStore().ensureTranslatedPromptsOnLaunch()
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
                .id(LibraryContentID(mode: mode, reloadToken: fullReloadToken))
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
        // KEYPOINT_CLIPBOARD_FLOW: toolbar "+" sets .clipboard input
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

        #if !targetEnvironment(macCatalyst)
            // List Filter

            if UIDevice.current.userInterfaceIdiom == .pad {
                ToolbarItem(placement: .topBarTrailing) {
                    listFilterMenu
                }

            } else {
                ToolbarItem(placement: .bottomBar) {
                    listFilterMenu
                }

                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                }
            }

        #endif

        #if targetEnvironment(macCatalyst)
            ToolbarItem(placement: .topBarTrailing) {
                listFilterMenu
            }
        #endif

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
    }

    @ViewBuilder
    private var listFilterMenu: some View {
        Menu {
            Button {
                selectedTag = nil
            } label: {
                if selectedTag == nil {
                    Label("All Tags", systemImage: "checkmark.circle")
                } else {
                    Label("All Tags", systemImage: "circle")
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
                            Label("#\(tag)", systemImage: "checkmark.circle")
                        } else {
                            Label("#\(tag)", systemImage: "circle")
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
                Text(syncCoordinator.isSyncing ? "Syncing" : (syncCoordinator.lastErrorMessage != nil ? "Sync error" : "Sync"))
            } icon: {
                if syncCoordinator.isSyncing {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
                } else if syncCoordinator.lastErrorMessage != nil {
                    Image(systemName: "exclamationmark.icloud")
                } else {
                    Image(systemName: "checkmark.icloud")
                }
            }
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
        switch platform {
        case .macCatalyst:
            content.safeAreaInset(edge: .bottom) {
                searchBar
            }

        default:
            content.searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        }
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
            VStack {
                Spacer()
                VStack {
                    HStack {
                        Image("arrow")
                            .rotationEffect(.degrees(26), anchor: .center)
                            .opacity(0.6)

                        Spacer()
                    }
                    .frame(width: 200)
                    .padding(.bottom)

                    Text("Add your first material")
                        .font(.headline)
                    Text("Turn text or links into structured reading")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(width: 260)

                    Text("New materials you save will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.top)

                Spacer()
            }
        } else {
            List(visibleEntries) { entry in
                NavigationLink {
                    LibraryItemDetailView(
                        viewModel: viewModel,
                        entry: entry
                    )
                } label: {
                    LibraryItemRow(
                        entry: entry,
                        isFavorite: viewModel.isFavorited(entry),
                        onToggleFavorite: { viewModel.toggleFavorite(entry) },
                        onDelete: { viewModel.delete(entry) }
                    )
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
            .frame(maxWidth: isSearchFocused ? 320 : 180)
            .padding(.horizontal, 16)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
        .animation(.easeInOut(duration: 0.15), value: searchText)
        .padding(.bottom, 8)
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

    private func performFullReload() {
        viewModel.reload()
        syncCoordinator.syncNow()
        fullReloadToken = UUID()
    }
}

private struct LibraryContentID: Hashable {
    let mode: LibraryMode
    let reloadToken: UUID
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
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.metadata.tags.isEmpty {
                TagsText(tags: entry.metadata.tags)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.metadata.title.isEmpty ? "(no title)" : entry.metadata.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                        .accessibilityLabel("Favorite")
                }

                Spacer(minLength: 0)
            }

            Text(entry.metadata.summaryText.removingThinkTags().removingBlankLines())
                .foregroundStyle(.secondary)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.metadata.modelId.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(0.8)

                Text(createdAtText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(0.6)
            }
        }
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Text(isFavorite ? "Unfavorite" : "Favorite")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("Delete")
            }
        }
    }

    private var createdAtText: String {
        let date = entry.metadata.createdAt
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInYesterday(date) {
            let dayText = Self.relativeDayFormatter.string(from: date)
            let timeText = Self.timeFormatter.string(from: date)
            return "\(dayText) \(timeText)"
        }

        let dayInterval: TimeInterval = 24 * 60 * 60
        if abs(date.timeIntervalSince(now)) < dayInterval {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
        }

        return Self.dateTimeFormatter.string(from: date)
    }
}

#Preview("Empty State") {
    // Render LibraryRootView in its default state; with no user content
    // the view should present the built-in empty state UI.
    NavigationStack {
        LibraryRootView()
    }
}
