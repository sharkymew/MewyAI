import SwiftUI
import Combine
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private enum ChatScrollMetrics {
    static let coordinateSpaceName = "ChatScrollCoordinateSpace"
    static let bottomThreshold: CGFloat = 12
    static let dragIntentMinimumDistance: CGFloat = 3
    static let scrollToBottomButtonBottomPadding: CGFloat = 92
    static let scrollToBottomButtonHitOutset: CGFloat = 8
    static let scrollToBottomButtonHitSize: CGFloat = 52
    static var scrollToBottomButtonHitAdjustedBottomPadding: CGFloat {
        max(scrollToBottomButtonBottomPadding - scrollToBottomButtonHitOutset, 0)
    }

    static func roundedDistance(_ distance: CGFloat) -> CGFloat {
        let scale = max(UIScreen.main.scale, 1)
        return (max(distance, 0) * scale).rounded() / scale
    }
}

private extension View {
    @ViewBuilder
    func observeChatScrollUserInteraction(
        onBegin: @escaping () -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .interacting, .decelerating:
                    onBegin()
                case .idle:
                    onEnd()
                case .tracking, .animating:
                    break
                }
            }
        } else {
            simultaneousGesture(
                DragGesture(minimumDistance: ChatScrollMetrics.dragIntentMinimumDistance)
                    .onChanged { _ in
                        onBegin()
                    }
                    .onEnded { _ in
                        onEnd()
                    }
            )
        }
    }
}

private struct ChatScrollBottomDistancePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct InputBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SidebarLayout {
    let sidebarWidth: CGFloat
    let mainContentWidth: CGFloat
    let usesPersistentSidebar: Bool

    func mainContentOffsetX(isOverlayVisible: Bool) -> CGFloat {
        usesPersistentSidebar || isOverlayVisible ? sidebarWidth : 0
    }
}

struct FixedTopGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.46)
            .background {
                if #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(.regular.tint(tint), in: Capsule())
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(tint))
                        .overlay(
                            Capsule()
                                .stroke(highlight, lineWidth: 1)
                                .blendMode(.screen)
                        )
                }
            }
            .scaleEffect(configuration.isPressed ? 1.05 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct FunctionOpacityMask: View {
    let topOpacity: Double
    let maxOpacity: Double
    let fadeInEnd: Double
    let holdEnd: Double
    let fadeOutEnd: Double
    var progressStartOffset: CGFloat = 0
    var progressLength: CGFloat?

    var body: some View {
        Canvas { context, size in
            let scale = max(UIScreen.main.scale, 1)
            let rowHeight = 1 / scale
            let rowCount = max(Int(ceil(size.height / rowHeight)), 1)

            for row in 0..<rowCount {
                let y = min(CGFloat(row) * rowHeight, size.height)
                let nextY = min(y + rowHeight, size.height)
                guard nextY > y else { continue }

                let midpoint = (y + nextY) * 0.5
                let length = max(progressLength ?? size.height, 1)
                let progress = Double((midpoint - progressStartOffset) / length)
                let opacity = opacity(at: progress)
                guard opacity > 0.001 else { continue }

                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: nextY - y)),
                    with: .color(.black.opacity(opacity))
                )
            }
        }
    }

    private func opacity(at rawProgress: Double) -> Double {
        let progress = min(max(rawProgress, 0), 1)

        if progress <= fadeInEnd {
            let phase = smootherStep(progress / fadeInEnd)
            return topOpacity + (maxOpacity - topOpacity) * phase
        }

        if progress <= holdEnd {
            return maxOpacity
        }

        if progress <= fadeOutEnd {
            let phase = smootherStep((progress - holdEnd) / (fadeOutEnd - holdEnd))
            return maxOpacity * (1 - phase)
        }

        return 0
    }

    private func smootherStep(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

private struct GlassFadeExclusion {
    let bounds: Anchor<CGRect>
    let inset: CGFloat
}

private struct GlassFadeExclusionPreferenceKey: PreferenceKey {
    static var defaultValue: [GlassFadeExclusion] = []

    static func reduce(value: inout [GlassFadeExclusion], nextValue: () -> [GlassFadeExclusion]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func glassFadeExclusion(inset: CGFloat) -> some View {
        anchorPreference(key: GlassFadeExclusionPreferenceKey.self, value: .bounds) { bounds in
            [GlassFadeExclusion(bounds: bounds, inset: inset)]
        }
    }

    @ViewBuilder
    func observeChatScrollBottomDistance(_ action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(
                for: CGFloat.self,
                of: { geometry in
                    ChatScrollMetrics.roundedDistance(geometry.contentSize.height - geometry.visibleRect.maxY)
                },
                action: { _, distanceFromBottom in
                    action(distanceFromBottom)
                }
            )
        } else {
            onPreferenceChange(ChatScrollBottomDistancePreferenceKey.self) { distanceFromBottom in
                action(distanceFromBottom)
            }
        }
    }
}

@MainActor
private final class ChatScrollController: ObservableObject {
    @Published private var shouldAutoScroll = true
    @Published private var isScrolledToBottom = true

    private var isUserDragging = false
    private var hasUserPausedAutoScroll = false
    private var hasLeftBottomAfterUserPause = false
    private var isAutoScrollScheduled = false
    private var isBottomDistanceUpdateScheduled = false
    private var pendingDistanceFromBottom: CGFloat?
    private var lastDistanceFromBottom: CGFloat = 0
    private var autoScrollTask: Task<Void, Never>?
    private var scrollAction: ((Bool) -> Void)?

    var shouldShowScrollToBottomButton: Bool {
        !isScrolledToBottom
    }

    deinit {
        autoScrollTask?.cancel()
    }

    func setScrollAction(_ action: @escaping (Bool) -> Void) {
        scrollAction = action
    }

    func clearScrollAction() {
        scrollAction = nil
    }

    func beginUserScrollInteraction() {
        isUserDragging = true
        pauseAutoScrollForUser()
    }

    func endUserScrollInteraction() {
        isUserDragging = false

        if resumeAutoScrollIfUserReturnedToBottom() {
            return
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resumeAutoScrollIfUserReturnedToBottom()
        }
    }

    func scheduleBottomDistanceUpdate(_ distanceFromBottom: CGFloat) {
        lastDistanceFromBottom = distanceFromBottom
        pendingDistanceFromBottom = distanceFromBottom

        guard !isBottomDistanceUpdateScheduled else { return }
        isBottomDistanceUpdateScheduled = true

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }

            let distanceFromBottom = pendingDistanceFromBottom ?? 0
            pendingDistanceFromBottom = nil
            isBottomDistanceUpdateScheduled = false
            updateBottomDistance(distanceFromBottom)
        }
    }

    private func updateBottomDistance(_ distanceFromBottom: CGFloat) {
        lastDistanceFromBottom = distanceFromBottom
        let isAtBottom = distanceFromBottom <= ChatScrollMetrics.bottomThreshold

        if isScrolledToBottom != isAtBottom {
            setIsScrolledToBottom(isAtBottom)
        }

        if isAtBottom {
            if hasUserPausedAutoScroll {
                if hasLeftBottomAfterUserPause, !isUserDragging {
                    resumeAutoScroll()
                }
            } else {
                setShouldAutoScroll(true)
            }
        } else if isUserDragging {
            pauseAutoScrollForUser()
        } else if hasUserPausedAutoScroll {
            hasLeftBottomAfterUserPause = true
        }
    }

    func returnToBottom() {
        resumeAutoScroll()
        requestImmediateAutoScroll(animated: false)
    }

    func requestImmediateAutoScroll(animated: Bool = false) {
        guard shouldAutoScroll else { return }
        cancelScheduledAutoScroll()
        scrollAction?(animated)
    }

    func scheduleStreamingAutoScroll() {
        guard shouldAutoScroll else { return }
        guard !hasUserPausedAutoScroll else { return }
        guard !isUserDragging else { return }
        guard !isAutoScrollScheduled else { return }
        isAutoScrollScheduled = true
        autoScrollTask?.cancel()

        autoScrollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(32))
            guard let self, !Task.isCancelled else { return }
            if shouldAutoScroll {
                scrollAction?(false)
            }
            isAutoScrollScheduled = false
            autoScrollTask = nil
        }
    }

    func cancelScheduledAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        isAutoScrollScheduled = false
    }

    private func setShouldAutoScroll(_ value: Bool) {
        guard shouldAutoScroll != value else { return }
        shouldAutoScroll = value
    }

    private func setIsScrolledToBottom(_ value: Bool) {
        guard isScrolledToBottom != value else { return }
        isScrolledToBottom = value
    }

    private func pauseAutoScrollForUser() {
        hasUserPausedAutoScroll = true
        hasLeftBottomAfterUserPause = hasLeftBottomAfterUserPause || !isScrolledToBottom
        setShouldAutoScroll(false)
        cancelScheduledAutoScroll()
    }

    private func resumeAutoScroll() {
        hasUserPausedAutoScroll = false
        hasLeftBottomAfterUserPause = false
        setShouldAutoScroll(true)
    }

    @discardableResult
    private func resumeAutoScrollIfUserReturnedToBottom() -> Bool {
        guard hasUserPausedAutoScroll, hasLeftBottomAfterUserPause else { return false }
        guard isScrolledToBottom || lastDistanceFromBottom <= ChatScrollMetrics.bottomThreshold else { return false }
        resumeAutoScroll()
        return true
    }
}

private struct ScrollToBottomButtonOverlay<Label: View>: View {
    @ObservedObject var scrollController: ChatScrollController
    let label: () -> Label

    var body: some View {
        ZStack {
            if scrollController.shouldShowScrollToBottomButton {
                Button {
                    scrollController.returnToBottom()
                } label: {
                    label()
                        .frame(
                            width: ChatScrollMetrics.scrollToBottomButtonHitSize,
                            height: ChatScrollMetrics.scrollToBottomButtonHitSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, ChatScrollMetrics.scrollToBottomButtonHitAdjustedBottomPadding)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: 0.18),
            value: scrollController.shouldShowScrollToBottomButton
        )
    }
}

@MainActor
private final class StreamingTokenBuffer {
    private var pendingReasoningChunks: [String] = []
    private var pendingContentChunks: [String] = []

    var hasPendingReasoningText: Bool {
        !pendingReasoningChunks.isEmpty
    }

    var hasPendingContentText: Bool {
        !pendingContentChunks.isEmpty
    }

    var reasoningChunksSnapshot: [String] {
        pendingReasoningChunks
    }

    func appendReasoning(_ text: String) {
        pendingReasoningChunks.append(text)
    }

    func appendContent(_ text: String) {
        pendingContentChunks.append(text)
    }

    func consumePendingReasoningChunks() -> [String] {
        let chunks = pendingReasoningChunks
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        return chunks
    }

    func consumePendingContentText() -> String {
        let text = pendingContentChunks.joined()
        pendingContentChunks.removeAll(keepingCapacity: true)
        return text
    }

    func clearPendingTokens() {
        pendingReasoningChunks.removeAll(keepingCapacity: true)
        pendingContentChunks.removeAll(keepingCapacity: true)
    }

    func reset() {
        clearPendingTokens()
    }
}

@MainActor
private final class AssistantLiveDisplay {
    let reasoningChannel = StreamingTextUpdateChannel()
    let contentChannel = StreamingTextUpdateChannel()
}

private final class StreamingOutputHaptics: ObservableObject {
    private let refreshGenerator = UIImpactFeedbackGenerator(style: .light)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var lastImpactAt: Date?
    private static let minimumImpactInterval: TimeInterval = 0.055

    func prepareForStreaming() {
        lastImpactAt = nil
        refreshGenerator.prepare()
        completionGenerator.prepare()
    }

    func impactForOutputRefresh() {
        let now = Date()
        if let lastImpactAt,
           now.timeIntervalSince(lastImpactAt) < Self.minimumImpactInterval {
            return
        }

        refreshGenerator.impactOccurred(intensity: 0.35)
        refreshGenerator.prepare()
        lastImpactAt = now
    }

    func impactForOutputCompletion() {
        completionGenerator.impactOccurred(intensity: 0.85)
        completionGenerator.prepare()
        lastImpactAt = nil
    }

    func reset() {
        lastImpactAt = nil
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @StateObject private var speechInputController = SpeechInputController()
    @StateObject private var streamingOutputHaptics = StreamingOutputHaptics()
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var conversations = ConversationStore.loadConversations()
    @State private var selectedConversationID: UUID? = ConversationStore.loadSelectedConversationID()
    @State private var isGenerating = false
    @State private var showConfiguration = false
    @State private var showConversationSidebar = false
    @State private var chatScrollController = ChatScrollController()
    @State private var streamingTokenBuffer = StreamingTokenBuffer()
    @State private var activeAssistantHasReasoning = false
    @State private var activeAssistantHasContent = false
    @State private var activeAssistantReasoningIsExpanded = false
    @State private var activeAssistantDidCollapseReasoningAfterThinking = false
    @State private var liveAssistantDisplays: [UUID: AssistantLiveDisplay] = [:]
    @State private var isFlushScheduled = false
    @State private var flushTask: Task<Void, Never>?
    @State private var activeAssistantMessageID: UUID?
    @State private var markdownRenderCache: [UUID: MarkdownRenderCacheEntry] = [:]
    @State private var markdownRenderTasks: [UUID: Task<Void, Never>] = [:]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var pendingImageAttachments: [ChatImageAttachment] = []
    @State private var pendingFileAttachments: [ChatFileAttachment] = []
    @State private var imageSelectionError: String?
    @State private var isAttachmentDropTargeted = false
    @State private var activeMessageActionID: UUID?
    @State private var didTapMessageBubble = false
    @State private var editingMessageID: UUID?
    @State private var isInputFocused = false
    @State private var inputFocusRequestID = 0
    @State private var speechInputBaseText = ""
    @State private var speechInputLastTranscript = ""
    @State private var speechInputLastMergedText = ""
    @State private var inputBarMeasuredHeight: CGFloat = 0
    @State private var hasLoadedInitialConversation = false
    @State private var showsMainSidebarToggleFadeExclusion = true
    @State private var showsSidebarToggleFadeExclusion = false
    @State private var sidebarVisibilityTransitionTask: Task<Void, Never>?

    let aiService = AIService()
    private let maxImageAttachmentCount = 4
    private let maxFileAttachmentCount = 5
    private let maxImageInputByteCount = 12 * 1024 * 1024
    private let maxImagePixelCount: Int64 = 24_000_000
    private let inputBarBottomPadding: CGFloat = 8
    private let inputBarTopPadding: CGFloat = 8
    private let inputBarHorizontalPadding: CGFloat = 12
    private let inputBarCornerRadius: CGFloat = 34
    private let bottomScrollContentGap: CGFloat = 10
    private let inputBottomFadeHeight: CGFloat = 178
    private let inputBottomFadeOverlap: CGFloat = 118
    private let topGlassFadeExclusionInset: CGFloat = 8
    private let scrollToBottomFadeExclusionSize: CGFloat = 34
    private let topControlSize: CGFloat = 44
    private let topControlsTopPadding: CGFloat = 8
    private let topControlsHorizontalPadding: CGFloat = 16
    private let topConversationTitleButtonWidth: CGFloat = 148
    private let topFadeBottomPadding: CGFloat = 155
    private let topScrollContentGap: CGFloat = 70
    private let persistentSidebarWidthRatio: CGFloat = 0.28
    private let persistentSidebarMinimumWidth: CGFloat = 280
    private let persistentSidebarMaximumWidth: CGFloat = 360
    private let sidebarTransitionDuration: Double = 0.22
    private let sidebarTransitionDelayNanoseconds: UInt64 = 220_000_000

    private var inputGlassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.14)
    }

    private var inputGlassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : Color.white.opacity(0.74)
    }

    private var controlGlassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.58)
    }

    private var sendControlBackground: Color {
        !canSendMessage && !isGenerating
            ? inputGlassTint
            : Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.11)
    }

    private var cancelControlBackground: Color {
        Color.red.opacity(colorScheme == .dark ? 0.18 : 0.09)
    }

    private var speechControlBackground: Color {
        speechInputController.isRecording
            ? Color.red.opacity(colorScheme == .dark ? 0.22 : 0.12)
            : inputGlassTint
    }

    private var inputBottomFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.40) : Color.white.opacity(0.62)
    }

    private var topFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.48)
    }

    private var topFadeHeight: CGFloat {
        topControlsTopPadding + topControlSize + topFadeBottomPadding
    }

    private var topScrollContentPadding: CGFloat {
        topControlsTopPadding + topControlSize + topScrollContentGap
    }

    private var bottomScrollContentPadding: CGFloat {
        let inputBarHeight = inputBarMeasuredHeight > 0 ? inputBarMeasuredHeight : inputBottomFadeOverlap
        return inputBarHeight + bottomScrollContentGap
    }

    @ViewBuilder
    private var fadeBase: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(Color.black)
        } else {
            Rectangle()
                .fill(.thickMaterial)
        }
    }

    @ViewBuilder
    private func inputGlassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content()
                .background {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(inputGlassTint), in: shape)
                }
        } else {
            content()
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(inputGlassTint))
                .overlay(
                    shape
                        .stroke(inputGlassHighlight, lineWidth: 1)
                        .blendMode(.screen)
                )
        }
    }

    @ViewBuilder
    private func controlGlassBackground(_ tint: Color, isInteractive: Bool = true) -> some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(tint))
            .overlay(
                Circle()
                    .stroke(controlGlassHighlight, lineWidth: 1)
            )
    }

    private func controlGlassIcon(
        systemName: String,
        size: CGFloat,
        weight: Font.Weight,
        frame: CGFloat,
        tint: Color,
        foreground: Color = .primary
    ) -> some View {
        ZStack {
            controlGlassBackground(tint)

            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(foreground)
        }
        .frame(width: frame, height: frame)
    }

    private func scrollToBottomGlassIcon() -> some View {
        let shape = Circle()

        return ZStack {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(inputGlassTint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(inputGlassTint))
                    .overlay(
                        shape
                            .stroke(inputGlassHighlight, lineWidth: 1)
                            .blendMode(.screen)
                    )
            }

            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 36, height: 36)
    }

    private var inputBottomFade: some View {
        fadeBase
            .overlay(inputBottomFadeTint)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.08), location: 0.00),
                        .init(color: .black.opacity(0.18), location: 0.10),
                        .init(color: .black.opacity(0.36), location: 0.24),
                        .init(color: .black.opacity(0.66), location: 0.48),
                        .init(color: .black.opacity(0.90), location: 0.72),
                        .init(color: .black.opacity(1.00), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }

    private var inputBottomFadeBackdrop: some View {
        GeometryReader { geometry in
            let fadeTop = geometry.size.height - inputBottomFadeOverlap - inputBarBottomPadding
            let scrollButtonCenterY = geometry.size.height
                - ChatScrollMetrics.scrollToBottomButtonHitAdjustedBottomPadding
                - ChatScrollMetrics.scrollToBottomButtonHitSize / 2

            ZStack(alignment: .topLeading) {
                inputBottomFade
                    .frame(width: geometry.size.width, height: inputBottomFadeHeight)
                    .offset(y: fadeTop)

                if chatScrollController.shouldShowScrollToBottomButton {
                    Circle()
                        .frame(
                            width: scrollToBottomFadeExclusionSize,
                            height: scrollToBottomFadeExclusionSize
                        )
                        .position(x: geometry.size.width / 2, y: scrollButtonCenterY)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }

    private var topFade: some View {
        fadeBase
            .overlay(topFadeTint)
            .mask(
                FunctionOpacityMask(
                    topOpacity: 0.28,
                    maxOpacity: 0.90,
                    fadeInEnd: 0.22,
                    holdEnd: 0.48,
                    fadeOutEnd: 0.88
                )
            )
            .allowsHitTesting(false)
    }

    private func topFadeBackdrop(
        topSafeAreaInset: CGFloat,
        exclusions: [GlassFadeExclusion],
        proxy: GeometryProxy,
        showsSidebarToggleExclusion: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            topFade
                .frame(width: proxy.size.width, height: topSafeAreaInset + topFadeHeight)
                .offset(y: -topSafeAreaInset)
                .ignoresSafeArea(edges: .top)

            if showsSidebarToggleExclusion {
                Capsule()
                    .frame(
                        width: max(topControlSize - topGlassFadeExclusionInset * 2, 0),
                        height: max(topControlSize - topGlassFadeExclusionInset * 2, 0)
                    )
                    .position(
                        x: topControlsHorizontalPadding + topControlSize / 2,
                        y: topControlsTopPadding + topControlSize / 2
                    )
                    .blendMode(.destinationOut)
            }

            ForEach(Array(exclusions.enumerated()), id: \.offset) { _, exclusion in
                let rect = proxy[exclusion.bounds]

                Capsule()
                    .frame(
                        width: max(rect.width - exclusion.inset * 2, 0),
                        height: max(rect.height - exclusion.inset * 2, 0)
                    )
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func topChrome(topSafeAreaInset: CGFloat, showsSidebarToggleExclusion: Bool) -> some View {
        topFloatingControls
            .frame(maxWidth: .infinity, maxHeight: topFadeHeight, alignment: .top)
            .backgroundPreferenceValue(GlassFadeExclusionPreferenceKey.self) { exclusions in
                GeometryReader { proxy in
                    topFadeBackdrop(
                        topSafeAreaInset: topSafeAreaInset,
                        exclusions: exclusions,
                        proxy: proxy,
                        showsSidebarToggleExclusion: showsSidebarToggleExclusion
                    )
                }
            }
    }

    @ViewBuilder
    private func topGlassControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .buttonStyle(
                FixedTopGlassButtonStyle(
                    tint: inputGlassTint,
                    highlight: inputGlassHighlight
                )
            )
            .glassFadeExclusion(inset: topGlassFadeExclusionInset)
    }

    private func topIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: topControlSize, height: topControlSize)
            .contentShape(Circle())
    }

    private var canSendMessage: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingImageAttachments.isEmpty
            || !pendingFileAttachments.isEmpty
    }

    private var isEditingMessage: Bool {
        editingMessageID != nil
    }

    private func toggleSpeechInput() {
        if speechInputController.isRecording {
            speechInputController.stopRecording()
            return
        }

        speechInputBaseText = inputText
        speechInputLastTranscript = ""
        speechInputLastMergedText = inputText

        Task {
            await speechInputController.startRecording()
        }
    }

    private func stopSpeechInputIfNeeded() {
        if speechInputController.isRecording {
            speechInputController.stopRecording()
        }
    }

    private func resetSpeechInputMergeState() {
        speechInputBaseText = inputText
        speechInputLastTranscript = ""
        speechInputLastMergedText = inputText
    }

    private func applySpeechTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            speechInputLastTranscript = ""
            speechInputLastMergedText = inputText
            return
        }

        if speechInputLastTranscript.isEmpty {
            if inputText != speechInputBaseText {
                speechInputBaseText = inputText
            }
        } else if inputText != speechInputLastMergedText {
            speechInputBaseText = inputText
        }

        let mergedText = mergedSpeechInputText(
            baseText: speechInputBaseText,
            speechText: trimmedTranscript
        )
        inputText = mergedText
        speechInputLastTranscript = trimmedTranscript
        speechInputLastMergedText = mergedText
    }

    private func mergedSpeechInputText(baseText: String, speechText: String) -> String {
        let trimmedSpeechText = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSpeechText.isEmpty else { return baseText }
        guard !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedSpeechText
        }

        let needsSeparator = baseText.unicodeScalars.last.map {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        } ?? false
        return baseText + (needsSeparator ? " " : "") + trimmedSpeechText
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = sidebarLayout(for: geometry.size)
            let showsOverlaySidebar = showConversationSidebar && !layout.usesPersistentSidebar
            let showsSidebar = showConversationSidebar || layout.usesPersistentSidebar

            ZStack(alignment: .leading) {
                mainContent(topSafeAreaInset: geometry.safeAreaInsets.top)
                    .frame(width: layout.mainContentWidth)
                    .disabled(showsOverlaySidebar)
                    .offset(x: layout.mainContentOffsetX(isOverlayVisible: showsOverlaySidebar))
                    .animation(.easeOut(duration: sidebarTransitionDuration), value: showConversationSidebar)

                if showsOverlaySidebar {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture {
                            setConversationSidebarVisibility(false)
                        }
                }

                if !showConversationSidebar && !layout.usesPersistentSidebar {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 28)
                        .ignoresSafeArea()
                        .gesture(openSidebarGesture)
                }

                ConversationSidebarView(
                    conversations: conversations,
                    selectedConversationID: selectedConversationID,
                    topSafeAreaInset: geometry.safeAreaInsets.top,
                    showsSidebarToggleFadeExclusion: showsSidebarToggleFadeExclusion && !layout.usesPersistentSidebar,
                    showsCloseButton: !layout.usesPersistentSidebar,
                    onSelect: { id in
                        selectConversation(id, closesSidebar: !layout.usesPersistentSidebar)
                    },
                    onClose: {
                        hideKeyboard()
                        setConversationSidebarVisibility(false)
                    },
                    onOpenConfiguration: {
                        openConfigurationFromSidebar(closesSidebar: !layout.usesPersistentSidebar)
                    },
                    onDelete: deleteConversation
                )
                .frame(width: layout.sidebarWidth)
                .ignoresSafeArea(edges: [.top, .bottom])
                .offset(x: showsSidebar ? 0 : -layout.sidebarWidth)
                .animation(.easeOut(duration: sidebarTransitionDuration), value: showConversationSidebar)

                if !showsSidebar {
                    sidebarToggleControl
                }
            }
            .simultaneousGesture(closeSidebarGesture)
        }
        .onAppear {
            guard !hasLoadedInitialConversation else { return }
            hasLoadedInitialConversation = true
            loadSelectedConversation()
        }
        .sheet(isPresented: $showConfiguration) {
            AIConfigurationView()
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: maxImageAttachmentCount,
            matching: .images
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: ChatFileAttachmentReader.supportedDocumentTypes,
            allowsMultipleSelection: true,
            onCompletion: loadSelectedFiles
        )
        .onChange(of: showConfiguration) { _, isPresented in
            if !isPresented {
                reloadConfigurations()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            loadSelectedImages(from: newItems)
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            resetMarkdownCache(for: messages)
        }
        .onChange(of: colorScheme) { _, _ in
            resetMarkdownCache(for: messages)
        }
        .onChange(of: speechInputController.transcript) { _, transcript in
            applySpeechTranscript(transcript)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            speechInputController.stopRecording()
            persistApplicationStateForLifecycle()
        }
    }

    private func sidebarLayout(for size: CGSize) -> SidebarLayout {
        let usesPersistentSidebar = UIDevice.current.userInterfaceIdiom == .pad
            && size.width > size.height
        let sidebarWidth: CGFloat

        if usesPersistentSidebar {
            sidebarWidth = min(
                max(size.width * persistentSidebarWidthRatio, persistentSidebarMinimumWidth),
                persistentSidebarMaximumWidth
            )
        } else {
            sidebarWidth = min(size.width * 0.72, 320)
        }

        return SidebarLayout(
            sidebarWidth: sidebarWidth,
            mainContentWidth: usesPersistentSidebar ? max(size.width - sidebarWidth, 0) : size.width,
            usesPersistentSidebar: usesPersistentSidebar
        )
    }

    private func setConversationSidebarVisibility(_ isVisible: Bool) {
        guard showConversationSidebar != isVisible else { return }

        sidebarVisibilityTransitionTask?.cancel()

        if isVisible {
            showsMainSidebarToggleFadeExclusion = false
            showsSidebarToggleFadeExclusion = false
            showConversationSidebar = true

            sidebarVisibilityTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: sidebarTransitionDelayNanoseconds)
                guard !Task.isCancelled, showConversationSidebar else { return }
                showsSidebarToggleFadeExclusion = true
                sidebarVisibilityTransitionTask = nil
            }
        } else {
            showsSidebarToggleFadeExclusion = false
            showConversationSidebar = false

            sidebarVisibilityTransitionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: sidebarTransitionDelayNanoseconds)
                guard !Task.isCancelled, !showConversationSidebar else { return }
                showsMainSidebarToggleFadeExclusion = true
                sidebarVisibilityTransitionTask = nil
            }
        }
    }

    @ViewBuilder
    private func mainContent(topSafeAreaInset: CGFloat) -> some View {
        legacyMainContent(topSafeAreaInset: topSafeAreaInset)
    }

    private func legacyMainContent(topSafeAreaInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            chatScrollView(topPadding: topScrollContentPadding)
                .ignoresSafeArea(edges: [.top, .bottom])

            topChrome(
                topSafeAreaInset: topSafeAreaInset,
                showsSidebarToggleExclusion: showsMainSidebarToggleFadeExclusion
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar(includesLegacyFade: true)
        }
        .overlay(alignment: .bottom) {
            ScrollToBottomButtonOverlay(scrollController: chatScrollController) {
                scrollToBottomGlassIcon()
            }
        }
    }

    private func chatScrollView(topPadding: CGFloat) -> some View {
        ScrollViewReader { proxy in
            GeometryReader { scrollGeometry in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($messages) { $message in
                            let liveAssistantDisplay = liveAssistantDisplays[message.id]
                            let isStreamingMessage = activeAssistantMessageID == message.id
                            let liveReasoningChannel = isStreamingMessage && activeAssistantReasoningIsExpanded
                                ? liveAssistantDisplay?.reasoningChannel
                                : nil
                            MessageBubble(
                                message: $message,
                                isStreaming: isStreamingMessage,
                                hasStreamingReasoning: isStreamingMessage && activeAssistantHasReasoning,
                                hasStreamingContent: isStreamingMessage && activeAssistantHasContent,
                                streamingContentChannel: liveAssistantDisplay?.contentChannel,
                                streamingReasoningChannel: liveReasoningChannel,
                                markdownRenderCache: markdownRenderCache[message.id],
                                showsActions: activeMessageActionID == message.id,
                                onSelect: {
                                    selectMessageAction(for: message.id)
                                },
                                onReasoningExpansionChanged: { isExpanded in
                                    handleReasoningExpansionChange(for: message.id, isExpanded: isExpanded)
                                },
                                onRegenerate: {
                                    regenerateAssistantResponse(message.id)
                                },
                                onEdit: {
                                    startEditingUserMessage(message.id)
                                }
                            )
                                .id(message.id)
                        }

                        if #available(iOS 18.0, *) {
                            Color.clear
                                .frame(height: bottomScrollContentPadding)
                                .id("bottomAnchor")
                        } else {
                            Color.clear
                                .frame(height: bottomScrollContentPadding)
                                .id("bottomAnchor")
                                .background(
                                    GeometryReader { bottomGeometry in
                                        Color.clear.preference(
                                            key: ChatScrollBottomDistancePreferenceKey.self,
                                            value: chatScrollBottomDistance(
                                                bottomGeometry: bottomGeometry,
                                                viewportHeight: scrollGeometry.size.height
                                            )
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, topPadding)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: scrollGeometry.size.height,
                        alignment: .top
                    )
                    .contentShape(Rectangle())
                }
                .coordinateSpace(name: ChatScrollMetrics.coordinateSpaceName)
                .observeChatScrollUserInteraction(
                    onBegin: {
                        chatScrollController.beginUserScrollInteraction()
                    },
                    onEnd: {
                        chatScrollController.endUserScrollInteraction()
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        DispatchQueue.main.async {
                            if didTapMessageBubble {
                                didTapMessageBubble = false
                                return
                            }

                            hideKeyboard()

                            withAnimation(.easeOut(duration: 0.16)) {
                                activeMessageActionID = nil
                            }
                        }
                    }
                )
                .onChange(of: messages.count) { _, _ in
                    chatScrollController.requestImmediateAutoScroll(animated: true)
                }
                .observeChatScrollBottomDistance { distanceFromBottom in
                    chatScrollController.scheduleBottomDistanceUpdate(distanceFromBottom)
                }
                .onAppear {
                    chatScrollController.setScrollAction { animated in
                        forceScrollToBottom(proxy: proxy, animated: animated)
                    }
                }
                .onDisappear {
                    chatScrollController.clearScrollAction()
                }
            }
        }
    }

    private func inputBar(includesLegacyFade: Bool) -> some View {
        inputGlassContainer {
            VStack(alignment: .leading, spacing: 8) {
                if !pendingImageAttachments.isEmpty || !pendingFileAttachments.isEmpty {
                    pendingAttachmentPreview
                }

                if let imageSelectionError {
                    Text(imageSelectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                }

                if let speechInputError = speechInputController.errorMessage {
                    Text(speechInputError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                }

                if isEditingMessage {
                    Text("正在修改消息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                inputComposer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)
                .stroke(
                    isAttachmentDropTargeted ? Color.accentColor.opacity(0.56) : Color.secondary.opacity(0.12),
                    lineWidth: isAttachmentDropTargeted ? 2 : 1
                )
        )
        .onDrop(
            of: [UTType.image.identifier] + ChatFileAttachmentReader.dropTypeIdentifiers,
            isTargeted: $isAttachmentDropTargeted,
            perform: handleDroppedAttachments
        )
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .padding(.horizontal, inputBarHorizontalPadding)
        .padding(.top, inputBarTopPadding)
        .padding(.bottom, inputBarBottomPadding)
        .background(alignment: .bottom) {
            if includesLegacyFade {
                inputBottomFadeBackdrop
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: InputBarHeightPreferenceKey.self,
                    value: ChatScrollMetrics.roundedDistance(geometry.size.height)
                )
            }
        }
        .onPreferenceChange(InputBarHeightPreferenceKey.self) { height in
            guard abs(inputBarMeasuredHeight - height) > 0.5 else { return }

            inputBarMeasuredHeight = height
            chatScrollController.requestImmediateAutoScroll(animated: false)
        }
    }

    private var topFloatingControls: some View {
        ZStack {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                topGlassControl {
                    Button {
                        hideKeyboard()
                        createConversation()
                    } label: {
                        topIconLabel(systemName: "square.and.pencil")
                    }
                }
                .disabled(isGenerating || !canCreateConversation)
                .accessibilityLabel("新建对话")
            }

            topConversationTitleMenu
        }
        .padding(.horizontal, topControlsHorizontalPadding)
        .padding(.top, topControlsTopPadding)
    }

    private var sidebarToggleControl: some View {
        VStack {
            HStack {
                topGlassControl {
                    Button {
                        hideKeyboard()
                        setConversationSidebarVisibility(!showConversationSidebar)
                    } label: {
                        topIconLabel(systemName: "sidebar.left")
                    }
                }
                .accessibilityLabel(showConversationSidebar ? "关闭对话列表" : "打开对话列表")

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, topControlsHorizontalPadding)
        .padding(.top, topControlsTopPadding)
    }

    @ViewBuilder
    private var inputComposer: some View {
        inputComposerContent
    }

    private var inputComposerContent: some View {
        HStack(alignment: .center, spacing: 10) {
            inputOptionsMenu

            ImagePastingTextView(
                text: $inputText,
                isFocused: $isInputFocused,
                focusRequestID: inputFocusRequestID,
                placeholder: "输入消息...",
                onPasteImageProviders: pasteImageProvidersFromInputMenu
            )
            .font(.body)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11)

            speechInputControl

            inputActionControl
        }
    }

    private var speechInputControl: some View {
        Button {
            toggleSpeechInput()
        } label: {
            controlGlassIcon(
                systemName: speechInputController.isRecording ? "mic.fill" : "mic",
                size: 18,
                weight: .semibold,
                frame: 40,
                tint: speechControlBackground,
                foreground: speechInputController.isRecording ? .red : .primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechInputController.isRecording ? "停止语音输入" : "开始语音输入")
    }

    @ViewBuilder
    private var inputActionControl: some View {
        if isEditingMessage {
            HStack(spacing: 8) {
                Button {
                    cancelEditingMessage()
                } label: {
                    controlGlassIcon(
                        systemName: "xmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: cancelControlBackground,
                        foreground: .red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消修改")

                Menu {
                    Button("仅修改") {
                        stopSpeechInputIfNeeded()
                        saveEditingMessageOnly()
                    }

                    Button("修改并发送") {
                        stopSpeechInputIfNeeded()
                        saveEditingMessageAndRegenerate()
                    }
                } label: {
                    controlGlassIcon(
                        systemName: "checkmark",
                        size: 19,
                        weight: .semibold,
                        frame: 48,
                        tint: sendControlBackground
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
            }
        } else {
            Button {
                if isGenerating {
                    stopGenerating()
                } else {
                    stopSpeechInputIfNeeded()
                    sendMessage()
                }
            } label: {
                controlGlassIcon(
                    systemName: isGenerating ? "stop.fill" : "paperplane.fill",
                    size: 19,
                    weight: .semibold,
                    frame: 48,
                    tint: sendControlBackground
                )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSendMessage)
        }
    }

    private var pendingAttachmentPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingImageAttachments.isEmpty {
                imageAttachmentPreview
            }

            if !pendingFileAttachments.isEmpty {
                fileAttachmentPreview
            }
        }
    }

    private var imageAttachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImageAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        ChatAttachmentImage(attachment: attachment)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            removePendingImage(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white, .black.opacity(0.60))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    private var fileAttachmentPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingFileAttachments) { attachment in
                    ChatFileAttachmentChip(attachment: attachment) {
                        removePendingFile(attachment.id)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var modelSelectionMenuItems: some View {
        ForEach(currentConfiguration.models) { model in
            Button {
                selectModel(model.name)
            } label: {
                if model.name == currentConfiguration.selectedModel {
                    Label(model.name, systemImage: "checkmark")
                } else {
                    Text(model.name)
                }
            }
        }

        Divider()

        Button {
            hideKeyboard()
            showConfiguration = true
        } label: {
            Label("管理模型", systemImage: "slider.horizontal.3")
        }
    }

    private var modelMenu: some View {
        Menu {
            modelSelectionMenuItems
        } label: {
            controlGlassIcon(
                systemName: "cube.transparent",
                size: 19,
                weight: .semibold,
                frame: 48,
                tint: inputGlassTint
            )
        }
        .disabled(isGenerating)
    }

    private var topConversationTitleMenu: some View {
        let title = currentConversationTitle

        return topGlassControl {
            Menu {
                modelSelectionMenuItems
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: topConversationTitleButtonWidth - 38, alignment: .center)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: topConversationTitleButtonWidth, height: topControlSize)
                .contentShape(Capsule())
            }
        }
        .disabled(isGenerating)
        .accessibilityLabel("当前对话：\(title)")
    }

    private var inputOptionsMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label(
                    currentConfiguration.selectedModelSupportsImages ? "上传图片" : "当前模型不支持图片",
                    systemImage: "photo"
                )
            }
            .disabled(!currentConfiguration.selectedModelSupportsImages)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("上传文件", systemImage: "doc")
            }

            if currentConfiguration.selectedModelSupportsReasoning {
                Divider()

                Button {
                    setReasoningEnabled(false)
                } label: {
                    if currentConfiguration.reasoningEnabled {
                        Text("思考强度：关闭")
                    } else {
                        Label("思考强度：关闭", systemImage: "checkmark")
                    }
                }

                ForEach(ReasoningEffort.allCases) { effort in
                    Button {
                        selectReasoningEffort(effort)
                    } label: {
                        if currentConfiguration.reasoningEnabled,
                           effort == currentConfiguration.reasoningEffort {
                            Label("思考强度：\(effort.title)", systemImage: "checkmark")
                        } else {
                            Text("思考强度：\(effort.title)")
                        }
                    }
                }
            }
        } label: {
            controlGlassIcon(
                systemName: "plus",
                size: 16,
                weight: .bold,
                frame: 34,
                tint: inputGlassTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多输入选项")
    }

    private var openSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if !showConversationSidebar,
                   value.translation.width > 46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.6 {
                    hideKeyboard()
                    setConversationSidebarVisibility(true)
                }
            }
    }

    private var closeSidebarGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                if showConversationSidebar,
                   value.translation.width < -46,
                   abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    setConversationSidebarVisibility(false)
                }
            }
    }

    private var currentConversationTitle: String {
        guard let selectedConversationID,
              let conversation = conversations.first(where: { $0.id == selectedConversationID }) else {
            return "新对话"
        }

        return conversation.title
    }

    private var canCreateConversation: Bool {
        !isGenerating
    }

    private var currentConversationIsBlank: Bool {
        messages.isEmpty
            && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingImageAttachments.isEmpty
            && pendingFileAttachments.isEmpty
    }

    private var currentConfiguration: AIConfiguration {
        AIConfigurationStore.selectedConfiguration(
            from: configurations,
            selectedID: selectedConfigurationID
        )
    }

    private var configurationSummary: String {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCustomHeaders = !configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let authSummary = hasAPIKey ? "API Key" : (hasCustomHeaders ? "自定义请求头" : "未配置认证")

        let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointSummary = endpoint.isEmpty ? "未配置 Endpoint" : endpoint
        let reasoningSummary = configuration.selectedModelSupportsReasoning
            ? (configuration.reasoningEnabled ? "思考 \(configuration.reasoningEffort.title)" : "思考关闭")
            : "无推理"
        let imageSummary = configuration.selectedModelSupportsImages ? "图片" : "文字"
        return "\(configuration.name) · \(configuration.selectedModel) · \(imageSummary) · \(reasoningSummary) · \(trimmedBaseURL.isEmpty ? "未配置 Base URL" : trimmedBaseURL) · \(endpointSummary) · \(authSummary)"
    }

    func sendMessage() {
        stopSpeechInputIfNeeded()
        let userText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageAttachments = pendingImageAttachments
        let fileAttachments = pendingFileAttachments
        ensureCurrentConversation()
        startStreamingResponse(
            userText: userText,
            imageAttachments: imageAttachments,
            fileAttachments: fileAttachments,
            contextMessages: messages,
            appendsUserMessage: true
        )
    }

    private func startStreamingResponse(
        userText: String,
        imageAttachments: [ChatImageAttachment],
        imageContextDescription: String = "",
        fileAttachments: [ChatFileAttachment],
        contextMessages: [ChatMessage],
        appendsUserMessage: Bool,
        existingUserMessageID: UUID? = nil
    ) {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil
        let usesImageAttachments = configuration.selectedModelSupportsImages
        let generatesImageContextDescriptions = configuration.generatesImageContextDescriptions

        guard !userText.isEmpty || !imageAttachments.isEmpty || !fileAttachments.isEmpty else { return }

        guard imageAttachments.isEmpty
                || usesImageAttachments
                || !imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendAssistantError("当前模型不支持图片输入，且这条图片消息还没有可用的隐藏描述。请切换到支持图片的多模态模型后重试。")
            return
        }

        guard usesImageAttachments || !containsImageWithoutContextDescription(in: contextMessages) else {
            appendAssistantError("当前模型不支持图片输入，且上下文中有图片消息还没有可用的隐藏描述。请稍后重试，或切换到支持图片的多模态模型。")
            return
        }

        guard !trimmedBaseURL.isEmpty else {
            appendAssistantError("请先配置 Base URL。")
            return
        }

        guard !model.isEmpty else {
            appendAssistantError("请先选择模型。")
            return
        }

        aiService.resetConversation(
            with: contextMessages,
            systemPrompt: configuration.systemPrompt,
            usesImageAttachments: usesImageAttachments
        )
        clearInputState()
        isGenerating = true
        streamingOutputHaptics.prepareForStreaming()
        chatScrollController.returnToBottom()
        streamingTokenBuffer.reset()
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isFlushScheduled = false
        activeMessageActionID = nil

        var userMessageIDForImageContext = existingUserMessageID
        if appendsUserMessage {
            let userMessage = ChatMessage(
                role: "user",
                content: userText,
                imageAttachments: imageAttachments,
                imageContextDescription: imageContextDescription,
                fileAttachments: fileAttachments
            )
            messages.append(userMessage)
            userMessageIDForImageContext = userMessage.id
        }

        let assistantMessage = ChatMessage(role: "assistant", content: "")
        messages.append(assistantMessage)
        invalidateMarkdownCache(for: assistantMessage.id)
        persistCurrentConversation()

        let assistantMessageID = assistantMessage.id
        activeAssistantMessageID = assistantMessageID
        liveAssistantDisplays[assistantMessageID] = AssistantLiveDisplay()

        aiService.sendStreamingMessage(
            message: userText,
            imageAttachments: imageAttachments,
            imageContextDescription: imageContextDescription,
            fileAttachments: fileAttachments,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            usesImageAttachments: usesImageAttachments,
            isReasoningDisplayActive: {
                activeAssistantMessageID == assistantMessageID && activeAssistantReasoningIsExpanded
            },
            onReasoningToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }

                streamingTokenBuffer.appendReasoning(token)
                if !activeAssistantHasReasoning {
                    activeAssistantHasReasoning = true
                }
                updateLiveReasoningDisplayIfNeeded(for: assistantMessageID, token: token)
            },
            onContentToken: { token in
                guard activeAssistantMessageID == assistantMessageID else { return }
                guard isGenerating else { return }

                collapseReasoningAfterThinkingIfNeeded(for: assistantMessageID)
                appendLiveContentToken(token, for: assistantMessageID)
                if !activeAssistantHasContent {
                    activeAssistantHasContent = true
                }
                streamingTokenBuffer.appendContent(token)
                scheduleTokenFlush(for: assistantMessageID)
                scheduleStreamingAutoScroll()
            },
            onComplete: { _ in
                guard activeAssistantMessageID == assistantMessageID else { return }

                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: true)
                isGenerating = false
                streamingOutputHaptics.impactForOutputCompletion()
                streamingOutputHaptics.reset()
                activeAssistantMessageID = nil
                activeAssistantHasReasoning = false
                activeAssistantHasContent = false
                activeAssistantReasoningIsExpanded = false
                activeAssistantDidCollapseReasoningAfterThinking = false
                prepareMarkdownCache(for: assistantMessageID)
                persistCurrentConversation()
                generateTitleIfNeeded()
            },
            onError: { error in
                guard activeAssistantMessageID == assistantMessageID else { return }

                cancelScheduledFlush()
                flushPendingTokens(for: assistantMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: false)

                let persistentError = persistentAssistantErrorMessage(from: error)
                if let index = messages.firstIndex(where: { $0.id == assistantMessageID }) {
                    messages[index].content = persistentError
                    publishLiveContentUpdate(for: assistantMessageID, chunks: [persistentError], resetsText: true)
                }

                isGenerating = false
                streamingOutputHaptics.reset()
                activeAssistantMessageID = nil
                activeAssistantHasReasoning = false
                activeAssistantHasContent = false
                activeAssistantReasoningIsExpanded = false
                activeAssistantDidCollapseReasoningAfterThinking = false
                prepareMarkdownCache(for: assistantMessageID)
                persistCurrentConversation()
            }
        )

        if usesImageAttachments,
           generatesImageContextDescriptions,
           !imageAttachments.isEmpty,
           imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let selectedConversationID,
           let userMessageIDForImageContext {
            generateImageContextDescriptionIfNeeded(
                for: userMessageIDForImageContext,
                in: selectedConversationID,
                imageAttachments: imageAttachments,
                baseURL: trimmedBaseURL,
                apiKey: trimmedAPIKey,
                customHeaders: trimmedCustomHeaders,
                model: model,
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort
            )
        }
    }

    private func appendAssistantError(_ content: String) {
        let message = ChatMessage(role: "assistant", content: content)
        messages.append(message)
        prepareMarkdownCache(for: message.id, content: content)
        persistCurrentConversation()
    }

    private func persistentAssistantErrorMessage(from error: String) -> String {
        let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedError.isEmpty ? "请求失败" : trimmedError
    }

    private func containsImageWithoutContextDescription(in messages: [ChatMessage]) -> Bool {
        messages.contains { message in
            message.role == "user"
                && !message.imageAttachments.isEmpty
                && message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func generateImageContextDescriptionIfNeeded(
        for messageID: UUID,
        in conversationID: UUID,
        imageAttachments: [ChatImageAttachment],
        baseURL: String,
        apiKey: String,
        customHeaders: String,
        model: String,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?
    ) {
        aiService.generateImageContextDescription(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            apiKey: apiKey,
            customHeaders: customHeaders,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ) { description in
            guard let description,
                  !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            saveImageContextDescription(
                description,
                for: messageID,
                in: conversationID,
                matching: imageAttachments
            )
        }
    }

    private func saveImageContextDescription(
        _ description: String,
        for messageID: UUID,
        in conversationID: UUID,
        matching imageAttachments: [ChatImageAttachment]
    ) {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else { return }

        if selectedConversationID == conversationID,
           let messageIndex = messages.firstIndex(where: { $0.id == messageID }),
           messages[messageIndex].imageAttachments == imageAttachments {
            messages[messageIndex].imageContextDescription = trimmedDescription
            persistCurrentConversation(refreshesUpdatedAt: false)
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == messageID }),
              conversations[conversationIndex].messages[messageIndex].imageAttachments == imageAttachments else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].imageContextDescription = trimmedDescription
        ConversationStore.saveConversations(conversations)
    }

    private func clearInputState() {
        speechInputController.cancelRecording()
        inputText = ""
        pendingImageAttachments = []
        pendingFileAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        editingMessageID = nil
        isInputFocused = false
        inputFocusRequestID += 1
        resetSpeechInputMergeState()
    }

    private func startEditingUserMessage(_ id: UUID) {
        didTapMessageBubble = true

        guard !isGenerating,
              editingMessageID != id,
              let message = messages.first(where: { $0.id == id && $0.role == "user" }) else {
            return
        }
        stopSpeechInputIfNeeded()

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            activateEditingInput(
                for: id,
                text: message.content,
                images: message.imageAttachments,
                files: message.fileAttachments
            )
            imageSelectionError = nil
            activeMessageActionID = nil
        }

        DispatchQueue.main.async {
            var focusTransaction = Transaction(animation: nil)
            focusTransaction.disablesAnimations = true

            withTransaction(focusTransaction) {
                isInputFocused = true
                inputFocusRequestID += 1
            }
        }
    }

    private func activateEditingInput(
        for id: UUID,
        text: String,
        images: [ChatImageAttachment],
        files: [ChatFileAttachment]
    ) {
        editingMessageID = id
        inputText = text
        pendingImageAttachments = images
        pendingFileAttachments = files
        selectedPhotoItems = []
    }

    private func selectMessageAction(for id: UUID) {
        didTapMessageBubble = true
        guard activeMessageActionID != id else { return }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                activeMessageActionID = id
            }
        }
    }

    private func cancelEditingMessage() {
        stopSpeechInputIfNeeded()
        clearInputState()
    }

    private func saveEditingMessageOnly() {
        stopSpeechInputIfNeeded()
        guard let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return
        }

        let keepsImageContextDescription = messages[index].imageAttachments == pendingImageAttachments
        messages[index].content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        messages[index].imageAttachments = pendingImageAttachments
        if !keepsImageContextDescription {
            messages[index].imageContextDescription = ""
        }
        messages[index].fileAttachments = pendingFileAttachments
        invalidateMarkdownCache(for: editingMessageID)
        persistCurrentConversation()
        removeUnreferencedConversationImages()
        clearInputState()
    }

    private func saveEditingMessageAndRegenerate() {
        stopSpeechInputIfNeeded()
        guard !isGenerating,
              let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return
        }

        let editedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedImages = pendingImageAttachments
        let editedFiles = pendingFileAttachments
        let editedImageContextDescription = messages[index].imageAttachments == editedImages
            ? messages[index].imageContextDescription
            : ""
        messages[index].content = editedText
        messages[index].imageAttachments = editedImages
        messages[index].imageContextDescription = editedImageContextDescription
        messages[index].fileAttachments = editedFiles
        messages.removeSubrange((index + 1)..<messages.count)
        pruneMarkdownCache()
        let context = Array(messages.prefix(index))
        persistCurrentConversation()
        removeUnreferencedConversationImages()

        startStreamingResponse(
            userText: editedText,
            imageAttachments: editedImages,
            imageContextDescription: editedImageContextDescription,
            fileAttachments: editedFiles,
            contextMessages: context,
            appendsUserMessage: false,
            existingUserMessageID: editingMessageID
        )
    }

    private func regenerateAssistantResponse(_ id: UUID) {
        didTapMessageBubble = true

        guard !isGenerating,
              let assistantIndex = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }),
              let userIndex = messages[..<assistantIndex].lastIndex(where: { $0.role == "user" }) else {
            return
        }

        activeMessageActionID = nil
        let userMessage = messages[userIndex]
        messages.removeSubrange((userIndex + 1)..<messages.count)
        pruneMarkdownCache()
        let context = Array(messages.prefix(userIndex))
        persistCurrentConversation()

        startStreamingResponse(
            userText: userMessage.content,
            imageAttachments: userMessage.imageAttachments,
            imageContextDescription: userMessage.imageContextDescription,
            fileAttachments: userMessage.fileAttachments,
            contextMessages: context,
            appendsUserMessage: false,
            existingUserMessageID: userMessage.id
        )
    }

    func scheduleTokenFlush(for messageID: UUID) {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        flushTask?.cancel()

        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flushPendingTokens(
                for: messageID,
                flushesReasoning: false,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }
    }

    func flushPendingTokens(
        for messageID: UUID,
        flushesReasoning: Bool = true,
        invalidatesMarkdownCache: Bool = true,
        requestsAutoScroll: Bool = true
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            streamingTokenBuffer.clearPendingTokens()
            isFlushScheduled = false
            flushTask = nil
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            if flushesReasoning, streamingTokenBuffer.hasPendingReasoningText {
                messages[index].reasoningChunks.append(
                    contentsOf: streamingTokenBuffer.consumePendingReasoningChunks()
                )
            }

            if streamingTokenBuffer.hasPendingContentText {
                messages[index].content += streamingTokenBuffer.consumePendingContentText()
                activeAssistantHasContent = true
                if invalidatesMarkdownCache {
                    invalidateMarkdownCache(for: messageID)
                }
            }
        }

        if requestsAutoScroll {
            scheduleStreamingAutoScroll()
        }

        isFlushScheduled = false
        flushTask = nil
    }

    func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }

    private func appendLiveContentToken(_ token: String, for messageID: UUID) {
        publishLiveContentUpdate(for: messageID, chunks: [token], resetsText: false)
    }

    private func updateLiveReasoningDisplayIfNeeded(for messageID: UUID, token: String) {
        guard activeAssistantMessageID == messageID,
              activeAssistantReasoningIsExpanded else { return }

        publishLiveReasoningUpdate(
            for: messageID,
            chunks: [token],
            resetsText: false,
            appendsProgressively: token.utf16.count > Self.liveReasoningProgressiveAppendThreshold
        )
    }

    private func collapseReasoningAfterThinkingIfNeeded(for messageID: UUID) {
        guard activeAssistantMessageID == messageID,
              activeAssistantHasReasoning,
              !activeAssistantDidCollapseReasoningAfterThinking else { return }

        activeAssistantDidCollapseReasoningAfterThinking = true
        let wasReasoningExpanded = activeAssistantReasoningIsExpanded
        activeAssistantReasoningIsExpanded = false

        if let index = messages.firstIndex(where: { $0.id == messageID }),
           messages[index].isReasoningExpanded {
            messages[index].isReasoningExpanded = false
            clearLiveReasoningDisplay(for: messageID)
        } else if wasReasoningExpanded {
            clearLiveReasoningDisplay(for: messageID)
        }
    }

    private func handleReasoningExpansionChange(for messageID: UUID, isExpanded: Bool) {
        guard activeAssistantMessageID == messageID else { return }

        activeAssistantReasoningIsExpanded = isExpanded
        if isExpanded {
            publishLiveReasoningReset(for: messageID, appendsProgressively: true)
        } else {
            clearLiveReasoningDisplay(for: messageID)
        }
    }

    private func publishLiveReasoningReset(
        for messageID: UUID,
        appendsProgressively: Bool
    ) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }

        var chunks: [String] = []
        if !message.reasoningContent.isEmpty {
            chunks.append(message.reasoningContent)
        }
        chunks.append(contentsOf: message.reasoningChunks)
        chunks.append(contentsOf: streamingTokenBuffer.reasoningChunksSnapshot)

        publishLiveReasoningUpdate(
            for: messageID,
            chunks: chunks,
            resetsText: true,
            appendsProgressively: appendsProgressively
        )
    }

    private func publishLiveReasoningUpdate(
        for messageID: UUID,
        chunks: [String],
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        guard let reasoningChannel = liveAssistantDisplays[messageID]?.reasoningChannel else { return }

        reasoningChannel.publish(
            chunks: chunks,
            resetsText: resetsText,
            appendsProgressively: appendsProgressively
        )
        triggerStreamingOutputHapticIfNeeded(chunks: chunks, resetsText: resetsText)
    }

    private func clearLiveReasoningDisplay(for messageID: UUID) {
        publishLiveReasoningUpdate(for: messageID, chunks: [], resetsText: true)
    }

    private func publishLiveContentUpdate(for messageID: UUID, chunks: [String], resetsText: Bool) {
        guard let contentChannel = liveAssistantDisplays[messageID]?.contentChannel else { return }

        contentChannel.publish(chunks: chunks, resetsText: resetsText)
        triggerStreamingOutputHapticIfNeeded(chunks: chunks, resetsText: resetsText)
    }

    private func triggerStreamingOutputHapticIfNeeded(chunks: [String], resetsText: Bool) {
        guard !resetsText,
              chunks.contains(where: { !$0.isEmpty }) else { return }

        streamingOutputHaptics.impactForOutputRefresh()
    }

    private func pruneLiveAssistantDisplays() {
        let messageIDs = Set(messages.map(\.id))
        liveAssistantDisplays = liveAssistantDisplays.filter { messageIDs.contains($0.key) }
    }

    private func scheduleStreamingAutoScroll() {
        chatScrollController.scheduleStreamingAutoScroll()
    }

    private static let liveReasoningProgressiveAppendThreshold = 720

    private func prepareMarkdownCaches(for messages: [ChatMessage]) {
        messages
            .filter { $0.role == "assistant" && !$0.content.isEmpty }
            .forEach { prepareMarkdownCache(for: $0.id, content: $0.content) }
    }

    private func prepareMarkdownCache(
        for messageID: UUID,
        onPrepared: (() -> Void)? = nil
    ) {
        guard let message = messages.first(where: { $0.id == messageID && $0.role == "assistant" }),
              !message.content.isEmpty else {
            invalidateMarkdownCache(for: messageID)
            onPrepared?()
            return
        }
        prepareMarkdownCache(for: messageID, content: message.content, onPrepared: onPrepared)
    }

    private func prepareMarkdownCache(
        for messageID: UUID,
        content: String,
        onPrepared: (() -> Void)? = nil
    ) {
        if ErrorDetailContent.parse(content) != nil {
            invalidateMarkdownCache(for: messageID)
            onPrepared?()
            return
        }

        let style = MarkdownRenderStyle(
            textColor: .label,
            baseFont: .preferredFont(forTextStyle: .body),
            textAlignment: .left,
            userInterfaceStyle: colorScheme == .dark ? .dark : .light,
            displayScale: UIScreen.main.scale
        )
        let signature = MarkdownRenderCacheEntry.signature(for: content, style: style)
        guard markdownRenderCache[messageID]?.signature != signature else {
            onPrepared?()
            return
        }

        markdownRenderTasks[messageID]?.cancel()
        markdownRenderTasks[messageID] = Task { @MainActor in
            let entry = await Task.detached(priority: .utility) {
                await MarkdownRenderCacheEntry.make(content: content, style: style)
            }.value

            guard !Task.isCancelled else { return }
            markdownRenderCache[messageID] = entry
            markdownRenderTasks[messageID] = nil
            onPrepared?()
        }
    }

    private func invalidateMarkdownCache(for messageID: UUID) {
        markdownRenderTasks[messageID]?.cancel()
        markdownRenderTasks[messageID] = nil
        markdownRenderCache[messageID] = nil
    }

    private func resetMarkdownCache(for messages: [ChatMessage]) {
        markdownRenderTasks.values.forEach { $0.cancel() }
        markdownRenderTasks = [:]
        markdownRenderCache = [:]
        prepareMarkdownCaches(for: messages)
    }

    private func pruneMarkdownCache() {
        let messageIDs = Set(messages.map(\.id))
        markdownRenderCache = markdownRenderCache.filter { messageIDs.contains($0.key) }
        for (messageID, task) in markdownRenderTasks where !messageIDs.contains(messageID) {
            task.cancel()
            markdownRenderTasks[messageID] = nil
        }
        pruneLiveAssistantDisplays()
    }

    func stopGenerating(triggersCompletionHaptic: Bool = true) {
        let stoppedMessageID = activeAssistantMessageID

        aiService.cancelStreaming()
        cancelScheduledFlush()

        if let stoppedMessageID {
            flushPendingTokens(for: stoppedMessageID, invalidatesMarkdownCache: true, requestsAutoScroll: true)

            if let index = messages.firstIndex(where: { $0.id == stoppedMessageID }) {
                messages[index].isStopped = true
                prepareMarkdownCache(for: stoppedMessageID)
            }
        }

        activeAssistantMessageID = nil
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isGenerating = false
        if triggersCompletionHaptic, stoppedMessageID != nil {
            streamingOutputHaptics.impactForOutputCompletion()
        }
        streamingOutputHaptics.reset()
        streamingTokenBuffer.reset()
        isFlushScheduled = false
        persistCurrentConversation()
    }

    func hideKeyboard() {
        isInputFocused = false
        KeyboardDismissal.dismissNowAndDeferred()
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        guard currentConfiguration.selectedModelSupportsImages else {
            selectedPhotoItems = []
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        imageSelectionError = nil

        Task {
            var attachments = [ChatImageAttachment]()

            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let attachment = storedImageAttachment(from: data) else {
                    continue
                }

                attachments.append(attachment)
            }

            if attachments.isEmpty, !items.isEmpty {
                imageSelectionError = "图片读取失败，请重新选择。"
            } else {
                setPendingImageAttachments(attachments)
                imageSelectionError = nil
            }
        }
    }

    private func storedImageAttachment(from data: Data) -> ChatImageAttachment? {
        guard imageDataIsWithinLimits(data) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        return storedImageAttachment(from: image)
    }

    private func storedImageAttachment(fromImageFileAt url: URL) -> ChatImageAttachment? {
        guard imageFileIsWithinLimits(url),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return storedImageAttachment(from: data)
    }

    private func storedImageAttachment(from image: UIImage) -> ChatImageAttachment? {
        guard imagePixelCount(image) <= maxImagePixelCount else { return nil }
        let scaledImage = image.scaledDown(maxDimension: 1600)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        return ConversationImageStore.storeJPEGData(jpegData)
    }

    private func imageDataIsWithinLimits(_ data: Data) -> Bool {
        guard data.count <= maxImageInputByteCount else { return false }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }

        let pixelCount = Int64(width.intValue) * Int64(height.intValue)
        return pixelCount > 0 && pixelCount <= maxImagePixelCount
    }

    private func imageFileIsWithinLimits(_ url: URL) -> Bool {
        guard url.isFileURL,
              let byteCount = fileByteCount(for: url),
              byteCount <= maxImageInputByteCount,
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }

        let pixelCount = Int64(width.intValue) * Int64(height.intValue)
        return pixelCount > 0 && pixelCount <= maxImagePixelCount
    }

    private func fileByteCount(for url: URL) -> Int? {
        if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) {
            if resourceValues.isRegularFile == false {
                return nil
            }
            if let fileSize = resourceValues.fileSize {
                return fileSize
            }
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private func imagePixelCount(_ image: UIImage) -> Int64 {
        let scale = max(image.scale, 1)
        let width = Int64((image.size.width * scale).rounded())
        let height = Int64((image.size.height * scale).rounded())
        return width * height
    }

    private func setPendingImageAttachments(_ attachments: [ChatImageAttachment]) {
        pendingImageAttachments = Array(attachments.prefix(maxImageAttachmentCount))
        if attachments.count > maxImageAttachmentCount {
            imageSelectionError = "最多只能添加 \(maxImageAttachmentCount) 张图片，已保留前 \(maxImageAttachmentCount) 张。"
        }
    }

    private func appendPendingImageAttachments(_ attachments: [ChatImageAttachment], source: String) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        guard !attachments.isEmpty else {
            imageSelectionError = "\(source)图片读取失败。"
            return
        }

        let remainingCount = maxImageAttachmentCount - pendingImageAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = "最多只能添加 \(maxImageAttachmentCount) 张图片。"
            return
        }

        pendingImageAttachments.append(contentsOf: attachments.prefix(remainingCount))
        imageSelectionError = attachments.count > remainingCount
            ? "最多只能添加 \(maxImageAttachmentCount) 张图片，已保留前 \(maxImageAttachmentCount) 张。"
            : nil
    }

    private func handleDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        let imageProviders = providers.filter { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }
        }

        guard !imageProviders.isEmpty else { return false }

        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入，已忽略图片。"
            return false
        }

        imageSelectionError = nil

        Task {
            var attachments = [ChatImageAttachment]()

            for provider in imageProviders.prefix(maxImageAttachmentCount) {
                guard let attachment = await imageAttachment(from: provider) else {
                    continue
                }

                attachments.append(attachment)
            }

            appendPendingImageAttachments(attachments, source: "拖拽")
        }

        return true
    }

    private func loadSelectedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }

            Task {
                var attachments = [ChatFileAttachment]()
                var firstError: String?

                for url in urls.prefix(maxFileAttachmentCount) {
                    do {
                        attachments.append(try ChatFileAttachmentReader.attachment(from: url))
                    } catch {
                        if firstError == nil {
                            firstError = error.localizedDescription
                        }
                    }
                }

                appendPendingFileAttachments(attachments, source: "选择", fallbackError: firstError)
            }
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            imageSelectionError = "文件选择失败：\(error.localizedDescription)"
        }
    }

    private func appendPendingFileAttachments(
        _ attachments: [ChatFileAttachment],
        source: String,
        fallbackError: String? = nil
    ) {
        guard !attachments.isEmpty else {
            imageSelectionError = fallbackError ?? "\(source)文件读取失败。"
            return
        }

        let remainingCount = maxFileAttachmentCount - pendingFileAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = "最多只能添加 \(maxFileAttachmentCount) 个文件。"
            return
        }

        pendingFileAttachments.append(contentsOf: attachments.prefix(remainingCount))

        if attachments.count > remainingCount {
            imageSelectionError = "最多只能添加 \(maxFileAttachmentCount) 个文件，已保留前 \(maxFileAttachmentCount) 个。"
        } else {
            imageSelectionError = fallbackError
        }
    }

    private func handleDroppedAttachments(_ providers: [NSItemProvider]) -> Bool {
        let handledImages = handleDroppedImages(providers)
        let handledFiles = handleDroppedFiles(providers)
        return handledImages || handledFiles
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { provider in
            !providerContainsImage(provider) && providerContainsReadableFile(provider)
        }

        guard !fileProviders.isEmpty else { return false }

        Task {
            var attachments = [ChatFileAttachment]()

            for provider in fileProviders.prefix(maxFileAttachmentCount) {
                guard let attachment = await fileAttachment(from: provider) else { continue }
                attachments.append(attachment)
            }

            appendPendingFileAttachments(attachments, source: "拖拽")
        }

        return true
    }

    private func providerContainsImage(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
    }

    private func providerContainsReadableFile(_ provider: NSItemProvider) -> Bool {
        provider.registeredTypeIdentifiers.contains { identifier in
            isReadableFileIdentifier(identifier)
        }
    }

    private func fileAttachment(from provider: NSItemProvider) async -> ChatFileAttachment? {
        if provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier),
           let url = await fileURL(from: provider),
           url.isFileURL {
            return try? ChatFileAttachmentReader.attachment(from: url)
        }

        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            isReadableFileIdentifier(identifier)
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: try? ChatFileAttachmentReader.attachment(from: url))
            }
        }
    }

    private func isReadableFileIdentifier(_ identifier: String) -> Bool {
        guard identifier != UTType.fileURL.identifier else { return true }
        guard let type = UTType(identifier) else { return false }

        return ChatFileAttachmentReader.supportedDocumentTypes.contains { supportedType in
            type.conforms(to: supportedType) || supportedType.conforms(to: type)
        }
    }

    private func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL, url.isFileURL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString),
                   url.isFileURL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func imageAttachment(from provider: NSItemProvider) async -> ChatImageAttachment? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url,
                      let attachment = storedImageAttachment(fromImageFileAt: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: attachment)
            }
        }
    }

    private func pasteImageProvidersFromInputMenu(_ providers: [NSItemProvider]) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = "当前模型不支持图片输入。"
            return
        }

        let imageProviders = providers.filter(providerContainsImage)
        guard !imageProviders.isEmpty else {
            imageSelectionError = "剪贴板中没有可粘贴的图片。"
            return
        }

        Task {
            var attachments = [ChatImageAttachment]()
            for provider in imageProviders.prefix(maxImageAttachmentCount) {
                guard let attachment = await imageAttachment(from: provider) else { continue }
                attachments.append(attachment)
            }

            appendPendingImageAttachments(attachments, source: "剪贴板")
        }
    }

    private func removePendingImage(_ id: UUID) {
        pendingImageAttachments.removeAll { $0.id == id }
        if pendingImageAttachments.isEmpty {
            selectedPhotoItems = []
        }
        removeUnreferencedConversationImages()
    }

    private func removePendingFile(_ id: UUID) {
        pendingFileAttachments.removeAll { $0.id == id }
    }

    private func chatScrollBottomDistance(bottomGeometry: GeometryProxy, viewportHeight: CGFloat) -> CGFloat {
        let bottomY = bottomGeometry.frame(in: .named(ChatScrollMetrics.coordinateSpaceName)).maxY
        return ChatScrollMetrics.roundedDistance(bottomY - viewportHeight)
    }

    func forceScrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
    }

    private func selectModel(_ model: String) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].selectedModel = model
        if !configurations[index].models.contains(where: { $0.name == model }) {
            configurations[index].models.append(AIModelConfiguration(name: model))
        }
        if !configurations[index].selectedModelSupportsImages {
            pendingImageAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
        }
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func selectReasoningEffort(_ effort: ReasoningEffort) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].reasoningEnabled = true
        configurations[index].reasoningEffort = effort
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func setReasoningEnabled(_ isEnabled: Bool) {
        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) else { return }
        configurations[index].reasoningEnabled = isEnabled
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.saveConfigurations(configurations)
    }

    private func reloadConfigurations() {
        configurations = AIConfigurationStore.loadConfigurations()
        selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
        if selectedConfigurationID == nil,
           let firstConfiguration = configurations.first {
            selectedConfigurationID = firstConfiguration.id
            AIConfigurationStore.saveSelectedConfigurationID(firstConfiguration.id)
        }
    }

    private func loadSelectedConversation() {
        if let selectedConversationID,
           let conversation = conversations.first(where: { $0.id == selectedConversationID }) {
            restoreConversation(conversation, closesSidebar: false)
        } else if let firstConversation = conversations.first {
            restoreConversation(firstConversation, closesSidebar: false)
        } else {
            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            resetMarkdownCache(for: messages)
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            liveAssistantDisplays = [:]
            aiService.resetConversation(
                with: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
        }
    }

    private func ensureCurrentConversation() {
        if selectedConversationID == nil || !conversations.contains(where: { $0.id == selectedConversationID }) {
            let conversation = AIConversation()
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
        }
    }

    private func selectConversation(_ id: UUID) {
        selectConversation(id, closesSidebar: true)
    }

    private func selectConversation(_ id: UUID, closesSidebar: Bool) {
        if isGenerating {
            stopGenerating(triggersCompletionHaptic: false)
        } else {
            persistCurrentConversation()
        }

        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        restoreConversation(conversation, closesSidebar: closesSidebar)
    }

    private func restoreConversation(_ conversation: AIConversation, closesSidebar: Bool) {
        speechInputController.cancelRecording()
        selectedConversationID = conversation.id
        messages = conversation.messages
        resetMarkdownCache(for: messages)
        inputText = ""
        resetSpeechInputMergeState()
        pendingImageAttachments = []
        pendingFileAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        liveAssistantDisplays = [:]
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        activeMessageActionID = nil
        editingMessageID = nil
        streamingTokenBuffer.reset()
        isFlushScheduled = false
        chatScrollController.returnToBottom()
        aiService.resetConversation(
            with: messages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages
        )
        ConversationStore.saveSelectedConversationID(conversation.id)

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func createConversation() {
        createConversation(closesSidebar: true)
    }

    private func openConfigurationFromSidebar(closesSidebar: Bool) {
        hideKeyboard()
        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
        showConfiguration = true
    }

    private func createConversation(closesSidebar: Bool) {
        guard canCreateConversation else {
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        if isGenerating {
            stopGenerating(triggersCompletionHaptic: false)
        } else {
            persistCurrentConversation()
        }

        if currentConversationIsBlank {
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        if let emptyConversation = conversations.first(where: { conversation in
            conversation.id != selectedConversationID && !conversation.hasInformation
        }) {
            selectConversation(emptyConversation.id, closesSidebar: closesSidebar)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        messages = []
        resetMarkdownCache(for: messages)
        speechInputController.cancelRecording()
        inputText = ""
        resetSpeechInputMergeState()
        pendingImageAttachments = []
        pendingFileAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        activeAssistantMessageID = nil
        liveAssistantDisplays = [:]
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        activeMessageActionID = nil
        editingMessageID = nil
        streamingTokenBuffer.reset()
        isFlushScheduled = false
        aiService.resetConversation(
            with: [],
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages
        )
        ConversationStore.saveSelectedConversationID(conversation.id)
        ConversationStore.saveConversations(conversations)

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func deleteConversation(_ id: UUID) {
        if conversations.count <= 1 {
            if selectedConversationID == id && isGenerating {
                aiService.cancelStreaming()
                isGenerating = false
            }

            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            resetMarkdownCache(for: messages)
            speechInputController.cancelRecording()
            inputText = ""
            resetSpeechInputMergeState()
            pendingImageAttachments = []
            pendingFileAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeAssistantMessageID = nil
            liveAssistantDisplays = [:]
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            activeMessageActionID = nil
            editingMessageID = nil
            streamingTokenBuffer.reset()
            isFlushScheduled = false
            setConversationSidebarVisibility(false)
            aiService.resetConversation(
                with: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            ConversationStore.saveSelectedConversationID(conversation.id)
            ConversationStore.saveConversations(conversations)
            removeUnreferencedConversationImages()
            return
        }

        if selectedConversationID == id && isGenerating {
            stopGenerating(triggersCompletionHaptic: false)
        }

        conversations.removeAll { $0.id == id }

        if selectedConversationID == id || selectedConversationID == nil {
            let nextConversation = conversations[0]
            selectedConversationID = nextConversation.id
            messages = nextConversation.messages
            resetMarkdownCache(for: messages)
            pendingImageAttachments = []
            pendingFileAttachments = []
            selectedPhotoItems = []
            imageSelectionError = nil
            activeAssistantMessageID = nil
            liveAssistantDisplays = [:]
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            activeMessageActionID = nil
            editingMessageID = nil
            streamingTokenBuffer.reset()
            isFlushScheduled = false
            aiService.resetConversation(
                with: messages,
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            ConversationStore.saveSelectedConversationID(nextConversation.id)
        }

        ConversationStore.saveConversations(conversations)
        removeUnreferencedConversationImages()
    }

    private func persistApplicationStateForLifecycle() {
        let shouldRefreshUpdatedAt = activeAssistantMessageID != nil

        if let activeAssistantMessageID {
            cancelScheduledFlush()
            flushPendingTokens(for: activeAssistantMessageID, invalidatesMarkdownCache: false, requestsAutoScroll: false)
        }

        persistCurrentConversation(synchronize: true, refreshesUpdatedAt: shouldRefreshUpdatedAt)
    }

    private func persistCurrentConversation(
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return
        }

        conversations[index].messages = messages
        if refreshesUpdatedAt {
            conversations[index].updatedAt = Date()
        }
        ConversationStore.saveConversations(conversations, synchronize: synchronize)
    }

    private func removeUnreferencedConversationImages() {
        var retainedConversations = conversations
        if let selectedConversationID,
           let index = retainedConversations.firstIndex(where: { $0.id == selectedConversationID }) {
            retainedConversations[index].messages = messages
        }
        ConversationImageStore.removeUnreferencedImages(
            retainedBy: retainedConversations,
            additionalAttachments: pendingImageAttachments
        )
    }

    private func generateTitleIfNeeded() {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }),
              !conversations[index].hasGeneratedTitle,
              conversations[index].messages.contains(where: { $0.role == "assistant" && !$0.content.isEmpty }) else {
            return
        }

        let titleMessages = conversations[index].messages
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil

        guard !model.isEmpty else { return }

        aiService.generateConversationTitle(
            messages: titleMessages,
            baseURL: trimmedBaseURL,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ) { title in
            if self.selectedConversationID == selectedConversationID {
                persistCurrentConversation()
            }

            guard let title,
                  let currentIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }),
                  !title.isEmpty else {
                return
            }

            conversations[currentIndex].title = title
            conversations[currentIndex].hasGeneratedTitle = true
            conversations[currentIndex].updatedAt = Date()
            ConversationStore.saveConversations(conversations)
        }
    }

}

struct MessageBubble: View {
    @Binding var message: ChatMessage
    let isStreaming: Bool
    let hasStreamingReasoning: Bool
    let hasStreamingContent: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let streamingReasoningChannel: StreamingTextUpdateChannel?
    let markdownRenderCache: MarkdownRenderCacheEntry?
    let showsActions: Bool
    let onSelect: () -> Void
    let onReasoningExpansionChanged: (Bool) -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool {
        message.role == "user"
    }

    private var userBubbleColor: Color {
        colorScheme == .dark ? Color.blue.opacity(0.72) : Color.accentColor
    }

    private var assistantBubbleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.gray.opacity(0.16)
    }

    private var assistantReasoningColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.10)
    }

    private var displayContent: String {
        message.content
    }

    private var displayReasoningContent: String {
        message.reasoningContent
    }

    private var displayReasoningChunks: [String] {
        message.reasoningChunks
    }

    private var hasReasoningContent: Bool {
        hasStreamingReasoning || !displayReasoningContent.isEmpty || !displayReasoningChunks.isEmpty
    }

    private var shouldShowMessageContentBubble: Bool {
        if isUser {
            return !displayContent.isEmpty
        }

        if !displayContent.isEmpty || hasStreamingContent || message.isStopped {
            return true
        }

        return !isStreaming && !hasReasoningContent
    }

    private var messageContentBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                SelectableTextView(
                    text: displayContent,
                    textColor: .white,
                    font: .preferredFont(forTextStyle: .body),
                    textAlignment: .left,
                    sizing: .natural,
                    onTap: onSelect
                )
            } else if displayContent.isEmpty, !hasStreamingContent {
                Text(message.isStopped ? "已停止生成。" : "正在生成回答...")
            } else {
                AssistantMessageContent(
                    content: displayContent,
                    isStreaming: isStreaming,
                    streamingContentChannel: streamingContentChannel,
                    isStopped: message.isStopped,
                    markdownRenderCache: markdownRenderCache
                )
            }
        }
        .font(.body)
        .foregroundStyle(isUser ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isUser ? userBubbleColor : assistantBubbleColor)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 48)
                userMessageStack
            } else {
                assistantMessageStack
                Spacer(minLength: 48)
            }
        }
    }

    private var userMessageStack: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.imageAttachments.isEmpty {
                messageImages
            }

            if !message.fileAttachments.isEmpty {
                messageFiles
            }

            if !message.content.isEmpty {
                messageContentBubble
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
            }

            if showsActions {
                Button {
                    onEdit()
                } label: {
                    Label("修改", systemImage: "pencil")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private var assistantMessageStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasReasoningContent {
                reasoningBlock
            }

            if shouldShowMessageContentBubble {
                messageContentBubble
            }

            if showsActions, !displayContent.isEmpty {
                Button {
                    onRegenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.16), value: showsActions)
    }

    private var messageImages: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88, maximum: 140), spacing: 8)],
            alignment: .trailing,
            spacing: 8
        ) {
            ForEach(message.imageAttachments) { attachment in
                ChatAttachmentImage(attachment: attachment)
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )
            }
        }
        .frame(width: imageGridWidth, alignment: .trailing)
        .onTapGesture {
            onSelect()
        }
    }

    private var messageFiles: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(message.fileAttachments) { attachment in
                ChatFileAttachmentChip(attachment: attachment)
            }
        }
        .frame(maxWidth: 300, alignment: .trailing)
        .onTapGesture {
            onSelect()
        }
    }

    private var imageGridWidth: CGFloat {
        let count = min(message.imageAttachments.count, 2)
        guard count > 0 else { return 0 }
        return CGFloat(count) * 112 + CGFloat(count - 1) * 8
    }

    private var reasoningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                message.isReasoningExpanded.toggle()
                onReasoningExpansionChanged(message.isReasoningExpanded)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: message.isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)

                    Text("思考过程")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if message.isReasoningExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ReasoningMessageContent(
                        content: displayReasoningContent,
                        chunks: displayReasoningChunks,
                        isStreaming: isStreaming,
                        streamingChannel: streamingReasoningChannel
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(assistantReasoningColor)
                )
                .transaction { transaction in
                    transaction.animation = nil
                }
                .clipped()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .clipped()
    }
}

struct AssistantMessageContent: View {
    let content: String
    let isStreaming: Bool
    let streamingContentChannel: StreamingTextUpdateChannel?
    let isStopped: Bool
    let markdownRenderCache: MarkdownRenderCacheEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorContent = ErrorDetailContent.parse(content),
               streamingContentChannel == nil,
               !isStreaming {
                CollapsibleErrorDetailsView(error: errorContent)
            } else if let streamingContentChannel {
                StreamingAssistantMarkdownText(streamingChannel: streamingContentChannel)
            } else if isStreaming {
                StreamingAssistantMarkdownText(content)
            } else if let markdownRenderCache {
                AssistantMarkdownText(renderCache: markdownRenderCache)
            } else {
                PlainAssistantText(content)
            }

            if isStopped {
                Text("已停止生成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ErrorDetailContent: Equatable {
    let summary: String
    let details: String

    static func parse(_ message: String) -> ErrorDetailContent? {
        let normalized = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorRange = normalized.range(of: "\n\n") else { return nil }

        let summary = String(normalized[..<separatorRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let details = String(normalized[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !summary.isEmpty,
              !details.isEmpty,
              summaryLooksLikeError(summary) else {
            return nil
        }

        return ErrorDetailContent(summary: summary, details: details)
    }

    private static func summaryLooksLikeError(_ summary: String) -> Bool {
        summary.hasPrefix("请求失败")
            || summary.hasPrefix("解析失败")
            || summary.hasPrefix("模型列表解析失败")
            || summary.hasPrefix("流式请求失败")
            || summary.contains("状态码")
    }
}

struct CollapsibleErrorMessageView: View {
    let message: String

    var body: some View {
        if let error = ErrorDetailContent.parse(message) {
            CollapsibleErrorDetailsView(error: error)
        } else {
            Text(message)
        }
    }
}

private struct CollapsibleErrorDetailsView: View {
    let error: ErrorDetailContent
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var detailBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.summary)

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)

                    Text("错误详细信息")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(error.details)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(detailBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReasoningMessageContent: View {
    let content: String
    let chunks: [String]
    let isStreaming: Bool
    let streamingChannel: StreamingTextUpdateChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let streamingChannel {
                ScrollableSelectableTextView(
                    text: "",
                    streamingChannel: streamingChannel,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: true
                )
            } else if !chunks.isEmpty {
                ScrollableSelectableTextView(
                    text: "",
                    chunks: chunks,
                    appendsChunksProgressively: true,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: false
                )
            } else if usesScrollableTextView {
                ScrollableSelectableTextView(
                    text: content,
                    textColor: .secondaryLabel,
                    font: .preferredFont(forTextStyle: .caption1),
                    textAlignment: .left,
                    height: 340,
                    scrollsToBottom: isStreaming
                )
            } else {
                ReasoningPlainText(content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesScrollableTextView: Bool {
        isStreaming || !chunks.isEmpty || content.utf16.count > Self.inlineCharacterLimit
    }

    private static let inlineCharacterLimit = 1_800
}

private struct ReasoningPlainText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .secondaryLabel,
            font: .preferredFont(forTextStyle: .caption1),
            textAlignment: .left
        )
    }
}

struct StreamingAssistantMarkdownText: View {
    let content: String
    let streamingChannel: StreamingTextUpdateChannel?
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderedContent: String
    @State private var pendingAppendChunks: [String] = []
    @State private var renderedSegments: [StreamingChatMarkdownSegment]
    @State private var renderCache = PreparedMarkdownBlockCache()
    @State private var renderTask: Task<Void, Never>?
    @State private var needsRenderAfterCurrentTask = false
    @State private var streamingObserverID: UUID?

    init(_ content: String) {
        self.content = content
        streamingChannel = nil
        _renderedContent = State(initialValue: content)
        _renderedSegments = State(initialValue: Self.fallbackSegments(for: content))
    }

    init(streamingChannel: StreamingTextUpdateChannel) {
        content = ""
        self.streamingChannel = streamingChannel
        _renderedContent = State(initialValue: "")
        _renderedSegments = State(initialValue: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(renderedSegments) { segment in
                switch segment.kind {
                case let .text(blocks):
                    if !blocks.isEmpty {
                        SelectableMarkdownTextView(blocks: blocks)
                    }
                case let .fallbackText(text):
                    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
                        StreamingMarkdownText(trimmedText)
                            .equatable()
                    }
                case let .code(language, code):
                    StreamingCodeBlock(content: code, language: language)
                case let .math(formula, displayMode):
                    LaTeXFormulaView(formula: formula, displayMode: displayMode)
                        .equatable()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            attachStreamingChannelIfNeeded()
            if streamingChannel == nil, !renderedContent.isEmpty {
                scheduleRender(delay: .zero)
            }
        }
        .onChange(of: content) { _, newContent in
            guard streamingChannel == nil else { return }
            renderedContent = newContent
            scheduleRender()
        }
        .onChange(of: colorScheme) { _, _ in
            renderCache = PreparedMarkdownBlockCache()
            scheduleRender(delay: .zero)
        }
        .onDisappear {
            cancelRenderTask()
            detachStreamingChannel()
        }
    }

    private var renderStyle: MarkdownRenderStyle {
        MarkdownRenderStyle(
            textColor: .label,
            baseFont: .preferredFont(forTextStyle: .body),
            textAlignment: .left,
            userInterfaceStyle: colorScheme == .dark ? .dark : .light,
            displayScale: UIScreen.main.scale
        )
    }

    private func scheduleRender(delay: Duration = Self.renderInterval) {
        guard renderTask == nil else {
            needsRenderAfterCurrentTask = true
            return
        }

        renderTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            applyPendingChunks()
            let contentSnapshot = renderedContent
            let style = renderStyle
            let cacheSnapshot = renderCache
            let result = await Task.detached(priority: .userInitiated) {
                await Self.renderSegments(
                    for: contentSnapshot,
                    style: style,
                    cache: cacheSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            if renderedContent == contentSnapshot {
                renderedSegments = result.segments
                renderCache = result.cache
            } else {
                needsRenderAfterCurrentTask = true
            }
            renderTask = nil
            let shouldRenderAgain = needsRenderAfterCurrentTask || !pendingAppendChunks.isEmpty
            needsRenderAfterCurrentTask = false
            if shouldRenderAgain {
                scheduleRender()
            }
        }
    }

    private func renderImmediately() {
        cancelRenderTask()
        applyPendingChunks()
        scheduleRender(delay: .zero)
    }

    private func applyPendingChunks() {
        guard !pendingAppendChunks.isEmpty else { return }
        renderedContent += pendingAppendChunks.joined()
        pendingAppendChunks.removeAll(keepingCapacity: true)
    }

    private func applyStreamingUpdate(_ update: StreamingTextUpdate) {
        if update.resetsText {
            cancelRenderTask()
            pendingAppendChunks.removeAll(keepingCapacity: true)
            needsRenderAfterCurrentTask = false
            renderedContent = update.chunks.joined()
            renderCache = PreparedMarkdownBlockCache()
            renderedSegments = Self.fallbackSegments(for: renderedContent)
            if !renderedContent.isEmpty {
                scheduleRender(delay: .zero)
            }
            return
        }

        guard !update.chunks.isEmpty else { return }
        pendingAppendChunks.append(contentsOf: update.chunks)
        if renderedContent.isEmpty {
            renderImmediately()
        } else {
            scheduleRender()
        }
    }

    private func attachStreamingChannelIfNeeded() {
        guard let streamingChannel, streamingObserverID == nil else { return }

        applyStreamingUpdate(streamingChannel.latest)
        streamingObserverID = streamingChannel.addObserver { update in
            applyStreamingUpdate(update)
        }
    }

    private func detachStreamingChannel() {
        if let streamingObserverID {
            streamingChannel?.removeObserver(streamingObserverID)
        }
        streamingObserverID = nil
    }

    private func cancelRenderTask() {
        renderTask?.cancel()
        renderTask = nil
        needsRenderAfterCurrentTask = false
    }

    private nonisolated static func fallbackSegments(for content: String) -> [StreamingChatMarkdownSegment] {
        ChatMarkdownBlockSegment.split(content).map { segment in
            switch segment.kind {
            case let .text(text):
                return StreamingChatMarkdownSegment(id: segment.id, kind: .fallbackText(text))
            case let .code(language, code):
                return StreamingChatMarkdownSegment(id: segment.id, kind: .code(language: language, code: code))
            case let .math(formula, displayMode):
                return StreamingChatMarkdownSegment(id: segment.id, kind: .math(formula: formula, displayMode: displayMode))
            }
        }
    }

    private nonisolated static func renderSegments(
        for content: String,
        style: MarkdownRenderStyle,
        cache: PreparedMarkdownBlockCache
    ) async -> StreamingMarkdownRenderResult {
        let previousBlockCache = cache
        var nextBlockCache = PreparedMarkdownBlockCache()
        var segments: [StreamingChatMarkdownSegment] = []

        for segment in ChatMarkdownBlockSegment.split(content) {
            switch segment.kind {
            case let .text(text):
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    segments.append(StreamingChatMarkdownSegment(
                        id: stableSegmentID(sourceID: segment.id, groupIndex: 0),
                        kind: .text([])
                    ))
                } else {
                    for (groupIndex, group) in splitStreamingTextGroups(trimmedText).enumerated() {
                        let textSignature = textSegmentSignature(for: group, style: style)
                        if let blocks = previousBlockCache.blocks(forTextSignature: textSignature) {
                            nextBlockCache.store(blocks, forTextSignature: textSignature)
                            segments.append(StreamingChatMarkdownSegment(
                                id: stableSegmentID(sourceID: segment.id, groupIndex: groupIndex),
                                kind: .text(blocks)
                            ))
                            continue
                        }

                        let preprocessedText = ChatMarkdownPreprocessor.preprocess(group)
                        let result = await PreparedMarkdownBlockRenderer.renderBlocks(
                            markdown: preprocessedText,
                            style: style,
                            cache: previousBlockCache
                        )
                        nextBlockCache.merge(result.cache)
                        nextBlockCache.store(result.blocks, forTextSignature: textSignature)
                        segments.append(StreamingChatMarkdownSegment(
                            id: stableSegmentID(sourceID: segment.id, groupIndex: groupIndex),
                            kind: .text(result.blocks)
                        ))
                    }
                }
            case let .code(language, code):
                segments.append(StreamingChatMarkdownSegment(
                    id: stableSegmentID(sourceID: segment.id, groupIndex: 0),
                    kind: .code(language: language, code: code)
                ))
            case let .math(formula, displayMode):
                segments.append(StreamingChatMarkdownSegment(
                    id: stableSegmentID(sourceID: segment.id, groupIndex: 0),
                    kind: .math(formula: formula, displayMode: displayMode)
                ))
            }
        }

        return StreamingMarkdownRenderResult(segments: segments, cache: nextBlockCache)
    }

    private nonisolated static func splitStreamingTextGroups(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var groups: [String] = []
        var index = 0

        func appendGroup(_ groupLines: [String]) {
            let group = groupLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !group.isEmpty {
                groups.append(group)
            }
        }

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            } else if let table = streamingTableGroup(in: lines, at: index) {
                appendGroup(Array(lines[index..<table]))
                index = table
            } else if isStreamingSingletonLine(lines[index]) {
                appendGroup([lines[index]])
                index += 1
            } else if isStreamingQuoteLine(lines[index]) {
                let nextIndex = collectStreamingLines(in: lines, from: index, while: isStreamingQuoteLine(_:))
                appendGroup(Array(lines[index..<nextIndex]))
                index = nextIndex
            } else {
                let nextIndex = collectStreamingParagraph(in: lines, from: index)
                appendGroup(Array(lines[index..<nextIndex]))
                index = nextIndex
            }
        }

        return groups.isEmpty ? [text] : groups
    }

    private nonisolated static func stableSegmentID(sourceID: Int, groupIndex: Int) -> Int {
        sourceID * 10_000 + groupIndex
    }

    private nonisolated static func collectStreamingParagraph(in lines: [String], from start: Int) -> Int {
        var index = start
        while index < lines.count {
            let line = lines[index]
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  streamingTableGroup(in: lines, at: index) == nil,
                  !isStreamingSingletonLine(line),
                  !isStreamingQuoteLine(line) else {
                break
            }
            index += 1
        }
        return max(index, start + 1)
    }

    private nonisolated static func collectStreamingLines(
        in lines: [String],
        from start: Int,
        while shouldInclude: (String) -> Bool
    ) -> Int {
        var index = start
        while index < lines.count, shouldInclude(lines[index]) {
            index += 1
        }
        return index
    }

    private nonisolated static func isStreamingSingletonLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let headingLevel = trimmed.prefix { $0 == "#" }.count
        let isHeading = (1...6).contains(headingLevel) && trimmed.dropFirst(headingLevel).first == " "
        let isDivider = trimmed.count >= 3 && (
            trimmed.allSatisfy { $0 == "-" } ||
            trimmed.allSatisfy { $0 == "*" } ||
            trimmed.allSatisfy { $0 == "_" }
        )
        return isHeading || isDivider || isStreamingListLine(trimmed)
    }

    private nonisolated static func isStreamingQuoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private nonisolated static func isStreamingListLine(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil
            || trimmedLine.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private nonisolated static func streamingTableGroup(
        in lines: [String],
        at index: Int
    ) -> Int? {
        guard index + 1 < lines.count,
              isStreamingTableSeparator(lines[index + 1]),
              streamingTableCells(in: lines[index]).count >= 2 else {
            return nil
        }

        var cursor = index + 2
        while cursor < lines.count, lines[cursor].contains("|") {
            cursor += 1
        }
        return cursor
    }

    private nonisolated static func isStreamingTableSeparator(_ line: String) -> Bool {
        let parts = streamingTableCells(in: line)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private nonisolated static func streamingTableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }

    private nonisolated static func textSegmentSignature(
        for text: String,
        style: MarkdownRenderStyle
    ) -> String {
        [
            style.signature,
            "text-segment",
            "\(text.count)",
            "\(text.hashValue)"
        ].joined(separator: ":")
    }

    private static let renderInterval: Duration = .milliseconds(50)
}

nonisolated struct StreamingChatMarkdownSegment: Identifiable, @unchecked Sendable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text([PreparedMarkdownBlock])
        case fallbackText(String)
        case code(language: String?, code: String)
        case math(formula: String, displayMode: Bool)
    }
}

nonisolated struct StreamingMarkdownRenderResult: @unchecked Sendable {
    let segments: [StreamingChatMarkdownSegment]
    let cache: PreparedMarkdownBlockCache
}

private struct StreamingMarkdownText: View, Equatable {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    static func == (lhs: StreamingMarkdownText, rhs: StreamingMarkdownText) -> Bool {
        lhs.markdown == rhs.markdown
    }

    var body: some View {
        if ChatLaTeXSegmentParser.containsInlineMath(in: markdown) {
            LaTeXInlineTextView(
                text: markdown,
                textColor: .label,
                font: .preferredFont(forTextStyle: .body),
                textAlignment: .left
            )
        } else {
            Text(Self.attributedString(from: markdown))
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func attributedString(from markdown: String) -> AttributedString {
        let fullOptions = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let attributed = try? AttributedString(markdown: markdown, options: fullOptions) {
            return attributed
        }

        let inlineOptions = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: inlineOptions)) ?? AttributedString(markdown)
    }
}

private struct StreamingCodeBlock: View {
    let content: String
    let language: String?
    @Environment(\.colorScheme) private var colorScheme

    private var languageName: String {
        let value = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "text"
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(languageName)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(content.isEmpty ? " " : content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}

struct PlainAssistantText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        SelectableTextView(
            text: content,
            textColor: .label,
            font: .preferredFont(forTextStyle: .body),
            textAlignment: .left
        )
    }
}

nonisolated struct PreparedChatMarkdownSegment: Identifiable, @unchecked Sendable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text([PreparedMarkdownBlock])
        case code(language: String?, code: String)
        case math(PreparedLaTeXFormula)
    }
}

nonisolated struct MarkdownRenderCacheEntry: @unchecked Sendable {
    let signature: String
    let renderedMarkdown: String
    let segments: [PreparedChatMarkdownSegment]
    private static let maxRenderedLaTeXFormulaCount = LaTeXRenderBudget.maxFormulasPerMessage

    private nonisolated init(
        signature: String,
        renderedMarkdown: String,
        segments: [PreparedChatMarkdownSegment]
    ) {
        self.signature = signature
        self.renderedMarkdown = renderedMarkdown
        self.segments = segments
    }

    nonisolated static func make(content: String, style: MarkdownRenderStyle) async -> MarkdownRenderCacheEntry {
        let signature = Self.signature(for: content, style: style)
        let renderedMarkdown = content
        var preparedSegments: [PreparedChatMarkdownSegment] = []
        var renderedFormulaCount = 0

        for segment in ChatMarkdownBlockSegment.split(content) {
            switch segment.kind {
            case let .text(text):
                let preprocessedText = ChatMarkdownPreprocessor.preprocess(text)
                let trimmedText = preprocessedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let blocks = trimmedText.isEmpty ? [] : await PreparedMarkdownBlockRenderer.renderBlocks(
                    markdown: trimmedText,
                    style: style
                )
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .text(blocks)))
            case let .code(language, code):
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .code(language: language, code: code)))
            case let .math(formula, displayMode):
                let preparedFormula: PreparedLaTeXFormula
                if renderedFormulaCount < maxRenderedLaTeXFormulaCount,
                   LaTeXRenderBudget.canRenderFormula(formula) {
                    renderedFormulaCount += 1
                    preparedFormula = await LaTeXSVGRenderer.shared.render(
                        formula: formula,
                        displayMode: displayMode,
                        style: style
                    )
                } else {
                    preparedFormula = LaTeXSVGRenderer.fallbackFormula(
                        formula: formula,
                        displayMode: displayMode,
                        error: "Formula render budget exceeded"
                    )
                }
                preparedSegments.append(PreparedChatMarkdownSegment(id: segment.id, kind: .math(preparedFormula)))
            }
        }

        return MarkdownRenderCacheEntry(
            signature: signature,
            renderedMarkdown: renderedMarkdown,
            segments: preparedSegments
        )
    }

    nonisolated static func signature(for content: String, style: MarkdownRenderStyle) -> String {
        "\(style.signature):\(content.count):\(content.hashValue)"
    }
}

struct AssistantMarkdownText: View {
    let renderCache: MarkdownRenderCacheEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(renderCache.segments) { segment in
                switch segment.kind {
                case let .text(blocks):
                    if !blocks.isEmpty {
                        SelectableMarkdownTextView(blocks: blocks)
                    }
                case let .code(language, code):
                    ChatCodeBlock(content: code, language: language)
                case let .math(formula):
                    PreparedLaTeXFormulaView(formula: formula)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatMarkdownBlockSegment: Identifiable {
    let id: Int
    let kind: Kind

    enum Kind {
        case text(String)
        case code(language: String?, code: String)
        case math(formula: String, displayMode: Bool)
    }

    nonisolated static func split(_ content: String) -> [ChatMarkdownBlockSegment] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [ChatMarkdownBlockSegment] = []
        var textBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendText() {
            guard !textBuffer.isEmpty else { return }
            appendTextSegments(textBuffer.joined(separator: "\n"))
            textBuffer.removeAll()
        }

        func appendTextSegments(_ text: String) {
            for segment in ChatLaTeXSegmentParser.split(text) {
                switch segment {
                case let .text(text):
                    segments.append(
                        ChatMarkdownBlockSegment(
                            id: segments.count,
                            kind: .text(text)
                        )
                    )
                case let .math(formula, displayMode):
                    segments.append(
                        ChatMarkdownBlockSegment(
                            id: segments.count,
                            kind: .math(formula: formula, displayMode: displayMode)
                        )
                    )
                }
            }
        }

        func appendCode() {
            segments.append(
                ChatMarkdownBlockSegment(
                    id: segments.count,
                    kind: .code(language: codeLanguage, code: codeBuffer.joined(separator: "\n"))
                )
            )
            codeBuffer.removeAll()
            codeLanguage = nil
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                if codeFence.isClosing(line) {
                    appendCode()
                    activeCodeFence = nil
                } else {
                    codeBuffer.append(line)
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendText()
                activeCodeFence = codeFence
                codeLanguage = codeFence.language
            } else {
                textBuffer.append(line)
            }
        }

        if activeCodeFence != nil {
            appendCode()
        } else {
            appendText()
        }

        return segments
    }
}

private struct ChatMarkdownCodeFence {
    let marker: Character
    let length: Int
    let language: String?

    nonisolated static func opening(in line: String) -> ChatMarkdownCodeFence? {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first, marker == "`" || marker == "~" else { return nil }

        let length = trimmedLine.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }

        let language = trimmedLine
            .dropFirst(length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)

        return ChatMarkdownCodeFence(marker: marker, length: length, language: language)
    }

    nonisolated func isClosing(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        let closingLength = trimmedLine.prefix { $0 == marker }.count
        guard closingLength >= length else { return false }
        return trimmedLine.dropFirst(closingLength).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum ChatMarkdownPreprocessor {
    nonisolated static func preprocess(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let segments = splitByCodeFence(normalized)
        return segments
            .map { segment in
                segment.isCode ? segment.text : preprocessMarkdownText(segment.text)
            }
            .joined()
    }

    private nonisolated static func preprocessMarkdownText(_ text: String) -> String {
        var processed = text
        processed = stripLaTeXDocumentShell(from: processed)
        processed = removeHTMLComments(from: processed)
        processed = removeTOCLines(from: processed)
        processed = transformCustomContainers(in: processed)
        processed = normalizeTables(in: processed)
        processed = transformInlineExtensions(in: processed)
        processed = stripAttributeLists(from: processed)
        processed = appendFootnotes(in: processed)
        return processed
    }

    private nonisolated static func splitByCodeFence(_ content: String) -> [(text: String, isCode: Bool)] {
        let lines = content.components(separatedBy: "\n")
        var segments: [(text: String, isCode: Bool)] = []
        var buffer: [String] = []
        var activeCodeFence: ChatMarkdownCodeFence?

        func appendBuffer(isCode: Bool, appendsTrailingNewline: Bool) {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: "\n") + (appendsTrailingNewline ? "\n" : "")
            segments.append((text, isCode))
            buffer = []
        }

        for line in lines {
            if let codeFence = activeCodeFence {
                buffer.append(line)
                if codeFence.isClosing(line) {
                    appendBuffer(isCode: true, appendsTrailingNewline: true)
                    activeCodeFence = nil
                }
            } else if let codeFence = ChatMarkdownCodeFence.opening(in: line) {
                appendBuffer(isCode: false, appendsTrailingNewline: true)
                activeCodeFence = codeFence
                buffer.append(line)
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            segments.append((buffer.joined(separator: "\n"), activeCodeFence != nil))
        }
        return segments
    }

    private nonisolated static func stripLaTeXDocumentShell(from text: String) -> String {
        var result = text

        if let beginRange = result.range(
            of: #"\\begin\{document\}"#,
            options: .regularExpression
        ) {
            let bodyStart = beginRange.upperBound
            if let endRange = result.range(
                of: #"\\end\{document\}"#,
                options: .regularExpression,
                range: bodyStart..<result.endIndex
            ) {
                result = String(result[bodyStart..<endRange.lowerBound])
            } else {
                result = String(result[bodyStart...])
            }
        }

        result = result.replacingOccurrences(
            of: #"(?m)^\s*\\(?:documentclass|usepackage)\b(?:\[[^\]]*\])?\{[^}]*\}\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?m)^\s*\\(?:begin|end)\{document\}\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func removeHTMLComments(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func removeTOCLines(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?mi)^\s*\[(?:toc|TOC)\]\s*$\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func transformCustomContainers(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var containerTitle: String?
        var containerLines: [String] = []

        func flushContainer() {
            guard let containerTitle else { return }
            result.append("> **\(containerTitle)**")
            result.append(contentsOf: containerLines.map { $0.isEmpty ? ">" : "> \($0)" })
            containerLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":::") {
                if containerTitle == nil {
                    let rawTitle = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    containerTitle = rawTitle.isEmpty ? "提示" : rawTitle
                    containerLines = []
                } else {
                    flushContainer()
                    containerTitle = nil
                }
                continue
            }

            if containerTitle != nil {
                containerLines.append(line)
            } else {
                result.append(line)
            }
        }

        flushContainer()
        return result.joined(separator: "\n")
    }

    private nonisolated static func normalizeTables(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if isTableHeader(lines: lines, at: index) {
                if let previous = result.last, !previous.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }

                var tableLines: [String] = []
                let columnCount = tableCellCount(in: lines[index])
                while index < lines.count, looksLikeTableLine(lines[index]) {
                    tableLines.append(normalizedTableLine(lines[index], columnCount: columnCount))
                    index += 1
                }
                result.append(contentsOf: tableLines)

                if index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append("")
                }
                continue
            }

            result.append(lines[index])
            index += 1
        }

        return result.joined(separator: "\n")
    }

    private nonisolated static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count,
              looksLikeTableLine(lines[index]) else {
            return false
        }
        return isTableSeparatorLine(lines[index + 1])
    }

    private nonisolated static func looksLikeTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") || trimmed.contains("｜")
    }

    private nonisolated static func normalizedTableLine(_ line: String) -> String {
        normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func normalizedTableLine(_ line: String, columnCount: Int) -> String {
        let cells = normalizedTableCells(in: line)
        guard !cells.isEmpty else { return normalizedTableLine(line) }

        let normalizedCells: [String]
        if isTableSeparatorLine(line) {
            normalizedCells = normalizedSeparatorCells(from: cells, columnCount: columnCount)
        } else {
            normalizedCells = normalizedDataCells(from: cells, columnCount: columnCount)
        }

        return "| " + normalizedCells.joined(separator: " | ") + " |"
    }

    private nonisolated static func normalizedTableText(_ line: String) -> String {
        line
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    private nonisolated static func normalizedTableCells(in line: String) -> [String] {
        let normalized = normalizedTableText(line)
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))

        return normalized
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private nonisolated static func tableCellCount(in line: String) -> Int {
        max(normalizedTableCells(in: line).count, 1)
    }

    private nonisolated static func normalizedDataCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount))
        while normalizedCells.count < columnCount {
            normalizedCells.append("")
        }
        return normalizedCells
    }

    private nonisolated static func normalizedSeparatorCells(from cells: [String], columnCount: Int) -> [String] {
        var normalizedCells = Array(cells.prefix(columnCount)).map { cell in
            let compact = cell.filter { !$0.isWhitespace }
            let leftAligned = compact.hasPrefix(":")
            let rightAligned = compact.hasSuffix(":")
            let marker = String(repeating: "-", count: max(3, compact.filter { $0 == "-" }.count))

            switch (leftAligned, rightAligned) {
            case (true, true):
                return ":" + marker + ":"
            case (true, false):
                return ":" + marker
            case (false, true):
                return marker + ":"
            case (false, false):
                return marker
            }
        }

        while normalizedCells.count < columnCount {
            normalizedCells.append("---")
        }
        return normalizedCells
    }

    private nonisolated static func isTableSeparatorLine(_ line: String) -> Bool {
        let cells = normalizedTableCells(in: line)

        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.filter { !$0.isWhitespace }
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private nonisolated static func transformInlineExtensions(in text: String) -> String {
        var processed = text
        processed = processed.replacingOccurrences(
            of: #"==([^=\n]+)=="#,
            with: "**$1**",
            options: .regularExpression
        )
        processed = processed.replacingOccurrences(
            of: #"<u>(.*?)</u>"#,
            with: "_$1_",
            options: [.regularExpression, .caseInsensitive]
        )
        return processed
    }

    private nonisolated static func stripAttributeLists(from text: String) -> String {
        text.replacingOccurrences(
            of: #"\s+\{[#.][^}\n]*\}"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func appendFootnotes(in text: String) -> String {
        var footnotes: [(id: String, body: String)] = []
        var bodyLines: [String] = []
        let pattern = #"^\[\^([^\]]+)\]:\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        for line in text.components(separatedBy: "\n") {
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
                  match.numberOfRanges == 3,
                  let idRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line) else {
                bodyLines.append(line)
                continue
            }

            footnotes.append((String(line[idRange]), String(line[bodyRange])))
        }

        guard !footnotes.isEmpty else { return text }
        let renderedFootnotes = footnotes.map { "[^\($0.id)]: \($0.body)" }.joined(separator: "\n")
        return bodyLines.joined(separator: "\n") + "\n\n---\n\n" + renderedFootnotes
    }
}

struct ImagePastingTextView: UIViewRepresentable {
    @Binding var text: String

    @Binding var isFocused: Bool
    let focusRequestID: Int
    let placeholder: String
    let onPasteImageProviders: ([NSItemProvider]) -> Void

    func makeUIView(context: Context) -> ImagePastingUITextView {
        let textView = ImagePastingUITextView()
        textView.delegate = context.coordinator
        textView.onPasteImageProviders = onPasteImageProviders
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: ImagePastingUITextView, context: Context) {
        if (textView.text ?? "") != text {
            textView.text = text
        }

        textView.onPasteImageProviders = onPasteImageProviders
        textView.isEditable = true
        textView.isSelectable = true
        textView.placeholderText = placeholder
        textView.accessibilityLabel = placeholder
        textView.updatePlaceholderVisibility()

        context.coordinator.updateFocus(
            for: textView,
            shouldBeFocused: isFocused,
            requestID: focusRequestID
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        let fittingWidth = width > 0 ? width : UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        )
        let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let maxHeight = lineHeight * 5
        let height = min(max(fittingSize.height, lineHeight), maxHeight)
        let shouldScroll = fittingSize.height > maxHeight
        if uiView.isScrollEnabled != shouldScroll {
            uiView.isScrollEnabled = shouldScroll
        }
        return CGSize(width: fittingWidth, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private let isFocused: Binding<Bool>
        private var lastHandledFocusRequestID: Int?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            if text.wrappedValue != updatedText {
                text.wrappedValue = updatedText
            }
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
        }

        func updateFocus(
            for textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            requestID: Int
        ) {
            let isNewRequest = lastHandledFocusRequestID != requestID
            guard isNewRequest || shouldBeFocused != textView.isFirstResponder else { return }
            lastHandledFocusRequestID = requestID

            if shouldBeFocused, textView.window != nil {
                if !textView.becomeFirstResponder() {
                    retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
                }
                return
            }

            retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
        }

        private func retryFocus(
            to textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            attemptsRemaining: Int
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.isFocused.wrappedValue == shouldBeFocused,
                      shouldBeFocused != textView.isFirstResponder else {
                    return
                }

                if shouldBeFocused {
                    guard textView.window != nil else {
                        if attemptsRemaining > 0 {
                            self.retryFocus(
                                to: textView,
                                shouldBeFocused: shouldBeFocused,
                                attemptsRemaining: attemptsRemaining - 1
                            )
                        }
                        return
                    }

                    if !textView.becomeFirstResponder(), attemptsRemaining > 0 {
                        self.retryFocus(
                            to: textView,
                            shouldBeFocused: shouldBeFocused,
                            attemptsRemaining: attemptsRemaining - 1
                        )
                    }
                } else {
                    textView.resignFirstResponder()
                }
            }
        }
    }
}

final class ImagePastingUITextView: UITextView {
    var onPasteImageProviders: (([NSItemProvider]) -> Void)?
    private let placeholderLabel = UILabel()

    var placeholderText: String = "" {
        didSet {
            placeholderLabel.text = placeholderText
        }
    }

    override var text: String! {
        didSet {
            updatePlaceholderVisibility()
        }
    }

    override var font: UIFont? {
        didSet {
            placeholderLabel.font = font
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func setupPlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = font ?? .preferredFont(forTextStyle: .body)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)),
           UIPasteboard.general.hasImages {
            return true
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let imageProviders = UIPasteboard.general.itemProviders.filter { provider in
            provider.registeredTypeIdentifiers.contains { identifier in
                UTType(identifier)?.conforms(to: .image) == true
            }
        }
        guard !imageProviders.isEmpty else {
            super.paste(sender)
            return
        }

        onPasteImageProviders?(imageProviders)
    }
}

struct ChatAttachmentImage: View {
    let attachment: ChatImageAttachment

    var body: some View {
        if let image = UIImage(chatImageAttachment: attachment) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

extension UIImage {
    convenience init?(chatImageAttachment attachment: ChatImageAttachment) {
        guard let data = ConversationImageStore.imageData(for: attachment) else { return nil }
        self.init(data: data)
    }

    func scaledDown(maxDimension: CGFloat) -> UIImage {
        let largestDimension = max(size.width, size.height)
        guard largestDimension > maxDimension else { return self }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

#Preview {
    ContentView()
}
