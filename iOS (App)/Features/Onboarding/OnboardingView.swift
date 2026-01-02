//
//  OnboardingView.swift
//  SwiftUIPreview
//
//  Created by 黃佁媛 on 12/31/25.
//

import Combine
import MarkdownUI
import SwiftUI

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
    private struct OnboardingCopy: Equatable {
        let line1: String
        let line2: String
        let line3: String
    }

    private let onboardingCopies: [OnboardingCopy] = [
        OnboardingCopy(
            line1: "你通常不是沒時間讀",
            line2: "而是不知道哪裡值得花時間",
            line3: "找到屬於你的認知節奏"
        ),
        OnboardingCopy(
            line1: "從這裡開始",
            line2: "透過 AI 技術的幫助",
            line3: "結構化閱讀技術"
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

    private var currentCopy: OnboardingCopy {
        onboardingCopy(for: selectedPage)
    }

    var body: some View {
        ZStack {
            mainView()

            logoView()

            actionButton()
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
                goToPage(selectedPage + 1)
            } label: {
                HStack {
                    Text(selectedPage == onboardingCopies.count - 1 ? "Continue" : "Get started")
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

            ZStack {
                if selectedPage == 0 {
                    longTextPage()
                        .transition(pageTransition)
                }

                if selectedPage == 1 {
                    keyPointView()
                        .transition(pageTransition)
                        .offset(y: -24)
                }
            }
            .padding(.bottom)
            .frame(height: 320)
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

            OnboardingText(
                currentCopy.line1,
                currentCopy.line2,
                currentCopy.line3,
                animationToken: textAnimationToken
            )

            Spacer()
        }
    }

    @ViewBuilder func OnboardingText(
        _ line1: String,
        _ line2: String,
        _ line3: String,
        animationToken: Int
    ) -> some View {
        VStack(alignment: .center, spacing: 12) {
            VStack(spacing: 6) {
                ScrambleText(text: line1, trigger: animationToken, delay: 0)

                ScrambleText(text: line2, trigger: animationToken, delay: 0.06)
            }
            .foregroundStyle(.primary)
            .font(.title3)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)

            Divider().frame(width: 32)

            VStack(spacing: 6) {
                ScrambleText(text: line3, trigger: animationToken, delay: 0.12)
                    .foregroundStyle(.secondary)
                    .font(.footnote)

                Text("Cognitive Index™")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .opacity(0.6)
            }

            Color.clear.frame(height: 1)
                .padding(.top, -1)
        }
        .padding(.horizontal)
        .frame(maxWidth: 320)
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
                    # 閱讀挑戰：結構而非內容

                    ### 問題：

                    *   **不具意義的順序**：文章依賴的順序，並非讓讀者理解的順序。
                    *   **不連貫的思考**：想法不 neatly 排列，重要背景資訊出現得太晚，關鍵假設被埋下。
                    *   **突如其來的過渡**：讀者必須不斷調整理解，而非直接思考。

                    ### 結果：

                    *   **記憶重複**：讀者記得內容，但未理解核心決策。
                    *   **認知負擔**：維持順序、追蹤位置、猜測相關性，而非真正思考。

                    ### 結論：

                    *   閱讀問題不是內容問題，而是結構問題。
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

    @ViewBuilder func actionButton2() -> some View {
        VStack(alignment: .leading) {
            Color.clear.frame(height: 1)

            VStack(alignment: .leading) {
                HStack {
                    Spacer()

                    Button {
                    } label: {
                        Text("Continue")
                    }

                    Spacer()
                }
            }
            .padding()

            Color.clear.frame(height: 1)
        }
        .glassedEffect(in: RoundedRectangle(cornerRadius: 16), interactive: true)
        .padding(.horizontal, -8)
        .offset(y: 8)
    }

    @ViewBuilder private func welcomePage() -> some View {
        VStack(alignment: .center, spacing: 12) {
            VStack(alignment: .center, spacing: 0) {
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
    let trigger: Int
    var duration: Double = 0.7
    var fps: Double = 30
    var delay: Double = 0
    var charset: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*")

    @State private var displayText = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        Text(displayText)
            .onAppear {
                displayText = text
            }
            .onChange(of: trigger) { _ in
                startScramble()
            }
            .onChange(of: text) { newValue in
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
                                .onChange(of: proxy.size.height) { newValue in
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
        .onChange(of: y) { newValue in
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
    OnboardingView()
}
