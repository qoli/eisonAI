//
//  OnboardingView.swift
//  SwiftUIPreview
//
//  Created by 黃佁媛 on 12/31/25.
//

import Combine
import Drops
import Foundation
import MarkdownUI
import StoreKit
import SwiftUI
import UIKit

struct UnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat = 0
    var topTrailingRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var style: RoundedCornerStyle = .circular

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = min(min(topLeadingRadius, rect.width / 2), rect.height / 2)
        let tr = min(min(topTrailingRadius, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeadingRadius, rect.width / 2), rect.height / 2)
        let br = min(min(bottomTrailingRadius, rect.width / 2), rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr,
                    startAngle: Angle(degrees: -90),
                    endAngle: Angle(degrees: 0),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 270),
                    clockwise: false)
        path.closeSubpath()

        return path
    }
}

struct OnboardingView: View {
    let onGetLifetimeAccess: () -> Void
    private struct BionicLine: Equatable {
        let text: String
        let boldParts: [String]
    }

    private struct OnboardingCopy: Equatable {
        let line1: BionicLine
        let line2: BionicLine
        let line3: BionicLine
    }

    private let onboardingCopies: [OnboardingCopy] = [
        OnboardingCopy(
            line1: BionicLine(
                text: "Language is not just output",
                boldParts: ["Lang", "is", "not", "just", "out"]
            ),
            line2: BionicLine(
                text: "It defines how ideas are formed",
                boldParts: ["I", "defi", "h", "ide", "a", "for"]
            ),
            line3: BionicLine(
                text: "Before they become words",
                boldParts: []
            )
        ),
        OnboardingCopy(
            line1: BionicLine(
                text: "Read less linearly",
                boldParts: ["Re", "le", "line"]
            ),
            line2: BionicLine(
                text: "Think more deliberately",
                boldParts: ["Thi", "mo", "delib"]
            ),
            line3: BionicLine(
                text: "Make structure visible",
                boldParts: []
            )
        ),
        OnboardingCopy(
            line1: BionicLine(
                text: "Begin with structure",
                boldParts: ["Beg", "wi", "struc"]
            ),
            line2: BionicLine(
                text: "Let AI surface what matters",
                boldParts: ["L", "A", "surf", "wh", "matt"]
            ),
            line3: BionicLine(
                text: "Then choose where to focus",
                boldParts: []
            )
        ),
        OnboardingCopy(
            line1: BionicLine(text: "", boldParts: []),
            line2: BionicLine(text: "", boldParts: []),
            line3: BionicLine(text: "", boldParts: [])
        ),
    ]

    private let longTextSentences = [
        "Most texts ask you to follow a path that was convenient to write, not a path designed for understanding.",
        "The structure often mirrors the author’s process: how the idea was discovered, how it unfolded over time, how one thought led to the next.",
        "But discovery order is not the same as comprehension order.",
        "Paragraph follows paragraph, sentence after sentence, each one assuming the previous context is still active in the reader’s mind.",
        "Understanding is treated as something that simply accumulates through exposure — as if reading long enough were enough to make meaning emerge.",
        "In practice, this rarely happens.",
        "Ideas do not line up neatly.",
        "Important background information often appears only after it is needed.",
        "Key assumptions are introduced quietly, without being marked as such, leaving readers unsure whether they missed something earlier or are expected to accept it now.",
        "Transitions happen without warning.",
        "One concept gives way to another, not because the reader is ready, but because the sequence demands it.",
        "As a result, reading becomes an exercise in constant adjustment.",
        "You read on, trying to keep everything in mind at once — what was already said, what might become important later, what you are not fully confident you understood, but are afraid to stop and re-evaluate.",
        "The effort shifts.",
        "Instead of judging ideas, you focus on staying oriented.",
        "Instead of thinking critically, you track position, maintain sequence, and guess which parts matter more than others.",
        "This is why long texts feel heavy even when the ideas themselves are simple.",
        "Cognitive energy is spent preserving continuity — holding fragments together long enough to reach the end.",
        "By the time you do, you may remember what was written, recall specific phrases or examples, and even summarize the content accurately.",
        "Yet the real decisions — the points where meaning actually formed — remain difficult to locate.",
        "Not because they were absent, but because they were never structurally visible.",
        "This is not a problem of attention, or discipline, or reading ability.",
        "It is not caused by the content itself.",
        "It is a structural problem.",
    ]

    @State private var selectedPage = 0
    @State private var textAnimationToken = 0
    @State private var isForwardTransition = true
    @State private var modelLanguageTag = ""
    @State private var productScrollOffset: CGFloat = 0
    @State private var productScrollViewportHeight: CGFloat = 1
    @State private var lifetimeProduct: Product?
    @State private var isPurchasing = false
    @State private var isPurchased = false
    @State private var purchaseErrorMessage: String?
    @State private var hasLoadedStore = false

    private var currentCopy: OnboardingCopy {
        onboardingCopy(for: selectedPage)
    }

    init(defaultPage: Int = 0, onGetLifetimeAccess: @escaping () -> Void = {}) {
        let clamped = max(0, min(defaultPage, onboardingCopies.count - 1))
        _selectedPage = State(initialValue: clamped)
        self.onGetLifetimeAccess = onGetLifetimeAccess
    }

    var body: some View {
        ZStack {
            mainView()

            if selectedPage != 3 {
                logoView()
            }

            actionButton()
        }
        .ifMacCatalyst({ view in
            view.padding(.bottom, 24)
        })
        .ifIPad({ view in
            view.padding(.bottom, 24)
        })
        .task {
            await configureStoreIfNeeded()
        }
        .task {
            await listenForTransactions()
        }
        .alert("Purchase Error", isPresented: Binding(
            get: { purchaseErrorMessage != nil },
            set: { isPresented in
                if !isPresented { purchaseErrorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseErrorMessage ?? "")
        }
        .onAppear {
            guard modelLanguageTag.isEmpty else { return }
            let store = ModelLanguageStore()
            let tag = store.loadOrRecommended()
            modelLanguageTag = tag
            store.save(tag)
        }
    }

    @ViewBuilder func actionButton() -> some View {
        VStack {
            Spacer()

            HStack(spacing: 6) {
                ForEach(onboardingCopies.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .frame(
                            width: selectedPage == index ? 16 : 4,
                            height: 4
                        )
                        .foregroundStyle(selectedPage == index ? Color.primary : Color.secondary)
                }
            }
            .padding(.bottom, 4)

            Button {
                if selectedPage == 3 {
                    if isPurchased {
                        onGetLifetimeAccess()
                    } else {
                        Task { await purchaseLifetimeAccess() }
                    }
                } else {
                    goToPage(selectedPage + 1)
                }
            } label: {
                HStack {
                    Text(selectedPage == 0 ? "Get started" :
                        selectedPage == 3 ? "Get Lifetime Access" : "Continue")
                }
                .padding(.vertical, 6)
                .frame(width: 180)
            }
            .buttonStyle(
                BorderedTintButtonStyle(
                    tint: .primary,
                    stroke: .primary,
                    foreground: Color(uiColor: UIColor.systemBackground)
                )
            )
        }
        .animation(.easeInOut, value: selectedPage)
    }

    @ViewBuilder func mainView() -> some View {
        VStack {
            Spacer()

            Color.clear.frame(height: 40)

            // Like TabView
            ZStack {
                if selectedPage == 0 {
                    modelLanguagePage()
                        .transition(pageTransition)
                }

                if selectedPage == 1 {
                    longTextPage()
                        .transition(pageTransition)
                }

                if selectedPage == 2 {
                    keyPointView()
                        .transition(pageTransition)
                        .offset(y: -24)
                }

                if selectedPage == 3 {
                    productView()
                        .transition(pageTransition)
                        .padding(.top, -180)
                        .padding(.bottom, -256)
                        .frame(maxWidth: 480)
                }
            }
            .padding(.top, 48)
            .padding(.bottom, 64)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let threshold: CGFloat = 48
                        if value.translation.width < -threshold {
                            goToPage(selectedPage + 1)
                        } else if value.translation.width > threshold {
                            goToPage(selectedPage - 1)
                        }
                    }
            )
            .onChange(of: selectedPage) { _, newValue in
                animateOnboardingTextChange(to: newValue)
            }

            if selectedPage != 3 {
                OnboardingText(
                    currentCopy,
                    animationToken: textAnimationToken
                )
            } else {
                VStack {
                    HStack {
                        Text("Unlock Full Access")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, -4)
                    .padding(.top)

                    // Paywall-Button
                    Button {
                        Task { await purchaseLifetimeAccess() }
                    } label: {
                        HStack {
                            ZStack {
                                Image(systemName: "checkmark.seal.fill")
                            }
                            .frame(width: 18, height: 18)
                            .padding(.trailing, 8)
                            .fontWeight(.bold)

                            Text("Lifetime Access")
                                .font(.headline)

                            Spacer()

                            Text(lifetimePriceLabel)
                                .fontWeight(.bold)
                        }
                        .padding(.all, 20)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.1))
                    }
                    .padding(.horizontal)
                    .disabled(isPurchasing || isPurchased || lifetimeProduct == nil)

                    // Paywall-Button
                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack {
                            ZStack {
                                Image(systemName: "purchased")
                            }
                            .frame(width: 18, height: 18)
                            .padding(.trailing, 8)
                            .fontWeight(.bold)

                            Text("Restore Purchases")
                                .font(.headline)

                            Spacer()
                        }
                        .padding(.all, 20)
                    }
                    .buttonStyle(.plain)
                    .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                    .padding(.horizontal)

                    #if DEBUG
                        Button {
                            onGetLifetimeAccess()
                        } label: {
                            HStack {
                                ZStack {
                                    Image(systemName: "ladybug.fill")
                                }
                                .frame(width: 18, height: 18)
                                .padding(.trailing, 8)
                                .fontWeight(.bold)

                                Text("Skip Onboarding (Debug)")
                                    .font(.headline)

                                Spacer()
                            }
                            .padding(.all, 20)
                        }
                        .buttonStyle(.plain)
                        .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                        .padding(.horizontal)
                    #endif

                    HStack {
                        Text("No subscription. Restore anytime.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 70)
                }
                .frame(maxWidth: 480)
            }
            Spacer()
        }
    }

    @ViewBuilder private func OnboardingText(
        _ copy: OnboardingCopy,
        animationToken: Int
    ) -> some View {
        VStack(alignment: .center, spacing: 12) {
            VStack(spacing: 6) {
                ScrambleText(
                    text: copy.line1.text,
                    boldParts: copy.line1.boldParts,
                    trigger: animationToken,
                    delay: 0,
                    fontSize: 22
                )
                .lineLimit(1)

                ScrambleText(
                    text: copy.line2.text,
                    boldParts: copy.line2.boldParts,
                    trigger: animationToken,
                    delay: 0.12,
                    fontSize: 22
                )
                .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)

            Divider().frame(width: 32)

            VStack(spacing: 6) {
                ScrambleText(text: copy.line3.text, boldParts: copy.line3.boldParts, trigger: animationToken, delay: 0.24, useBionic: false)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .lineLimit(1)

                Text("Cognitive Index™")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .opacity(0.6)
                    .lineLimit(1)
            }

            Color.clear.frame(height: 1)
                .padding(.top, -1)
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder func keyPointView() -> some View {
        VStack {
            HStack {
                Image(systemName: "quote.opening")
                    .font(.caption2)
                    .fontWeight(.semibold)

                Text("Cognitive Index")
                    .font(.caption2)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.top, 6)
            .padding(.bottom, 20)
            .padding(.horizontal, 16)
            .background {
                Color.secondary.opacity(0.15)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            topTrailingRadius: 16,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            style: .continuous
                        )
                    )
            }
            .offset(y: 24)

            ScrollView {
                VStack {
                    Markdown("""
                    # Reading challenge: Structure, not content

                    ### Problem:

                    *   **Unhelpful order**: The writing order isn't the comprehension order.
                    *   **Missing structure**: Key assumptions hide in plain sight; background arrives too late.
                    *   **Abrupt transitions**: You keep adjusting instead of thinking.

                    ### Result:

                    *   **Recall without clarity**: You can summarize, but can't locate where meaning formed.
                    *   **Cognitive load**: Tracking position replaces judgment.

                    ### Conclusion:

                    *   The problem isn't the content — it's the structure.
                    """)
                    .markdownTheme(.librarySummary)
                }
                .padding(.vertical, -32)
                .padding(.horizontal, -46)
                .scaleEffect(0.7)
            }
            .scrollDisabled(true)
            .allowsHitTesting(false)
            .scrollIndicators(.hidden)
            .font(.footnote)
            .frame(width: 320)
            .frame(maxHeight: 240)
            .mask {
                LinearGradient(
                    colors: [.black, .black, .black, .clear],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            .overlay(alignment: .bottom) {
                IridescentOrbView()
                    .padding(.all, 8)
                    .glassedEffect(in: .circle, interactive: true)
                    .offset(y: 26)
            }
        }
        .frame(width: 320)
        .frame(height: 240)
    }

    @ViewBuilder private func modelLanguagePage() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Language of Thought")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()
            }

            Text("Choose the language eisonAI uses to think and write.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(ModelLanguage.supported) { language in
                    Button(language.displayName) {
                        modelLanguageTag = language.tag
                        ModelLanguageStore().save(language.tag)
                    }
                }
            } label: {
                HStack {
                    Text(ModelLanguage.displayName(forTag: modelLanguageTag))
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
            .padding()
            .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)

            Text("You can change this later at any time.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(width: 320, height: 240)
    }

    @ViewBuilder private func productView() -> some View {
        ScrollView {
            Color.clear.frame(height: 120)

            HStack {
                Image("ImageLogo")
                Image("TextLogo")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom)

            welcomePage()
                .padding(.horizontal, 28)

            // CheckList
            let checklistItems: [ProductChecklistItem] = [
                ProductChecklistItem(
                    title: "Cognitive Index™",
                    text: "Make structure visible",
                    description: "Scan ideas at a glance without breaking flow.",
                    symbolName: "viewfinder.circle",
                    color: .red
                ),
                ProductChecklistItem(
                    title: "Long-Document",
                    text: "Up to 15,000 tokens",
                    description: "Segmented processing keeps long reads fast.",
                    symbolName: "doc.text.magnifyingglass",
                    color: .orange
                ),
                ProductChecklistItem(
                    title: "Safari Extension",
                    text: "Works right in Safari",
                    description: "See structure on-page without leaving Safari.",
                    symbolName: "puzzlepiece.extension",
                    color: .yellow
                ),
                ProductChecklistItem(
                    title: "Local-First",
                    text: "On-device privacy",
                    description: "Read privately, even on sensitive content.",
                    symbolName: "lock.square",
                    color: .green
                ),
                ProductChecklistItem(
                    title: "Source Trust",
                    text: "Verify what you read",
                    description: "Verify sources, not slogans.",
                    symbolName: "checkmark.seal.fill",
                    color: .blue
                ),
                ProductChecklistItem(
                    title: "Library & Tags",
                    text: "Organize what matters",
                    description: "Tags make review and retrieval effortless.",
                    symbolName: "books.vertical",
                    color: .purple
                ),
            ]

            VStack(spacing: 18) {
                ForEach(Array(checklistItems.enumerated()), id: \.offset) { index, item in
                    ProductChecklistRow(
                        item: item,
                        index: index,
                        viewportHeight: productScrollViewportHeight
                    )
                }
            }
            .padding()
            .padding(.horizontal, 14)

            // 協議

            Divider()
                .padding(.vertical)
                .padding(.horizontal, 32)

            HStack {
                Button("Terms of Service") {
                    // TODO: add URL once confirmed
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("Privacy Policy") {
                    // TODO: add URL once confirmed
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            Color.clear.frame(height: 210)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "ProductScroll")
        .onAppear {
            updateProductScrollViewportHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateProductScrollViewportHeight()
        }
        .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in
            scrollGeometry.contentOffset.y
        } action: { _, newValue in
            productScrollOffset = newValue
        }
        .onChange(of: productScrollOffset) { _, newValue in
            print("ProductView scroll offset:", newValue)
        }
        .mask {
            LinearGradient(
                colors: [.clear, .black, .black, .black, .black, .black, .black, .black, .black, .clear],
                startPoint: UnitPoint(x: 0.5, y: 0),
                endPoint: UnitPoint(x: 0.5, y: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateProductScrollViewportHeight() {
        productScrollViewportHeight = max(UIScreen.main.bounds.height, 1)
    }

    @MainActor
    private func showDrop(title: String, subtitle: String? = nil) {
        let drop = Drop(title: title, subtitle: subtitle ?? "")
        Drops.show(drop)
    }

    private var lifetimePriceLabel: String {
        if isPurchased { return "Purchased" }
        if let product = lifetimeProduct { return product.displayPrice }
        return "Loading..."
    }

    @MainActor
    private func configureStoreIfNeeded() async {
        guard !hasLoadedStore else { return }
        hasLoadedStore = true
        await loadProducts()
        await refreshPurchasedState()
    }

    @MainActor
    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [AppConfig.lifetimeAccessProductId])
            lifetimeProduct = products.first
            purchaseErrorMessage = nil
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshPurchasedState() async {
        var hasAccess = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if transaction.productID == AppConfig.lifetimeAccessProductId {
                hasAccess = true
                break
            }
        }
        isPurchased = hasAccess
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case let .verified(transaction) = result else { continue }
            if transaction.productID == AppConfig.lifetimeAccessProductId {
                await MainActor.run {
                    isPurchased = true
                    onGetLifetimeAccess()
                }
            }
            await transaction.finish()
        }
    }

    @MainActor
    private func purchaseLifetimeAccess() async {
        if isPurchased {
            showDrop(title: "Already Unlocked", subtitle: "Lifetime access is active.")
            onGetLifetimeAccess()
            return
        }
        guard let product = lifetimeProduct else {
            showDrop(title: "Product Unavailable", subtitle: "Try again in a moment.")
            return
        }
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                switch verification {
                case let .verified(transaction):
                    await transaction.finish()
                    await refreshPurchasedState()
                    showDrop(title: "Purchase Successful", subtitle: "Lifetime access unlocked.")
                    onGetLifetimeAccess()
                case .unverified:
                    purchaseErrorMessage = "Purchase could not be verified."
                }
            case .pending:
                showDrop(title: "Purchase Pending", subtitle: "Awaiting approval.")
                break
            case .userCancelled:
                showDrop(title: "Purchase Cancelled", subtitle: "You can try again anytime.")
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshPurchasedState()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    private struct ProductChecklistItem: Identifiable {
        let id = UUID()
        let title: String
        let text: String
        let description: String
        let symbolName: String
        let color: Color
    }

    private struct ProductChecklistRow: View {
        let item: ProductChecklistItem
        let index: Int
        let viewportHeight: CGFloat

        @State private var rowMidY: CGFloat = 0

        var body: some View {
            let isLeading = index.isMultiple(of: 2)
            let progress = normalizedDistanceToCenter
            let verticalCompaction = dynamicChecklistVerticalCompaction(progress: progress)
            let rotation = dynamicChecklistRotation(progress: progress, isLeading: isLeading)
            let scale = dynamicChecklistScale(progress: progress)
            let horizontalOffset = dynamicChecklistHorizontalOffset(progress: progress, isLeading: isLeading)

            HStack {
                Spacer()

                ProductCheckListView(
                    title: item.title,
                    text: item.text,
                    description: item.description,
                    symbolName: item.symbolName,
                    accentColor: item.color
                )
                .frame(maxWidth: 230, alignment: .leading)
                .rotationEffect(rotation)
                .scaleEffect(scale)
                .padding(.vertical, verticalCompaction)
                .offset(x: horizontalOffset)

                Spacer()
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            rowMidY = proxy.frame(in: .named("ProductScroll")).midY
                        }
                        .onChange(of: proxy.frame(in: .named("ProductScroll")).midY) { _, newValue in
                            rowMidY = newValue
                        }
                }
            )
        }

        private var normalizedDistanceToCenter: CGFloat {
            let safeHeight = max(viewportHeight, 1)
            let centerY = safeHeight / 2
            let distance = abs(rowMidY - centerY)
            return min(distance / centerY, 1)
        }

        private func dynamicChecklistVerticalCompaction(progress: CGFloat) -> CGFloat {
            let fullPadding: CGFloat = 0
            let tightPadding: CGFloat = -48
            return fullPadding + (tightPadding - fullPadding) * progress
        }

        private func dynamicChecklistRotation(progress: CGFloat, isLeading: Bool) -> Angle {
            let maxRotation: CGFloat = 14
            let direction: CGFloat = isLeading ? -1 : 1
            let easedProgress = progress * progress * (3 - 2 * progress)
            return .degrees(Double(maxRotation * easedProgress * direction))
        }

        private func dynamicChecklistScale(progress: CGFloat) -> CGFloat {
            let minScale: CGFloat = 0.92
            let easedProgress = progress * progress * (3 - 2 * progress)
            return 1 - (1 - minScale) * easedProgress
        }

        private func dynamicChecklistHorizontalOffset(progress: CGFloat, isLeading: Bool) -> CGFloat {
            let baseOffset: CGFloat = 20
            let maxExtraOffset: CGFloat = 30
            let direction: CGFloat = isLeading ? 1 : -1
            let easedProgress = progress * progress * (3 - 2 * progress)
            return direction * (baseOffset + maxExtraOffset * easedProgress)
        }
    }

    private struct ProductCheckListView: View {
        let title: String
        let text: String
        let description: String
        let symbolName: String
        let accentColor: Color

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(alignment: .center) {
                HStack {
                    Image(systemName: symbolName)
                        .foregroundStyle(accentColor)

                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                }

                if text != "" {
                    HStack {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .opacity(0.7)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Color.clear.frame(height: 1)

                HStack {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                }
            }
            .multilineTextAlignment(.center)
            .padding()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentColor.opacity(0.3))
                        .mask {
                            LinearGradient(
                                colors: [.black, .black.opacity(0.3)],
                                startPoint: UnitPoint(x: 0.5, y: 0),
                                endPoint: UnitPoint(x: 0.5, y: 1)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
//                        .fill(.ultraThinMaterial)
//                        .fill(.ultraThickMaterial)
                }
            }
        }
    }

    @ViewBuilder func logoView() -> some View {
        VStack {
            HStack {
                Image("ImageLogo")
                Image("TextLogo")
            }

            Spacer()
        }
        .padding(.top, 48)
    }

    @ViewBuilder private func welcomePage() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    attributedLine(
                        "Read less linearly.",
                        boldParts: ["Re", "le", "line"]
                    )
                )
                Text(
                    attributedLine(
                        "Think more deliberately.",
                        boldParts: ["Th", "mo", "delibe"]
                    )
                )
            }
            .fontDesign(.rounded)

            HStack(spacing: 4) {
                Text("via")
                    .opacity(0.6)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)

                Text("Cognitive Index™")
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .fontDesign(.rounded)
            .font(.system(size: 15))

            Color.clear.frame(height: 1)
                .padding(.top, -1)
        }
    }

    @ViewBuilder private func longTextPage(longTextWidth: CGFloat = 320) -> some View {
        InfiniteAutoScrollText(sentences: longTextSentences)
            .font(.footnote)
            .fontWeight(.light)
            .foregroundStyle(.primary.opacity(0.75))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask {
                LinearGradient(
                    colors: [.clear, .black, .black, .black, .clear],
                    startPoint: UnitPoint(x: 0.5, y: 0),
                    endPoint: UnitPoint(x: 0.5, y: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .top) {
                HStack {
                    Text("Article")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassedEffect(in: RoundedRectangle(cornerRadius: 6), interactive: true)

                    Spacer()
                }
            }
            .padding()
            .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            .frame(width: longTextWidth, height: 240)
            .background {
                ZStack {
                    Color.clear
                        .frame(width: longTextWidth - 40, height: 240 - 40)
                        .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                        .offset(y: -42)
                        .opacity(0.6)
                        .blur(radius: 1)

                    Color.clear
                        .frame(width: longTextWidth - 20, height: 240 - 20)
                        .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                        .offset(y: -22)
                        .opacity(0.8)
                }
            }
    }

    private func attributedLine(_ text: String, boldParts: [String]) -> AttributedString {
        let size: CGFloat = 28

        var attributed = AttributedString(text)
        attributed.font = .system(size: size, weight: .light)
        attributed.foregroundColor = Color.primary.opacity(0.7)

        for part in boldParts {
            if let range = attributed.range(of: part) {
                attributed[range].font = .system(size: size, weight: .bold)
                attributed[range].foregroundColor = Color.primary
            }
        }
        return attributed
    }

    private func animateOnboardingTextChange(to index: Int) {
        guard onboardingCopies.indices.contains(index) else { return }
        textAnimationToken &+= 1
    }

    private var pageTransition: AnyTransition {
        let insertionEdge: Edge = isForwardTransition ? .trailing : .leading
        let removalEdge: Edge = isForwardTransition ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func goToPage(_ index: Int) {
        guard onboardingCopies.indices.contains(index) else { return }
        guard index != selectedPage else { return }
        isForwardTransition = index > selectedPage
        withAnimation(.easeInOut(duration: 0.35)) {
            selectedPage = index
        }
    }

    private func onboardingCopy(for index: Int) -> OnboardingCopy {
        if onboardingCopies.indices.contains(index) {
            return onboardingCopies[index]
        }
        return onboardingCopies[0]
    }
}

private struct ScrambleText: View {
    let text: String
    var boldParts: [String] = []
    let trigger: Int
    var duration: Double = 0.7
    var fps: Double = 30
    var delay: Double = 0
    var charset: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*")
    var baseWeight: Font.Weight = .light
    var boldWeight: Font.Weight = .bold
    var useBionic: Bool = true
    var fontSize: CGFloat? = nil

    @State private var displayText = ""
    @State private var task: Task<Void, Never>?

    @ViewBuilder var body: some View {
        Group {
            if useBionic {
                Text(bionicAttributed(displayText))
                    .fontDesign(.rounded)
            } else {
                Text(displayText)
            }
        }
        .onAppear {
            displayText = text
        }
        .onChange(of: trigger) { _, _ in
            startScramble()
        }
        .onChange(of: text) { _, newValue in
            if displayText.isEmpty {
                displayText = newValue
            }
        }
    }

    private func startScramble() {
        task?.cancel()
        task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
            }

            let steps = max(1, Int(duration * fps))
            let stepNanos = UInt64(1000000000 / max(fps, 1))
            for step in 0 ... steps {
                if Task.isCancelled { return }
                let progress = Double(step) / Double(steps)
                displayText = scramble(text, progress: progress)
                try? await Task.sleep(nanoseconds: stepNanos)
            }
            displayText = text
        }
    }

    private func scramble(_ text: String, progress: Double) -> String {
        let characters = Array(text)
        if characters.isEmpty { return "" }

        let revealCount = Int((Double(characters.count) * progress).rounded(.down))
        var result: [Character] = []
        result.reserveCapacity(characters.count)

        for index in characters.indices {
            let character = characters[index]
            if character.isWhitespace {
                result.append(character)
            } else if index < revealCount {
                result.append(character)
            } else {
                result.append(charset.randomElement() ?? character)
            }
        }
        return String(result)
    }

    private func bionicAttributed(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let size = fontSize {
            attributed.font = .system(size: size, weight: baseWeight, design: .rounded)
        } else {
            attributed.font = nil
        }
        attributed.foregroundColor = .primary.opacity(0.75)

        let words = extractWordRanges(from: text)
        for (index, wordRange) in words.enumerated() where index < boldParts.count {
            let part = boldParts[index]
            if part.isEmpty { continue }
            let prefixEnd = text.index(wordRange.lowerBound, offsetBy: min(part.count, text.distance(from: wordRange.lowerBound, to: wordRange.upperBound)))
            let prefixRange = wordRange.lowerBound ..< prefixEnd
            guard
                let lower = AttributedString.Index(prefixRange.lowerBound, within: attributed),
                let upper = AttributedString.Index(prefixRange.upperBound, within: attributed)
            else { continue }
            let attrRange = lower ..< upper
            if let size = fontSize {
                attributed[attrRange].font = .system(size: size, weight: boldWeight, design: .rounded)
            } else {
                attributed[attrRange].font = nil
            }
            attributed[attrRange].foregroundColor = .primary
        }
        return attributed
    }

    private func extractWordRanges(from text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var currentStart: String.Index?
        for index in text.indices {
            let character = text[index]
            if character.isWhitespace {
                if let start = currentStart {
                    ranges.append(start ..< index)
                    currentStart = nil
                }
            } else if currentStart == nil {
                currentStart = index
            }
        }
        if let start = currentStart {
            ranges.append(start ..< text.endIndex)
        }
        return ranges
    }
}

private struct InfiniteAutoScrollText: View {
    let sentences: [String]
    var velocity: CGFloat = 0.2

    @State private var scrollPosition = ScrollPosition()
    @State private var timer = Timer
        .publish(every: 0.02, on: .main, in: .common)
        .autoconnect()
    @State private var y: CGFloat = 0
    @State private var contentSetHeight: CGFloat = 0

    private let itemSpacing: CGFloat = 16
    private let verticalPadding: CGFloat = 20

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: verticalPadding)

                contentSet
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { updateContentHeight(proxy.size.height) }
                                .onChange(of: proxy.size.height) { _, newValue in
                                    updateContentHeight(newValue)
                                }
                        }
                    )

                contentSet
                contentSet

                Color.clear.frame(height: verticalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollClipDisabled(true)
        .allowsHitTesting(false)
        .scrollPosition($scrollPosition)
        .onReceive(timer) { _ in
            guard contentSetHeight > 0 else { return }
            if y >= maxOffset || y <= minOffset {
                y = baseOffset
            } else {
                y += velocity
            }
        }
        .onChange(of: y) { _, newValue in
            scrollPosition.scrollTo(y: newValue)
        }
        .onScrollGeometryChange(for: Double.self) { scrollGeometry in
            scrollGeometry.contentOffset.y
        } action: { _, newValue in
            y = CGFloat(newValue)
        }
    }

    private var contentSet: some View {
        VStack(alignment: .leading, spacing: itemSpacing) {
            ForEach(sentences.indices, id: \.self) { index in
                Text(sentences[index])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func updateContentHeight(_ value: CGFloat) {
        guard value > 0 else { return }
        if contentSetHeight != value {
            contentSetHeight = value
            if y == 0 || y > maxOffset {
                y = baseOffset
            }
        }
    }

    private var baseOffset: CGFloat {
        verticalPadding + contentSetHeight
    }

    private var minOffset: CGFloat {
        verticalPadding
    }

    private var maxOffset: CGFloat {
        verticalPadding + (contentSetHeight * 2)
    }
}

private struct BorderedTintButtonStyle: ButtonStyle {
    var tint: Color
    var stroke: Color
    var foreground: Color
    var cornerRadius: CGFloat = 99
    var pressedScale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView(defaultPage: 3)
        .environment(\.locale, .init(identifier: "en"))
        .environment(\.layoutDirection, .leftToRight)
}
