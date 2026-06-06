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
    static let scrollToBottomButtonHitOutset: CGFloat = 8
    static let scrollToBottomButtonHitSize: CGFloat = 52

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

struct MessageRevisionNavigationState: Equatable {
    let currentIndex: Int
    let count: Int

    var displayText: String {
        "\(currentIndex + 1) / \(count)"
    }

    var canMovePrevious: Bool {
        currentIndex > 0
    }

    var canMoveNext: Bool {
        currentIndex + 1 < count
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

    func resetForConversationChange() {
        cancelScheduledAutoScroll()
        isUserDragging = false
        hasUserPausedAutoScroll = false
        hasLeftBottomAfterUserPause = false
        isBottomDistanceUpdateScheduled = false
        pendingDistanceFromBottom = nil
        lastDistanceFromBottom = 0
        setIsScrolledToBottom(true)
        setShouldAutoScroll(true)
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
    let bottomPadding: CGFloat
    let label: () -> Label

    var body: some View {
        let adjustedBottomPadding = max(bottomPadding - ChatScrollMetrics.scrollToBottomButtonHitOutset, 0)
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
                .padding(.bottom, adjustedBottomPadding)
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

@MainActor
private final class ActiveConversationGeneration {
    let conversationID: UUID
    let assistantMessageID: UUID
    let service: AIService
    let tokenBuffer = StreamingTokenBuffer()
    var hasReasoning = false
    var hasContent = false
    var reasoningIsExpanded = false
    var didCollapseReasoningAfterThinking = false
    var isFlushScheduled = false
    var flushTask: Task<Void, Never>?

    init(conversationID: UUID, assistantMessageID: UUID, service: AIService) {
        self.conversationID = conversationID
        self.assistantMessageID = assistantMessageID
        self.service = service
    }

    func cancelScheduledFlush() {
        flushTask?.cancel()
        flushTask = nil
        isFlushScheduled = false
    }
}

@MainActor
private final class BackgroundRequestKeeper {
    private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid

    func update(
        activeRequestCount: Int,
        isSceneBackgrounded: Bool,
        expirationHandler: @escaping @MainActor () -> Void
    ) {
        guard activeRequestCount > 0, isSceneBackgrounded else {
            end()
            return
        }

        guard taskIdentifier == .invalid else { return }

        taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "AIClient.ActiveRequests") { [weak self] in
            Task { @MainActor in
                expirationHandler()
                self?.end()
            }
        }
    }

    func end() {
        guard taskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
    }
}

private final class StreamingOutputHaptics: ObservableObject {
    private let refreshGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let completionGenerator = UIImpactFeedbackGenerator(style: .heavy)
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

        refreshGenerator.impactOccurred(intensity: 0.55)
        refreshGenerator.prepare()
        lastImpactAt = now
    }

    func impactForOutputCompletion() {
        completionGenerator.impactOccurred(intensity: 1.0)
        completionGenerator.prepare()
        lastImpactAt = nil
    }

    func reset() {
        lastImpactAt = nil
    }
}

private final class ConversationActionHaptics: ObservableObject {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        generator.prepare()
    }

    func impact() {
        generator.impactOccurred(intensity: 0.7)
        generator.prepare()
    }
}

@MainActor
private final class ChatInputDraft: ObservableObject {
    private static let blankScalarSet = CharacterSet.whitespacesAndNewlines

    @Published var isFocused = false
    @Published private(set) var focusRequestID = 0
    @Published private(set) var textRevision = 0
    @Published private(set) var measuredLineCount = 1
    @Published private(set) var hasSubmittableText = false

    private(set) var text = ""

    var showsExpandedInputButton: Bool {
        measuredLineCount > 3
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateFromTextView(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
    }

    func updateFromExpandedTextView(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
        textRevision += 1
    }

    func updateMeasuredLineCount(_ lineCount: Int) {
        let lineCount = max(lineCount, 1)
        guard measuredLineCount != lineCount else { return }
        measuredLineCount = lineCount
    }

    func setText(_ newText: String) {
        guard text != newText else { return }
        text = newText
        updateSubmittableTextState()
        textRevision += 1
    }

    func clearText() {
        setText("")
    }

    func clearAndResignFocus() {
        clearText()
        isFocused = false
        focusRequestID += 1
    }

    func requestFocus() {
        isFocused = true
        focusRequestID += 1
    }

    private func updateSubmittableTextState() {
        let newValue = text.unicodeScalars.contains { !Self.blankScalarSet.contains($0) }
        if hasSubmittableText != newValue {
            hasSubmittableText = newValue
        }
    }
}

private struct PendingToolApproval: Identifiable {
    let id = UUID()
    let toolName: String
    let arguments: String
}

private struct ActiveAgentCapsule: Identifiable {
    enum Kind {
        case skill
        case mcp
    }

    let id: UUID
    let kind: Kind
    let title: String
    let icon: String
}

private struct ActiveAgentCapsuleView: View {
    @Environment(\.colorScheme) private var colorScheme

    let capsule: ActiveAgentCapsule
    let onClose: () -> Void

    private var glassTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.18)
    }

    private var glassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.62)
    }

    var body: some View {
        let shape = Capsule()

        HStack(spacing: 8) {
            Image(systemName: capsule.icon)
                .font(.system(size: 17, weight: .semibold))

            Text(capsule.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.blue)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(glassTint), in: shape)
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(glassTint))
                    .overlay(
                        shape
                            .stroke(glassHighlight, lineWidth: 1)
                            .blendMode(.screen)
                    )
            }
        }
        .accessibilityLabel(capsule.kind == .skill
            ? AppLocalizations.format(
                "accessibility.enabledSkill",
                defaultValue: "Enabled Skill: %@",
                arguments: [capsule.title]
            )
            : AppLocalizations.format(
                "accessibility.enabledMCP",
                defaultValue: "Enabled MCP: %@",
                arguments: [capsule.title]
            ))
    }
}

private struct ToolSearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
}

private struct ToolSearchResultCandidate: Equatable {
    let title: String
    let url: URL
}

private struct MovingHighlightTitle: View {
    let text: String
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isActive && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let cycle = 1.35
                let progress = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycle) / cycle
                let startX = progress * 2.2 - 1.1

                Text(text)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                baseColor,
                                highlightColor,
                                baseColor
                            ],
                            startPoint: UnitPoint(x: startX, y: 0.5),
                            endPoint: UnitPoint(x: startX + 0.72, y: 0.5)
                        )
                    )
            }
        } else {
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var baseColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.52) : Color.secondary
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.primary.opacity(0.90)
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var agentSkills = AgentCapabilityStore.loadSkills()
    @State private var mcpServers = AgentCapabilityStore.loadMCPServers()
    @State private var activeSkillIDs = Set<UUID>()
    @State private var activeMCPServerIDs = Set<UUID>()
    @State private var pendingToolApproval: PendingToolApproval?
    @State private var toolApprovalContinuation: CheckedContinuation<Bool, Never>?
    @StateObject private var speechInputController = SpeechInputController()
    @StateObject private var streamingOutputHaptics = StreamingOutputHaptics()
    @StateObject private var conversationActionHaptics = ConversationActionHaptics()
    @AppStorage(AIConfigurationStore.hapticFeedbackEnabledKey)
    private var isHapticFeedbackEnabled = AIConfigurationStore.defaultHapticFeedbackEnabled
    @StateObject private var inputDraft = ChatInputDraft()
    @State private var messages: [ChatMessage] = []
    @State private var conversations = ConversationStore.loadConversations()
    @State private var selectedConversationID: UUID? = ConversationStore.loadSelectedConversationID()
    @State private var privateConversationID: UUID?
    @State private var renamingConversationID: UUID?
    @State private var renamingConversationTitle = ""
    @State private var isRenameConversationAlertPresented = false
    @State private var conversationExportDocument = ConversationMarkdownDocument(text: "")
    @State private var conversationExportFileName = AppLocalizations.string(
        "markdown.fileName.fallback",
        defaultValue: "Conversation"
    )
    @State private var isConversationExporterPresented = false
    @State private var conversationExportErrorMessage: String?
    @State private var isGenerating = false
    @State private var showConfiguration = false
    @State private var showPromptSettings = false
    @State private var showAgentCapabilities = false
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
    @State private var activeConversationGenerations: [UUID: ActiveConversationGeneration] = [:]
    @State private var backgroundRequestKeeper = BackgroundRequestKeeper()
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
    @State private var speechInputBaseText = ""
    @State private var speechInputLastTranscript = ""
    @State private var speechInputLastMergedText = ""
    @State private var inputBarMeasuredHeight: CGFloat = 0
    @State private var isExpandedInputPresented = false
    @State private var hasLoadedInitialConversation = false
    @State private var showsMainSidebarToggleFadeExclusion = true
    @State private var showsSidebarToggleFadeExclusion = false
    @State private var sidebarVisibilityTransitionTask: Task<Void, Never>?
    @State private var conversationScrollRestoreTask: Task<Void, Never>?

    let aiService = AIService()
    private let maxActiveConversationGenerations = 4
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
    private let topModelButtonWidth: CGFloat = 148
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

    private var scrollToBottomButtonBottomPadding: CGFloat {
        let inputBarHeight = inputBarMeasuredHeight > 0 ? inputBarMeasuredHeight : inputBottomFadeOverlap
        return inputBarHeight + 12
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
                - max(scrollToBottomButtonBottomPadding - ChatScrollMetrics.scrollToBottomButtonHitOutset, 0)
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

    @ViewBuilder
    private var topConversationActionLabel: some View {
        if showsTemporaryChatNotice {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))

                Text("临时")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(height: topControlSize)
            .padding(.horizontal, 13)
            .contentShape(Capsule())
        } else {
            topIconLabel(systemName: topConversationActionSystemImage)
        }
    }

    private var storedConversations: [AIConversation] {
        guard let privateConversationID else { return conversations }
        return conversations.filter { $0.id != privateConversationID }
    }

    private var isPrivateConversationSelected: Bool {
        guard let privateConversationID else { return false }
        return selectedConversationID == privateConversationID
    }

    private var showsTemporaryChatNotice: Bool {
        isPrivateConversationSelected && messages.isEmpty
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText
            || !pendingImageAttachments.isEmpty
            || !pendingFileAttachments.isEmpty
    }

    private var isEditingMessage: Bool {
        editingMessageID != nil
    }

    private var hasPendingInputAttachments: Bool {
        !pendingImageAttachments.isEmpty || !pendingFileAttachments.isEmpty
    }

    private var expandedInputCover: some View {
        ExpandedChatInputView(
            inputDraft: inputDraft,
            isGenerating: isGenerating,
            isEditingMessage: isEditingMessage,
            isSpeechRecording: speechInputController.isRecording,
            hasPendingAttachments: hasPendingInputAttachments,
            onPasteImageProviders: pasteImageProvidersFromInputMenu,
            onDismiss: dismissExpandedInputAndRefocus,
            onToggleSpeechInput: toggleSpeechInput,
            onStopGenerating: {
                stopGenerating()
            },
            onSendMessage: handleExpandedInputSend,
            onCancelEditingMessage: handleExpandedInputCancelEditing,
            onSaveEditingMessageOnly: handleExpandedInputSaveEditingOnly,
            onSaveEditingMessageAndRegenerate: handleExpandedInputSaveEditingAndRegenerate
        )
    }

    private func presentExpandedInput() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isExpandedInputPresented = true
        }
    }

    private func dismissExpandedInput(refocusesInput: Bool) {
        withAnimation(.easeInOut(duration: 0.22)) {
            isExpandedInputPresented = false
        }
        guard refocusesInput else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard !isExpandedInputPresented else { return }
            inputDraft.requestFocus()
        }
    }

    private func dismissExpandedInputAndRefocus() {
        dismissExpandedInput(refocusesInput: true)
    }

    private func handleExpandedInputSend() {
        stopSpeechInputIfNeeded()
        let didStartSending = sendMessage()
        if didStartSending {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private func handleExpandedInputCancelEditing() {
        cancelEditingMessage()
        dismissExpandedInput(refocusesInput: false)
    }

    private func handleExpandedInputSaveEditingOnly() {
        stopSpeechInputIfNeeded()
        let didSave = saveEditingMessageOnly()
        if didSave {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private func handleExpandedInputSaveEditingAndRegenerate() {
        stopSpeechInputIfNeeded()
        let didStartSending = saveEditingMessageAndRegenerate()
        if didStartSending {
            dismissExpandedInput(refocusesInput: false)
        }
    }

    private var conversationExportErrorPresented: Binding<Bool> {
        Binding {
            conversationExportErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                conversationExportErrorMessage = nil
            }
        }
    }

    private func toggleSpeechInput() {
        if speechInputController.isRecording {
            speechInputController.stopRecording()
            return
        }

        speechInputBaseText = inputDraft.text
        speechInputLastTranscript = ""
        speechInputLastMergedText = inputDraft.text

        Task {
            await speechInputController.startRecording()
        }
    }

    private func stopSpeechInputIfNeeded() {
        if speechInputController.isRecording {
            speechInputController.stopRecording()
        }
    }

    private func resolveToolApproval(_ isAllowed: Bool) {
        let continuation = toolApprovalContinuation
        toolApprovalContinuation = nil
        pendingToolApproval = nil
        continuation?.resume(returning: isAllowed)
    }

    private func resetSpeechInputMergeState() {
        speechInputBaseText = inputDraft.text
        speechInputLastTranscript = ""
        speechInputLastMergedText = inputDraft.text
    }

    private func restoreChatScrollAfterConversationChange() {
        conversationScrollRestoreTask?.cancel()
        chatScrollController.resetForConversationChange()
        chatScrollController.requestImmediateAutoScroll(animated: false)

        conversationScrollRestoreTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            chatScrollController.requestImmediateAutoScroll(animated: false)

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            chatScrollController.requestImmediateAutoScroll(animated: false)
            conversationScrollRestoreTask = nil
        }
    }

    private func applySpeechTranscript(_ transcript: String) {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            speechInputLastTranscript = ""
            speechInputLastMergedText = inputDraft.text
            return
        }

        if speechInputLastTranscript.isEmpty {
            if inputDraft.text != speechInputBaseText {
                speechInputBaseText = inputDraft.text
            }
        } else if inputDraft.text != speechInputLastMergedText {
            speechInputBaseText = inputDraft.text
        }

        let mergedText = mergedSpeechInputText(
            baseText: speechInputBaseText,
            speechText: trimmedTranscript
        )
        inputDraft.setText(mergedText)
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
                    conversations: storedConversations,
                    selectedConversationID: selectedConversationID,
                    topSafeAreaInset: geometry.safeAreaInsets.top,
                    showsSidebarToggleFadeExclusion: showsSidebarToggleFadeExclusion && !layout.usesPersistentSidebar,
                    showsCloseButton: false,
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
                    onRename: beginRenamingConversation,
                    onTogglePinned: toggleConversationPin,
                    onExport: beginExportingConversation,
                    onDelete: deleteConversation
                )
                .frame(width: layout.sidebarWidth)
                .ignoresSafeArea(edges: [.top, .bottom])
                .offset(x: showsSidebar ? 0 : -layout.sidebarWidth)
                .animation(.easeOut(duration: sidebarTransitionDuration), value: showConversationSidebar)

                if !layout.usesPersistentSidebar {
                    sidebarToggleControl
                }
            }
            .simultaneousGesture(closeSidebarGesture)
        }
        .overlay {
            if isExpandedInputPresented {
                expandedInputCover
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .bottom))
                        )
                    )
                    .zIndex(1000)
            }
        }
        .onAppear {
            guard !hasLoadedInitialConversation else { return }
            hasLoadedInitialConversation = true
            loadSelectedConversation()
            if isHapticFeedbackEnabled {
                conversationActionHaptics.prepare()
            }
        }
        .sheet(isPresented: $showConfiguration) {
            AIConfigurationView()
        }
        .sheet(isPresented: $showPromptSettings) {
            AIPromptSettingsView(configurationID: currentConfiguration.id)
        }
        .sheet(isPresented: $showAgentCapabilities) {
            AgentCapabilitiesView()
        }
        .alert("重命名对话", isPresented: $isRenameConversationAlertPresented) {
            TextField("名称", text: $renamingConversationTitle)

            Button("取消", role: .cancel) {
                resetRenamingConversationState()
            }

            Button("保存") {
                commitRenamingConversation()
            }
        } message: {
            Text("请输入新的对话名称。")
        }
        .alert("导出失败", isPresented: conversationExportErrorPresented) {
            Button("好", role: .cancel) {
                conversationExportErrorMessage = nil
            }
        } message: {
            Text(conversationExportErrorMessage ?? "")
        }
        .alert(
            "允许工具调用？",
            isPresented: Binding(
                get: { pendingToolApproval != nil },
                set: { isPresented in
                    if !isPresented {
                        resolveToolApproval(false)
                    }
                }
            )
        ) {
            Button("拒绝", role: .cancel) {
                resolveToolApproval(false)
            }
            Button("允许") {
                resolveToolApproval(true)
            }
        } message: {
            Text(toolApprovalMessage)
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
        .fileExporter(
            isPresented: $isConversationExporterPresented,
            document: conversationExportDocument,
            contentType: ConversationMarkdownDocument.contentType,
            defaultFilename: conversationExportFileName,
            onCompletion: handleConversationExportResult
        )
        .onChange(of: showConfiguration) { _, isPresented in
            if !isPresented {
                reloadConfigurations()
                reloadAgentCapabilities()
            }
        }
        .onChange(of: showPromptSettings) { _, isPresented in
            if !isPresented {
                reloadConfigurations()
            }
        }
        .onChange(of: showAgentCapabilities) { _, isPresented in
            if !isPresented {
                reloadAgentCapabilities()
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
        .onChange(of: isHapticFeedbackEnabled) { _, isEnabled in
            if isEnabled {
                conversationActionHaptics.prepare()
            }

            if isEnabled, isGenerating {
                streamingOutputHaptics.prepareForStreaming()
            } else {
                streamingOutputHaptics.reset()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .inactive || newPhase == .background else {
                updateBackgroundRequestKeeper()
                return
            }
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
                .ignoresSafeArea(.container, edges: [.top, .bottom])

            temporaryChatNotice
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 34)
                .padding(.top, topScrollContentPadding)
                .padding(.bottom, bottomScrollContentPadding)
                .opacity(showsTemporaryChatNotice ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(!showsTemporaryChatNotice)
                .animation(.easeInOut(duration: 0.22), value: showsTemporaryChatNotice)

            topChrome(
                topSafeAreaInset: topSafeAreaInset,
                showsSidebarToggleExclusion: showsMainSidebarToggleFadeExclusion
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar(includesLegacyFade: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            chatScrollController.requestImmediateAutoScroll(animated: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            chatScrollController.requestImmediateAutoScroll(animated: false)
        }
        .overlay(alignment: .bottom) {
            ScrollToBottomButtonOverlay(
                scrollController: chatScrollController,
                bottomPadding: scrollToBottomButtonBottomPadding
            ) {
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
                            let revisionNavigationState = isGenerating ? nil : messageRevisionNavigationState(for: message.id)
                            let liveReasoningChannel = isStreamingMessage && activeAssistantReasoningIsExpanded
                                ? liveAssistantDisplay?.reasoningChannel
                                : nil
                            MessageBubble(
                                message: $message,
                                isStreaming: isStreamingMessage,
                                hasStreamingReasoning: isStreamingMessage && activeAssistantHasReasoning,
                                hasStreamingContent: isStreamingMessage && activeAssistantHasContent,
                                streamingContentChannel: isStreamingMessage ? liveAssistantDisplay?.contentChannel : nil,
                                streamingReasoningChannel: liveReasoningChannel,
                                markdownRenderCache: markdownRenderCache[message.id],
                                showsActions: activeMessageActionID == message.id,
                                revisionNavigationState: revisionNavigationState,
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
                                },
                                onSelectPreviousRevision: {
                                    selectMessageRevision(message.id, offset: -1)
                                },
                                onSelectNextRevision: {
                                    selectMessageRevision(message.id, offset: 1)
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
                    chatScrollController.requestImmediateAutoScroll(animated: false)
                }
                .onDisappear {
                    chatScrollController.clearScrollAction()
                }
            }
        }
    }

    private var temporaryChatNotice: some View {
        VStack(spacing: 12) {
            Text("临时聊天")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("在临时聊天中，聊天不会出现在历史记录中，但是在此对话进行过程中，你的上下文记录会被发送到模型提供商。")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360)
    }

    private func inputBar(includesLegacyFade: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !activeAgentCapsules.isEmpty {
                activeAgentCapsuleRow
                    .padding(.horizontal, 6)
            }

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
            .frame(maxWidth: .infinity)
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

            inputDisclaimer
        }
        .padding(.horizontal, inputBarHorizontalPadding)
        .padding(.top, inputBarTopPadding)
        .padding(.bottom, inputBarBottomPadding)
        .background(alignment: .bottom) {
            if includesLegacyFade {
                inputBottomFadeBackdrop
                    .ignoresSafeArea(.container, edges: .bottom)
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
                        triggerConversationActionHapticIfNeeded()
                        hideKeyboard()
                        handleTopConversationAction()
                    } label: {
                        topConversationActionLabel
                    }
                }
                .disabled(!canCreateConversation)
                .accessibilityLabel(topConversationActionAccessibilityLabel)
                .accessibilityHint(topConversationActionAccessibilityHint)
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
                .accessibilityLabel(showConversationSidebar
                    ? AppLocalizations.string("accessibility.closeConversationList", defaultValue: "Close conversation list")
                    : AppLocalizations.string("accessibility.openConversationList", defaultValue: "Open conversation list"))

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
        ChatInputComposer(
            inputDraft: inputDraft,
            isGenerating: isGenerating,
            isEditingMessage: isEditingMessage,
            isSpeechRecording: speechInputController.isRecording,
            hasPendingAttachments: hasPendingInputAttachments,
            inputGlassTint: inputGlassTint,
            controlGlassHighlight: controlGlassHighlight,
            onPasteImageProviders: pasteImageProvidersFromInputMenu,
            onExpandInput: presentExpandedInput,
            onToggleSpeechInput: toggleSpeechInput,
            onStopGenerating: {
                stopGenerating()
            },
            onSendMessage: {
                stopSpeechInputIfNeeded()
                sendMessage()
            },
            onCancelEditingMessage: cancelEditingMessage,
            onSaveEditingMessageOnly: {
                stopSpeechInputIfNeeded()
                saveEditingMessageOnly()
            },
            onSaveEditingMessageAndRegenerate: {
                stopSpeechInputIfNeeded()
                saveEditingMessageAndRegenerate()
            }
        ) {
            inputOptionsMenu
        }
    }

    private var inputDisclaimer: some View {
        Text("AI也有可能出错，输出仅供参考，请亲自核查重要信息。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
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

    private var activeAgentCapsules: [ActiveAgentCapsule] {
        let skillCapsules = activeSkills.map { skill in
            ActiveAgentCapsule(id: skill.id, kind: .skill, title: skill.displayName, icon: "wand.and.sparkles")
        }
        let mcpCapsules = activeMCPServers.map { server in
            ActiveAgentCapsule(id: server.id, kind: .mcp, title: server.name, icon: server.kind == .tavily ? "globe" : "point.3.connected.trianglepath.dotted")
        }
        return skillCapsules + mcpCapsules
    }

    private var activeAgentCapsuleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeAgentCapsules) { capsule in
                    ActiveAgentCapsuleView(capsule: capsule) {
                        deactivateAgentCapsule(capsule)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var modelChoiceMenuItems: some View {
        ForEach(currentConfiguration.models) { model in
            Button {
                selectModel(model.name)
            } label: {
                if model.name == currentConfiguration.selectedModel {
                    Label(model.displayName, systemImage: "checkmark")
                } else {
                    Text(model.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private var modelManagementMenuItem: some View {
        Button {
            hideKeyboard()
            showConfiguration = true
        } label: {
            Label("管理模型", systemImage: "slider.horizontal.3")
        }
    }

    @ViewBuilder
    private var modelSelectionMenuItems: some View {
        modelChoiceMenuItems
        Divider()
        modelManagementMenuItem
    }

    @ViewBuilder
    private var topModelSelectionMenuItems: some View {
        modelChoiceMenuItems
        Divider()
        Button {
            hideKeyboard()
            showPromptSettings = true
        } label: {
            Label("提示词设置", systemImage: "text.quote")
        }
        modelManagementMenuItem
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
        let title = currentConfiguration.selectedModelDisplayName

        return topGlassControl {
            Menu {
                topModelSelectionMenuItems
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: topModelButtonWidth - 38, alignment: .center)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: topModelButtonWidth, height: topControlSize)
                .contentShape(Capsule())
            }
        }
        .disabled(isGenerating)
        .accessibilityLabel(AppLocalizations.format(
            "accessibility.currentModel",
            defaultValue: "Current model: %@",
            arguments: [title]
        ))
    }

    private var inputOptionsMenu: some View {
        Menu {
            Button {
                isPhotoPickerPresented = true
            } label: {
                Label(
                    currentConfiguration.selectedModelSupportsImages
                        ? AppLocalizations.string("input.uploadImage", defaultValue: "Upload Image")
                        : AppLocalizations.string("input.imageUnsupported", defaultValue: "Current model does not support images"),
                    systemImage: "photo"
                )
            }
            .disabled(!currentConfiguration.selectedModelSupportsImages)

            Button {
                isFileImporterPresented = true
            } label: {
                Label("上传文件", systemImage: "doc")
            }

            Divider()

            Menu {
                if agentSkills.isEmpty {
                    Text("没有可用 Skill")
                } else {
                    ForEach(agentSkills) { skill in
                        Button {
                            toggleSkill(skill.id)
                        } label: {
                            if activeSkillIDs.contains(skill.id) {
                                Label(skill.displayName, systemImage: "checkmark")
                            } else {
                                Label(skill.displayName, systemImage: "wand.and.sparkles")
                            }
                        }
                    }
                }

                Button {
                    hideKeyboard()
                    showAgentCapabilities = true
                } label: {
                    Label("管理 Skills", systemImage: "slider.horizontal.3")
                }
            } label: {
                Label("Agent Skills", systemImage: "wand.and.sparkles")
            }

            Menu {
                if mcpServers.isEmpty {
                    Text("没有可用 MCP")
                } else {
                    ForEach(mcpServers) { server in
                        Button {
                            toggleMCPServer(server.id)
                        } label: {
                            if activeMCPServerIDs.contains(server.id) {
                                Label(server.name, systemImage: "checkmark")
                            } else {
                                Label(server.name, systemImage: server.kind == .tavily ? "globe" : "point.3.connected.trianglepath.dotted")
                            }
                        }
                    }
                }

                Button {
                    hideKeyboard()
                    showAgentCapabilities = true
                } label: {
                    Label("管理 MCP", systemImage: "slider.horizontal.3")
                }
            } label: {
                Label("MCP 工具", systemImage: "point.3.connected.trianglepath.dotted")
            }

            if currentConfiguration.selectedModelSupportsReasoning {
                Divider()

                Button {
                    setReasoningEnabled(false)
                } label: {
                    if currentConfiguration.reasoningEnabled {
                        Text(AppLocalizations.string("reasoning.menu.off", defaultValue: "Reasoning: Off"))
                    } else {
                        Label(AppLocalizations.string("reasoning.menu.off", defaultValue: "Reasoning: Off"), systemImage: "checkmark")
                    }
                }

                ForEach(ReasoningEffort.allCases) { effort in
                    Button {
                        selectReasoningEffort(effort)
                    } label: {
                        if currentConfiguration.reasoningEnabled,
                           effort == currentConfiguration.reasoningEffort {
                            Label(AppLocalizations.format(
                                "reasoning.menu.effort",
                                defaultValue: "Reasoning: %@",
                                arguments: [effort.title]
                            ), systemImage: "checkmark")
                        } else {
                            Text(AppLocalizations.format(
                                "reasoning.menu.effort",
                                defaultValue: "Reasoning: %@",
                                arguments: [effort.title]
                            ))
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
        .accessibilityLabel(AppLocalizations.string("accessibility.moreInputOptions", defaultValue: "More input options"))
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

    private var canCreateConversation: Bool {
        true
    }

    private var showsPrivateConversationAction: Bool {
        currentConversationIsBlank && !isPrivateConversationSelected
    }

    private var topConversationActionSystemImage: String {
        showsPrivateConversationAction ? "lock" : "square.and.pencil"
    }

    private var topConversationActionAccessibilityLabel: String {
        if showsTemporaryChatNotice {
            return AppLocalizations.string("accessibility.exitTemporaryChat", defaultValue: "Exit temporary chat")
        }

        return showsPrivateConversationAction
            ? AppLocalizations.string("accessibility.startPrivateConversation", defaultValue: "Start private conversation")
            : AppLocalizations.string("accessibility.newConversation", defaultValue: "New conversation")
    }

    private var topConversationActionAccessibilityHint: String {
        showsTemporaryChatNotice
            ? AppLocalizations.string("accessibility.temporaryChatHint", defaultValue: "Temporary chats are not saved locally")
            : ""
    }

    private var currentConversationIsBlank: Bool {
        messages.isEmpty
            && inputDraft.trimmedText.isEmpty
            && pendingImageAttachments.isEmpty
            && pendingFileAttachments.isEmpty
    }

    private var currentConfiguration: AIConfiguration {
        AIConfigurationStore.selectedConfiguration(
            from: configurations,
            selectedID: selectedConfigurationID
        )
    }

    private var activeSkills: [AgentSkill] {
        agentSkills.filter { activeSkillIDs.contains($0.id) }
    }

    private var activeMCPServers: [MCPServerConfiguration] {
        mcpServers.filter { activeMCPServerIDs.contains($0.id) }
    }

    private var toolApprovalMessage: String {
        guard let pendingToolApproval else { return "" }
        let arguments = pendingToolApproval.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !arguments.isEmpty else {
            return pendingToolApproval.toolName
        }
        return "\(pendingToolApproval.toolName)\n\n\(String(arguments.prefix(1_000)))"
    }

    private var configurationSummary: String {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelSummary = configuration.selectedModelDisplayName
        let hasAPIKey = !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCustomHeaders = !configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let authSummary = hasAPIKey
            ? "API Key"
            : (hasCustomHeaders
                ? AppLocalizations.string("configuration.summary.customHeaders", defaultValue: "Custom headers")
                : AppLocalizations.string("configuration.summary.noAuth", defaultValue: "No authentication configured"))

        let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointSummary = endpoint.isEmpty
            ? AppLocalizations.string("configuration.summary.noEndpoint", defaultValue: "No Endpoint configured")
            : endpoint
        let reasoningSummary = configuration.selectedModelSupportsReasoning
            ? (configuration.reasoningEnabled
                ? AppLocalizations.format(
                    "configuration.summary.reasoning",
                    defaultValue: "Reasoning %@",
                    arguments: [configuration.reasoningEffort.title]
                )
                : AppLocalizations.string("configuration.summary.reasoningOff", defaultValue: "Reasoning off"))
            : AppLocalizations.string("configuration.summary.noReasoning", defaultValue: "No reasoning")
        let imageSummary = configuration.selectedModelSupportsImages
            ? AppLocalizations.string("configuration.summary.images", defaultValue: "Images")
            : AppLocalizations.string("configuration.summary.textOnly", defaultValue: "Text")
        let apiSummary = configuration.apiFormat.title
        let anthropicSummary = configuration.apiFormat == .anthropicMessages
            ? " · max_tokens \(configuration.anthropicMaxTokens)"
            : ""
        let baseURLSummary = trimmedBaseURL.isEmpty
            ? AppLocalizations.string("configuration.summary.noBaseURL", defaultValue: "No Base URL configured")
            : trimmedBaseURL
        return "\(configuration.name) · \(apiSummary) · \(modelSummary) · \(imageSummary) · \(reasoningSummary)\(anthropicSummary) · \(baseURLSummary) · \(endpointSummary) · \(authSummary)"
    }

    private func reloadAgentCapabilities() {
        agentSkills = AgentCapabilityStore.loadSkills()
        mcpServers = AgentCapabilityStore.loadMCPServers()
        activeSkillIDs = activeSkillIDs.intersection(Set(agentSkills.map(\.id)))
        activeMCPServerIDs = activeMCPServerIDs.intersection(Set(mcpServers.map(\.id)))
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func toggleSkill(_ id: UUID) {
        if activeSkillIDs.contains(id) {
            activeSkillIDs.remove(id)
        } else {
            activeSkillIDs.insert(id)
        }
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func toggleMCPServer(_ id: UUID) {
        if activeMCPServerIDs.contains(id) {
            activeMCPServerIDs.remove(id)
        } else {
            activeMCPServerIDs.insert(id)
        }
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func deactivateAgentCapsule(_ capsule: ActiveAgentCapsule) {
        switch capsule.kind {
        case .skill:
            activeSkillIDs.remove(capsule.id)
        case .mcp:
            activeMCPServerIDs.remove(capsule.id)
        }
        persistCurrentConversation(refreshesUpdatedAt: false)
    }

    private func activeAgentToolDefinitions() -> [AgentToolDefinition] {
        var definitions = [AgentToolDefinition]()
        var usedFunctionNames = Set<String>()

        for server in activeMCPServers {
            for tool in effectiveMCPTools(for: server) {
                let definition = AgentToolDefinition.make(server: server, tool: tool)
                guard usedFunctionNames.insert(definition.functionName).inserted else { continue }
                definitions.append(definition)
            }
        }

        return definitions
    }

    private func effectiveMCPTools(for server: MCPServerConfiguration) -> [MCPToolDefinition] {
        var tools = server.cachedTools.map { tool in
            var normalizedTool = tool
            if server.kind == .tavily {
                normalizedTool.name = AgentCapabilityStore.normalizedTavilyToolName(tool.name)
            }
            return normalizedTool
        }
        if server.kind == .tavily {
            for defaultTool in MCPServerConfiguration.tavilyDefault().cachedTools
            where !tools.contains(where: { $0.name == defaultTool.name }) {
                tools.append(defaultTool)
            }
        }

        let allowedToolNames: [String]
        if server.kind == .tavily {
            let normalizedAllowedToolNames = server.allowedToolNames.map(AgentCapabilityStore.normalizedTavilyToolName)
            allowedToolNames = normalizedAllowedToolNames.isEmpty
                ? MCPServerConfiguration.tavilyDefault().allowedToolNames
                : normalizedAllowedToolNames
        } else {
            allowedToolNames = server.allowedToolNames
        }
        let allowedNames = Set(allowedToolNames)
        let filteredTools = tools.filter { allowedNames.isEmpty || allowedNames.contains($0.name) }

        if filteredTools.isEmpty && server.kind == .tavily {
            return MCPServerConfiguration.tavilyDefault().cachedTools
        }
        return filteredTools
    }

    private func executeAgentTool(_ request: AgentToolCallRequest) async -> AgentToolCallResult {
        if request.tool.requiresApproval {
            let isAllowed = await requestToolApproval(
                toolName: request.tool.displayName,
                arguments: request.argumentsJSON
            )
            guard isAllowed else {
                return AgentToolCallResult(
                    content: AppLocalizations.string(
                        "agentTool.result.userDenied",
                        defaultValue: "The user denied this tool call."
                    ),
                    isError: true
                )
            }
        }

        let server = currentMCPServerConfiguration(for: request.tool)
        let mcpToolName = server.kind == .tavily
            ? AgentCapabilityStore.normalizedTavilyToolName(request.tool.mcpToolName)
            : request.tool.mcpToolName

        do {
            let result = try await RemoteMCPClient(configuration: server).callTool(
                name: mcpToolName,
                arguments: jsonValue(from: request.argumentsJSON)
            )
            if result.isError,
               shouldRefreshTools(after: result.content),
               let retryResult = await retryAgentToolAfterRefreshingTools(
                request,
                server: server,
                failedToolName: mcpToolName
               ) {
                return retryResult
            }
            return AgentToolCallResult(content: result.content, isError: result.isError)
        } catch {
            return AgentToolCallResult(content: error.localizedDescription, isError: true)
        }
    }

    private func currentMCPServerConfiguration(for tool: AgentToolDefinition) -> MCPServerConfiguration {
        if var server = mcpServers.first(where: { $0.id == tool.mcpServerID }) {
            if server.authorizationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                server.authorizationToken = tool.authorizationToken
            }
            return server
        }

        return MCPServerConfiguration(
            id: tool.mcpServerID,
            name: tool.mcpServerName,
            serverURL: tool.mcpServerURL,
            kind: tool.mcpServerID == MCPServerConfiguration.tavilyID ? .tavily : .custom,
            requiresApproval: tool.requiresApproval,
            authorizationToken: tool.authorizationToken
        )
    }

    private func shouldRefreshTools(after errorContent: String) -> Bool {
        let lowercasedContent = errorContent.lowercased()
        return lowercasedContent.contains("unknown tool")
            || lowercasedContent.contains("tool not found")
            || lowercasedContent.contains("not found")
    }

    private func retryAgentToolAfterRefreshingTools(
        _ request: AgentToolCallRequest,
        server: MCPServerConfiguration,
        failedToolName: String
    ) async -> AgentToolCallResult? {
        do {
            let refreshedTools = try await RemoteMCPClient(configuration: server).listTools()
            guard !refreshedTools.isEmpty else { return nil }

            let normalizedTools = refreshedTools.map { tool in
                var normalizedTool = tool
                if server.kind == .tavily {
                    normalizedTool.name = AgentCapabilityStore.normalizedTavilyToolName(tool.name)
                }
                return normalizedTool
            }
            saveRefreshedTools(normalizedTools, for: server)

            guard let replacementTool = replacementToolName(
                for: failedToolName,
                in: normalizedTools,
                serverKind: server.kind
            ) else {
                return nil
            }

            let retryResult = try await RemoteMCPClient(configuration: server).callTool(
                name: replacementTool,
                arguments: jsonValue(from: request.argumentsJSON)
            )
            return AgentToolCallResult(content: retryResult.content, isError: retryResult.isError)
        } catch {
            return nil
        }
    }

    private func replacementToolName(
        for failedToolName: String,
        in tools: [MCPToolDefinition],
        serverKind: MCPServerKind
    ) -> String? {
        let normalizedFailedToolName = serverKind == .tavily
            ? AgentCapabilityStore.normalizedTavilyToolName(failedToolName)
            : failedToolName
        if tools.contains(where: { $0.name == normalizedFailedToolName }) {
            return normalizedFailedToolName
        }

        let underscoreName = normalizedFailedToolName.replacingOccurrences(of: "-", with: "_")
        if tools.contains(where: { $0.name == underscoreName }) {
            return underscoreName
        }

        if serverKind == .tavily,
           normalizedFailedToolName.contains("search"),
           tools.contains(where: { $0.name == MCPServerConfiguration.tavilySearchToolName }) {
            return MCPServerConfiguration.tavilySearchToolName
        }

        return nil
    }

    private func saveRefreshedTools(_ tools: [MCPToolDefinition], for server: MCPServerConfiguration) {
        guard let index = mcpServers.firstIndex(where: { $0.id == server.id }) else { return }

        mcpServers[index].cachedTools = tools
        if server.kind == .tavily {
            let toolNames = Set(tools.map(\.name))
            let normalizedAllowedToolNames = mcpServers[index].allowedToolNames
                .map(AgentCapabilityStore.normalizedTavilyToolName)
                .filter { toolNames.contains($0) }
            mcpServers[index].allowedToolNames = normalizedAllowedToolNames.isEmpty
                ? MCPServerConfiguration.tavilyDefault().allowedToolNames
                : normalizedAllowedToolNames
        }
        mcpServers[index].updatedAt = Date()
        AgentCapabilityStore.saveMCPServers(mcpServers)
    }

    @MainActor
    private func requestToolApproval(toolName: String, arguments: String) async -> Bool {
        await withCheckedContinuation { continuation in
            toolApprovalContinuation?.resume(returning: false)
            toolApprovalContinuation = continuation
            pendingToolApproval = PendingToolApproval(toolName: toolName, arguments: arguments)
        }
    }

    private func jsonValue(from json: String) -> JSONValue {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }

    @discardableResult
    func sendMessage() -> Bool {
        stopSpeechInputIfNeeded()
        let userText = inputDraft.trimmedText
        let imageAttachments = pendingImageAttachments
        let fileAttachments = pendingFileAttachments
        ensureCurrentConversation()
        return startStreamingResponse(
            userText: userText,
            imageAttachments: imageAttachments,
            fileAttachments: fileAttachments,
            contextMessages: messages,
            appendsUserMessage: true
        )
    }

    @discardableResult
    private func startStreamingResponse(
        userText: String,
        imageAttachments: [ChatImageAttachment],
        imageContextDescription: String = "",
        fileAttachments: [ChatFileAttachment],
        contextMessages: [ChatMessage],
        appendsUserMessage: Bool,
        existingUserMessageID: UUID? = nil
    ) -> Bool {
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiFormat = configuration.apiFormat
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelParameters = configuration.selectedModelConfiguration
        let anthropicMaxTokens = configuration.anthropicMaxTokens
        let anthropicClaudeCodeImpersonationEnabled = configuration.anthropicClaudeCodeImpersonationEnabled
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil
        let usesImageAttachments = configuration.selectedModelSupportsImages
        let usesAgentTools = !activeMCPServers.isEmpty
        let agentTools = usesAgentTools ? activeAgentToolDefinitions() : []
        let effectiveSystemPrompt = configuration.systemPrompt + AgentTooling.promptAppendix(for: activeSkills)
        let generatesImageContextDescriptions = configuration.generatesImageContextDescriptions
        let preservesReasoningContext = AIService.usesDeepSeekReasoningContext(
            apiFormat: apiFormat,
            baseURL: trimmedBaseURL,
            model: model
        )

        guard !userText.isEmpty || !imageAttachments.isEmpty || !fileAttachments.isEmpty else { return false }

        guard !usesAgentTools || configuration.apiFormat != .vertexAIExpress else {
            appendAssistantError(AppLocalizations.string(
                "chat.error.vertexMCPUnsupported",
                defaultValue: "Vertex Express does not support MCP tool calls. Disable MCP capsules or switch API type."
            ))
            return false
        }

        guard !usesAgentTools || configuration.selectedModelSupportsTools else {
            appendAssistantError(AppLocalizations.string(
                "chat.error.modelToolsUnsupported",
                defaultValue: "The current model is not marked as supporting tool calls. Enable Tools in model settings, or disable MCP capsules before sending."
            ))
            return false
        }

        guard !usesAgentTools || !agentTools.isEmpty else {
            appendAssistantError(AppLocalizations.string(
                "chat.error.noMCPTools",
                defaultValue: "The enabled MCP servers have no available tools. Refresh the tool list in settings or check allowed tool names."
            ))
            return false
        }

        guard imageAttachments.isEmpty
                || usesImageAttachments
                || !imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendAssistantError(AppLocalizations.string(
                "chat.error.imageWithoutDescription",
                defaultValue: "The current model does not support image input, and this image message does not have a usable hidden description yet. Switch to an image-capable multimodal model and try again."
            ))
            return false
        }

        guard usesImageAttachments || !containsImageWithoutContextDescription(in: contextMessages) else {
            appendAssistantError(AppLocalizations.string(
                "chat.error.contextImageWithoutDescription",
                defaultValue: "The current model does not support image input, and an image message in the context does not have a usable hidden description yet. Try again later, or switch to an image-capable multimodal model."
            ))
            return false
        }

        guard !trimmedBaseURL.isEmpty else {
            appendAssistantError(AppLocalizations.string("chat.error.configureBaseURL", defaultValue: "Configure Base URL first."))
            return false
        }

        guard !model.isEmpty else {
            appendAssistantError(AppLocalizations.string("chat.error.selectModel", defaultValue: "Select a model first."))
            return false
        }

        guard let selectedConversationID else { return false }

        guard activeConversationGenerations[selectedConversationID] == nil else {
            return false
        }

        guard activeConversationGenerations.count < maxActiveConversationGenerations else {
            appendAssistantError(AppLocalizations.format(
                "chat.error.tooManyActiveRequests",
                defaultValue: "%d conversations are already requesting. Wait for one to finish before sending.",
                arguments: [maxActiveConversationGenerations]
            ))
            return false
        }

        let requestService = AIService()
        requestService.resetConversation(
            with: contextMessages,
            systemPrompt: effectiveSystemPrompt,
            usesImageAttachments: usesImageAttachments,
            preservesReasoningContext: preservesReasoningContext
        )
        clearInputState()
        isGenerating = true
        prepareStreamingOutputHapticsIfNeeded()
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
        let generation = ActiveConversationGeneration(
            conversationID: selectedConversationID,
            assistantMessageID: assistantMessageID,
            service: requestService
        )
        activeConversationGenerations[selectedConversationID] = generation
        streamingTokenBuffer = generation.tokenBuffer
        activeAssistantMessageID = assistantMessageID
        liveAssistantDisplays[assistantMessageID] = AssistantLiveDisplay()
        updateBackgroundRequestKeeper()

        requestService.sendStreamingMessage(
            message: userText,
            imageAttachments: imageAttachments,
            imageContextDescription: imageContextDescription,
            fileAttachments: fileAttachments,
            baseURL: trimmedBaseURL,
            apiFormat: apiFormat,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort,
            usesImageAttachments: usesImageAttachments,
            agentTools: agentTools,
            toolExecutor: { request in
                await executeAgentTool(request)
            },
            onToolExchangesUpdated: { exchanges in
                updateToolExchanges(
                    exchanges,
                    for: assistantMessageID,
                    in: selectedConversationID
                )
            },
            isReasoningDisplayActive: {
                isReasoningDisplayActive(
                    for: assistantMessageID,
                    in: selectedConversationID
                )
            },
            onReasoningToken: { token in
                handleReasoningToken(
                    token,
                    for: assistantMessageID,
                    in: selectedConversationID
                )
            },
            onContentToken: { token in
                handleContentToken(
                    token,
                    for: assistantMessageID,
                    in: selectedConversationID
                )
            },
            onComplete: { contentText in
                completeStreamingResponse(
                    for: assistantMessageID,
                    in: selectedConversationID,
                    contentText: contentText,
                    configuration: configuration
                )
            },
            onError: { error in
                failStreamingResponse(
                    error,
                    for: assistantMessageID,
                    in: selectedConversationID
                )
            }
        )

        if usesImageAttachments,
           generatesImageContextDescriptions,
           !imageAttachments.isEmpty,
           imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let userMessageIDForImageContext {
            generateImageContextDescriptionIfNeeded(
                for: userMessageIDForImageContext,
                in: selectedConversationID,
                imageAttachments: imageAttachments,
                baseURL: trimmedBaseURL,
                apiFormat: apiFormat,
                apiKey: trimmedAPIKey,
                customHeaders: trimmedCustomHeaders,
                model: model,
                modelParameters: modelParameters,
                anthropicMaxTokens: anthropicMaxTokens,
                anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
                reasoningEnabled: reasoningEnabled,
                reasoningEffort: reasoningEffort
            )
        }

        return true
    }

    private func activeGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) -> ActiveConversationGeneration? {
        guard let generation = activeConversationGenerations[conversationID],
              generation.assistantMessageID == assistantMessageID else {
            return nil
        }
        return generation
    }

    private func isReasoningDisplayActive(
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) -> Bool {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else {
            return false
        }
        return selectedConversationID == conversationID && generation.reasoningIsExpanded
    }

    private func updateToolExchanges(
        _ exchanges: [ChatToolExchange],
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        if selectedConversationID == conversationID {
            guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
            messages[index].toolExchanges = exchanges
            persistCurrentConversation(refreshesUpdatedAt: false)
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex].messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].toolExchanges = exchanges
        updateActiveMessageRevisionSnapshots(
            in: conversationIndex,
            with: conversations[conversationIndex].messages
        )
        saveConversationsPreservingSelectedConversation()
    }

    private func handleReasoningToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else { return }

        generation.hasReasoning = true
        generation.tokenBuffer.appendReasoning(token)

        guard selectedConversationID == conversationID,
              activeAssistantMessageID == assistantMessageID else {
            return
        }

        if streamingTokenBuffer !== generation.tokenBuffer {
            streamingTokenBuffer = generation.tokenBuffer
        }
        activeAssistantHasReasoning = true
        updateLiveReasoningDisplayIfNeeded(for: assistantMessageID, token: token)
    }

    private func handleContentToken(
        _ token: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else { return }

        generation.hasContent = true
        generation.tokenBuffer.appendContent(token)

        if selectedConversationID == conversationID,
           activeAssistantMessageID == assistantMessageID {
            if streamingTokenBuffer !== generation.tokenBuffer {
                streamingTokenBuffer = generation.tokenBuffer
            }
            collapseReasoningAfterThinkingIfNeeded(for: assistantMessageID)
            appendLiveContentToken(token, for: assistantMessageID)
            activeAssistantHasContent = true
            scheduleStreamingAutoScroll()
        }

        scheduleTokenFlush(for: assistantMessageID, in: conversationID)
    }

    private func completeStreamingResponse(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        contentText: String,
        configuration: AIConfiguration
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        cancelScheduledFlush(for: conversationID)
        flushPendingTokens(
            for: assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: selectedConversationID == conversationID
        )
        synchronizeCompletedAssistantContent(
            contentText,
            for: assistantMessageID,
            in: conversationID
        )

        if selectedConversationID == conversationID {
            triggerOutputCompletionHapticIfNeeded()
            prepareMarkdownCache(for: assistantMessageID)
        }

        finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            marksStopped: false,
            triggersCompletionHaptic: false
        )
        persistConversation(conversationID, refreshesUpdatedAt: true)
        generateTitleIfNeeded(for: conversationID, configuration: configuration)
    }

    private func synchronizeCompletedAssistantContent(
        _ contentText: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard !contentText.isEmpty else { return }

        if selectedConversationID == conversationID {
            guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }),
                  messages[index].content != contentText else {
                return
            }
            messages[index].content = contentText
            invalidateMarkdownCache(for: assistantMessageID)
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex]
                .messages
                .firstIndex(where: { $0.id == assistantMessageID }),
              conversations[conversationIndex].messages[messageIndex].content != contentText else {
            return
        }

        conversations[conversationIndex].messages[messageIndex].content = contentText
        updateActiveMessageRevisionSnapshots(
            in: conversationIndex,
            with: conversations[conversationIndex].messages
        )
    }

    private func failStreamingResponse(
        _ error: String,
        for assistantMessageID: UUID,
        in conversationID: UUID
    ) {
        guard activeGeneration(for: assistantMessageID, in: conversationID) != nil else { return }

        cancelScheduledFlush(for: conversationID)
        flushPendingTokens(
            for: assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: false
        )

        let persistentError = persistentAssistantErrorMessage(from: error)
        updateAssistantMessage(
            assistantMessageID,
            in: conversationID,
            refreshesUpdatedAt: false
        ) { message in
            message.content = persistentError
        }

        if selectedConversationID == conversationID {
            publishLiveContentUpdate(for: assistantMessageID, chunks: [persistentError], resetsText: true)
            prepareMarkdownCache(for: assistantMessageID)
        }

        finishActiveGeneration(
            for: assistantMessageID,
            in: conversationID,
            marksStopped: false,
            triggersCompletionHaptic: false
        )
        persistConversation(conversationID, refreshesUpdatedAt: true)
    }

    private func finishActiveGeneration(
        for assistantMessageID: UUID,
        in conversationID: UUID,
        marksStopped: Bool,
        triggersCompletionHaptic: Bool
    ) {
        guard let generation = activeGeneration(for: assistantMessageID, in: conversationID) else { return }

        generation.cancelScheduledFlush()
        activeConversationGenerations[conversationID] = nil

        if marksStopped {
            updateAssistantMessage(
                assistantMessageID,
                in: conversationID,
                refreshesUpdatedAt: false
            ) { message in
                message.isStopped = true
            }
        }

        if selectedConversationID == conversationID {
            if triggersCompletionHaptic {
                triggerOutputCompletionHapticIfNeeded()
            }
            isGenerating = false
            activeAssistantMessageID = nil
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            isFlushScheduled = false
            flushTask = nil
            liveAssistantDisplays[assistantMessageID] = nil
            streamingOutputHaptics.reset()
            streamingTokenBuffer = StreamingTokenBuffer()
        }

        updateBackgroundRequestKeeper()
    }

    private func cancelActiveGeneration(
        in conversationID: UUID,
        marksStopped: Bool,
        triggersCompletionHaptic: Bool = false
    ) {
        guard let generation = activeConversationGenerations[conversationID] else { return }

        generation.service.cancelStreaming()
        cancelScheduledFlush(for: conversationID)
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: selectedConversationID == conversationID
        )
        finishActiveGeneration(
            for: generation.assistantMessageID,
            in: conversationID,
            marksStopped: marksStopped,
            triggersCompletionHaptic: triggersCompletionHaptic
        )
    }

    private func appendAssistantError(_ content: String) {
        let message = ChatMessage(role: "assistant", content: content)
        messages.append(message)
        prepareMarkdownCache(for: message.id, content: content)
        persistCurrentConversation()
    }

    private func persistentAssistantErrorMessage(from error: String) -> String {
        let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedError.isEmpty
            ? AppLocalizations.string("aiService.diagnostics.requestFailedFallback", defaultValue: "Request failed")
            : trimmedError
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
        apiFormat: AIAPIFormat,
        apiKey: String,
        customHeaders: String,
        model: String,
        modelParameters: AIModelConfiguration?,
        anthropicMaxTokens: Int,
        anthropicClaudeCodeImpersonationEnabled: Bool,
        reasoningEnabled: Bool?,
        reasoningEffort: ReasoningEffort?
    ) {
        aiService.generateImageContextDescription(
            imageAttachments: imageAttachments,
            baseURL: baseURL,
            apiFormat: apiFormat,
            apiKey: apiKey,
            customHeaders: customHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
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
            if saveImageContextDescriptionInMessageRevisions(
                trimmedDescription,
                for: messageID,
                in: conversationID,
                matching: imageAttachments
            ) {
                saveConversationsPreservingSelectedConversation()
            }
            return
        }

        conversations[conversationIndex].messages[messageIndex].imageContextDescription = trimmedDescription
        _ = saveImageContextDescriptionInMessageRevisions(
            trimmedDescription,
            for: messageID,
            in: conversationID,
            matching: imageAttachments
        )
        saveConversationsPreservingSelectedConversation()
    }

    private func saveImageContextDescriptionInMessageRevisions(
        _ description: String,
        for messageID: UUID,
        in conversationID: UUID,
        matching imageAttachments: [ChatImageAttachment]
    ) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return false
        }

        var didUpdate = false
        for groupIndex in conversations[conversationIndex].messageRevisionGroups.indices {
            for revisionIndex in conversations[conversationIndex].messageRevisionGroups[groupIndex].revisions.indices {
                guard let messageIndex = conversations[conversationIndex]
                    .messageRevisionGroups[groupIndex]
                    .revisions[revisionIndex]
                    .messages
                    .firstIndex(where: { $0.id == messageID && $0.imageAttachments == imageAttachments }) else {
                    continue
                }

                conversations[conversationIndex]
                    .messageRevisionGroups[groupIndex]
                    .revisions[revisionIndex]
                    .messages[messageIndex]
                    .imageContextDescription = description
                didUpdate = true
            }
        }

        return didUpdate
    }

    private func messageRevisionNavigationState(for messageID: UUID) -> MessageRevisionNavigationState? {
        guard let selectedConversationID,
              let conversation = conversations.first(where: { $0.id == selectedConversationID }),
              let group = conversation.messageRevisionGroups.first(where: { $0.id == messageID }),
              group.revisions.count > 1,
              let currentIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
            return nil
        }

        return MessageRevisionNavigationState(
            currentIndex: currentIndex,
            count: group.revisions.count
        )
    }

    private func createMessageRevision(
        for messageID: UUID,
        previousMessages: [ChatMessage],
        newMessages: [ChatMessage]
    ) {
        guard previousMessages != newMessages,
              previousMessages.contains(where: { $0.id == messageID && $0.role == "user" }),
              newMessages.contains(where: { $0.id == messageID && $0.role == "user" }),
              let selectedConversationID,
              let conversationIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return
        }

        updateActiveMessageRevisionSnapshots(in: conversationIndex, with: previousMessages)

        let newRevision = ChatMessageRevision(messages: newMessages)
        if let groupIndex = conversations[conversationIndex]
            .messageRevisionGroups
            .firstIndex(where: { $0.id == messageID }) {
            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .revisions
                .append(newRevision)
            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .selectedRevisionID = newRevision.id
        } else {
            let previousRevision = ChatMessageRevision(messages: previousMessages)
            let group = ChatMessageRevisionGroup(
                id: messageID,
                selectedRevisionID: newRevision.id,
                revisions: [previousRevision, newRevision]
            )
            conversations[conversationIndex].messageRevisionGroups.append(group)
        }
    }

    private func updateActiveMessageRevisionSnapshots(
        in conversationIndex: Int,
        with snapshotMessages: [ChatMessage]
    ) {
        guard conversations.indices.contains(conversationIndex) else { return }

        for groupIndex in conversations[conversationIndex].messageRevisionGroups.indices {
            let group = conversations[conversationIndex].messageRevisionGroups[groupIndex]
            guard snapshotMessages.contains(where: { $0.id == group.id && $0.role == "user" }),
                  let revisionIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
                continue
            }

            conversations[conversationIndex]
                .messageRevisionGroups[groupIndex]
                .revisions[revisionIndex]
                .messages = snapshotMessages
        }
    }

    private func selectMessageRevision(_ messageID: UUID, offset: Int) {
        didTapMessageBubble = true
        guard !isGenerating,
              offset != 0,
              let selectedConversationID,
              let conversationIndex = conversations.firstIndex(where: { $0.id == selectedConversationID }),
              let groupIndex = conversations[conversationIndex]
                .messageRevisionGroups
                .firstIndex(where: { $0.id == messageID }) else {
            return
        }

        updateActiveMessageRevisionSnapshots(in: conversationIndex, with: messages)

        let group = conversations[conversationIndex].messageRevisionGroups[groupIndex]
        guard let currentIndex = group.revisions.firstIndex(where: { $0.id == group.selectedRevisionID }) else {
            return
        }

        let nextIndex = currentIndex + offset
        guard group.revisions.indices.contains(nextIndex) else { return }

        let revision = group.revisions[nextIndex]
        conversations[conversationIndex].messageRevisionGroups[groupIndex].selectedRevisionID = revision.id
        restoreSelectedMessageRevision(revision.messages)
        persistCurrentConversation()
    }

    private func restoreSelectedMessageRevision(_ revisionMessages: [ChatMessage]) {
        speechInputController.cancelRecording()
        messages = revisionMessages
        resetMarkdownCache(for: messages)
        inputDraft.clearText()
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
        restoreChatScrollAfterConversationChange()
        aiService.resetConversation(
            with: messages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages
        )
    }

    private func clearInputState() {
        speechInputController.cancelRecording()
        inputDraft.clearAndResignFocus()
        pendingImageAttachments = []
        pendingFileAttachments = []
        selectedPhotoItems = []
        imageSelectionError = nil
        editingMessageID = nil
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
                inputDraft.requestFocus()
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
        inputDraft.setText(text)
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

    @discardableResult
    private func saveEditingMessageOnly() -> Bool {
        stopSpeechInputIfNeeded()
        guard let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return false
        }

        let previousMessages = messages
        let keepsImageContextDescription = messages[index].imageAttachments == pendingImageAttachments
        messages[index].content = inputDraft.trimmedText
        messages[index].imageAttachments = pendingImageAttachments
        if !keepsImageContextDescription {
            messages[index].imageContextDescription = ""
        }
        messages[index].fileAttachments = pendingFileAttachments
        createMessageRevision(
            for: editingMessageID,
            previousMessages: previousMessages,
            newMessages: messages
        )
        invalidateMarkdownCache(for: editingMessageID)
        persistCurrentConversation()
        removeUnreferencedConversationImages()
        clearInputState()
        return true
    }

    @discardableResult
    private func saveEditingMessageAndRegenerate() -> Bool {
        stopSpeechInputIfNeeded()
        guard !isGenerating,
              let editingMessageID,
              let index = messages.firstIndex(where: { $0.id == editingMessageID && $0.role == "user" }) else {
            clearInputState()
            return false
        }

        let editedText = inputDraft.trimmedText
        let editedImages = pendingImageAttachments
        let editedFiles = pendingFileAttachments
        let editedImageContextDescription = messages[index].imageAttachments == editedImages
            ? messages[index].imageContextDescription
            : ""
        let previousMessages = messages
        messages[index].content = editedText
        messages[index].imageAttachments = editedImages
        messages[index].imageContextDescription = editedImageContextDescription
        messages[index].fileAttachments = editedFiles
        messages.removeSubrange((index + 1)..<messages.count)
        createMessageRevision(
            for: editingMessageID,
            previousMessages: previousMessages,
            newMessages: messages
        )
        pruneMarkdownCache()
        let context = Array(messages.prefix(index))
        persistCurrentConversation()
        removeUnreferencedConversationImages()

        return startStreamingResponse(
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
        guard let selectedConversationID else { return }
        scheduleTokenFlush(for: messageID, in: selectedConversationID)
    }

    func scheduleTokenFlush(for messageID: UUID, in conversationID: UUID) {
        if selectedConversationID == conversationID {
            scheduleVisibleTokenFlush(for: messageID, in: conversationID)
        } else {
            scheduleBackgroundTokenFlush(for: messageID, in: conversationID)
        }
    }

    private func scheduleVisibleTokenFlush(for messageID: UUID, in conversationID: UUID) {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        flushTask?.cancel()

        flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            flushPendingTokens(
                for: messageID,
                in: conversationID,
                flushesReasoning: false,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }
    }

    private func scheduleBackgroundTokenFlush(for messageID: UUID, in conversationID: UUID) {
        guard let generation = activeGeneration(for: messageID, in: conversationID),
              !generation.isFlushScheduled else {
            return
        }

        generation.isFlushScheduled = true
        generation.flushTask?.cancel()
        generation.flushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            flushPendingTokens(
                for: messageID,
                in: conversationID,
                flushesReasoning: false,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }
    }

    func flushPendingTokens(
        for messageID: UUID,
        in conversationID: UUID,
        flushesReasoning: Bool = true,
        invalidatesMarkdownCache: Bool = true,
        requestsAutoScroll: Bool = true
    ) {
        guard let generation = activeGeneration(for: messageID, in: conversationID) else { return }

        if selectedConversationID == conversationID {
            generation.cancelScheduledFlush()
            if streamingTokenBuffer !== generation.tokenBuffer {
                streamingTokenBuffer = generation.tokenBuffer
            }
            flushPendingTokens(
                for: messageID,
                flushesReasoning: flushesReasoning,
                invalidatesMarkdownCache: invalidatesMarkdownCache,
                requestsAutoScroll: requestsAutoScroll
            )
            return
        }

        flushPendingTokensFromBackgroundGeneration(
            generation,
            flushesReasoning: flushesReasoning
        )
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

    private func cancelScheduledFlush(for conversationID: UUID) {
        if selectedConversationID == conversationID {
            cancelScheduledFlush()
        }
        activeConversationGenerations[conversationID]?.cancelScheduledFlush()
    }

    private func flushPendingTokensFromBackgroundGeneration(
        _ generation: ActiveConversationGeneration,
        flushesReasoning: Bool
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == generation.conversationID }),
              let messageIndex = conversations[conversationIndex]
                .messages
                .firstIndex(where: { $0.id == generation.assistantMessageID }) else {
            generation.tokenBuffer.clearPendingTokens()
            generation.cancelScheduledFlush()
            return
        }

        if flushesReasoning, generation.tokenBuffer.hasPendingReasoningText {
            conversations[conversationIndex]
                .messages[messageIndex]
                .reasoningChunks
                .append(contentsOf: generation.tokenBuffer.consumePendingReasoningChunks())
        }

        if generation.tokenBuffer.hasPendingContentText {
            conversations[conversationIndex]
                .messages[messageIndex]
                .content += generation.tokenBuffer.consumePendingContentText()
        }

        updateActiveMessageRevisionSnapshots(
            in: conversationIndex,
            with: conversations[conversationIndex].messages
        )
        generation.cancelScheduledFlush()
        saveConversationsPreservingSelectedConversation()
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
        if let selectedConversationID,
           let generation = activeGeneration(for: messageID, in: selectedConversationID) {
            generation.didCollapseReasoningAfterThinking = true
            generation.reasoningIsExpanded = false
        }

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
        if let selectedConversationID,
           let generation = activeGeneration(for: messageID, in: selectedConversationID) {
            generation.reasoningIsExpanded = isExpanded
        }
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

    private func resetLiveContentDisplay(for messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }

        publishLiveContentUpdate(
            for: messageID,
            chunks: message.content.isEmpty ? [] : [message.content],
            resetsText: true
        )
    }

    private func publishLiveContentUpdate(for messageID: UUID, chunks: [String], resetsText: Bool) {
        guard let contentChannel = liveAssistantDisplays[messageID]?.contentChannel else { return }

        contentChannel.publish(chunks: chunks, resetsText: resetsText)
        triggerStreamingOutputHapticIfNeeded(chunks: chunks, resetsText: resetsText)
    }

    private func triggerStreamingOutputHapticIfNeeded(chunks: [String], resetsText: Bool) {
        guard isHapticFeedbackEnabled,
              !resetsText,
              chunks.contains(where: { !$0.isEmpty }) else { return }

        streamingOutputHaptics.impactForOutputRefresh()
    }

    private func prepareStreamingOutputHapticsIfNeeded() {
        guard isHapticFeedbackEnabled else {
            streamingOutputHaptics.reset()
            return
        }

        streamingOutputHaptics.prepareForStreaming()
    }

    private func triggerOutputCompletionHapticIfNeeded() {
        guard isHapticFeedbackEnabled else { return }
        streamingOutputHaptics.impactForOutputCompletion()
    }

    private func triggerConversationActionHapticIfNeeded() {
        guard isHapticFeedbackEnabled else { return }
        conversationActionHaptics.impact()
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
        guard let selectedConversationID,
              let generation = activeConversationGenerations[selectedConversationID] else {
            detachVisibleGenerationState()
            return
        }

        generation.service.cancelStreaming()
        cancelScheduledFlush(for: selectedConversationID)
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: selectedConversationID,
            invalidatesMarkdownCache: true,
            requestsAutoScroll: true
        )
        prepareMarkdownCache(for: generation.assistantMessageID)
        finishActiveGeneration(
            for: generation.assistantMessageID,
            in: selectedConversationID,
            marksStopped: true,
            triggersCompletionHaptic: triggersCompletionHaptic
        )
        persistConversation(selectedConversationID, refreshesUpdatedAt: true)
    }

    func hideKeyboard() {
        inputDraft.isFocused = false
        KeyboardDismissal.dismissNowAndDeferred()
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        guard currentConfiguration.selectedModelSupportsImages else {
            selectedPhotoItems = []
            imageSelectionError = AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            )
            return
        }

        imageSelectionError = nil

        let storesImagesLocally = !isPrivateConversationSelected
        Task {
            var attachments = [ChatImageAttachment]()

            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let attachment = imageAttachment(from: data, storesLocally: storesImagesLocally) else {
                    continue
                }

                attachments.append(attachment)
            }

            if attachments.isEmpty, !items.isEmpty {
                imageSelectionError = AppLocalizations.string(
                    "attachment.image.photoPickerReadFailed",
                    defaultValue: "Failed to read images. Please select them again."
                )
            } else {
                setPendingImageAttachments(attachments)
                imageSelectionError = nil
            }
        }
    }

    private func imageAttachment(from data: Data, storesLocally: Bool) -> ChatImageAttachment? {
        guard imageDataIsWithinLimits(data) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        return imageAttachment(from: image, storesLocally: storesLocally)
    }

    private func imageAttachment(fromImageFileAt url: URL, storesLocally: Bool) -> ChatImageAttachment? {
        guard imageFileIsWithinLimits(url),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return imageAttachment(from: data, storesLocally: storesLocally)
    }

    private func imageAttachment(from image: UIImage, storesLocally: Bool) -> ChatImageAttachment? {
        guard imagePixelCount(image) <= maxImagePixelCount else { return nil }
        let scaledImage = image.scaledDown(maxDimension: 1600)
        guard let jpegData = scaledImage.jpegData(compressionQuality: 0.78) else { return nil }
        if storesLocally {
            return ConversationImageStore.storeJPEGData(jpegData)
        }

        var attachment = ChatImageAttachment(
            dataURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        )
        attachment.byteCount = jpegData.count
        return attachment
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
            imageSelectionError = AppLocalizations.format(
                "attachment.image.limitTrimmed",
                defaultValue: "You can add up to %d images. The first %d were kept.",
                arguments: [maxImageAttachmentCount, maxImageAttachmentCount]
            )
        }
    }

    private func appendPendingImageAttachments(_ attachments: [ChatImageAttachment], source: String) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            )
            return
        }

        guard !attachments.isEmpty else {
            imageSelectionError = AppLocalizations.format(
                "attachment.image.readFailed",
                defaultValue: "Failed to read images from %@.",
                arguments: [source]
            )
            return
        }

        let remainingCount = maxImageAttachmentCount - pendingImageAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = AppLocalizations.format(
                "attachment.image.limit",
                defaultValue: "You can add up to %d images.",
                arguments: [maxImageAttachmentCount]
            )
            return
        }

        pendingImageAttachments.append(contentsOf: attachments.prefix(remainingCount))
        imageSelectionError = attachments.count > remainingCount
            ? AppLocalizations.format(
                "attachment.image.limitTrimmed",
                defaultValue: "You can add up to %d images. The first %d were kept.",
                arguments: [maxImageAttachmentCount, maxImageAttachmentCount]
            )
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
            imageSelectionError = AppLocalizations.string(
                "attachment.image.droppedUnsupported",
                defaultValue: "The current model does not support image input. Images were ignored."
            )
            return false
        }

        imageSelectionError = nil

        let storesImagesLocally = !isPrivateConversationSelected
        Task {
            var attachments = [ChatImageAttachment]()

            for provider in imageProviders.prefix(maxImageAttachmentCount) {
                guard let attachment = await imageAttachment(
                    from: provider,
                    storesLocally: storesImagesLocally
                ) else {
                    continue
                }

                attachments.append(attachment)
            }

            appendPendingImageAttachments(
                attachments,
                source: AppLocalizations.string("attachment.source.drag", defaultValue: "drag and drop")
            )
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

                appendPendingFileAttachments(
                    attachments,
                    source: AppLocalizations.string("attachment.source.selection", defaultValue: "selection"),
                    fallbackError: firstError
                )
            }
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            imageSelectionError = AppLocalizations.format(
                "attachment.file.selectionFailed",
                defaultValue: "File selection failed: %@",
                arguments: [error.localizedDescription]
            )
        }
    }

    private func appendPendingFileAttachments(
        _ attachments: [ChatFileAttachment],
        source: String,
        fallbackError: String? = nil
    ) {
        guard !attachments.isEmpty else {
            imageSelectionError = fallbackError ?? AppLocalizations.format(
                "attachment.file.readFailed",
                defaultValue: "Failed to read files from %@.",
                arguments: [source]
            )
            return
        }

        let remainingCount = maxFileAttachmentCount - pendingFileAttachments.count
        guard remainingCount > 0 else {
            imageSelectionError = AppLocalizations.format(
                "attachment.file.limit",
                defaultValue: "You can add up to %d files.",
                arguments: [maxFileAttachmentCount]
            )
            return
        }

        pendingFileAttachments.append(contentsOf: attachments.prefix(remainingCount))

        if attachments.count > remainingCount {
            imageSelectionError = AppLocalizations.format(
                "attachment.file.limitTrimmed",
                defaultValue: "You can add up to %d files. The first %d were kept.",
                arguments: [maxFileAttachmentCount, maxFileAttachmentCount]
            )
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

            appendPendingFileAttachments(
                attachments,
                source: AppLocalizations.string("attachment.source.drag", defaultValue: "drag and drop")
            )
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

    private func imageAttachment(
        from provider: NSItemProvider,
        storesLocally: Bool
    ) async -> ChatImageAttachment? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where: { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                guard let url,
                      let attachment = imageAttachment(
                        fromImageFileAt: url,
                        storesLocally: storesLocally
                      ) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: attachment)
            }
        }
    }

    private func pasteImageProvidersFromInputMenu(_ providers: [NSItemProvider]) {
        guard currentConfiguration.selectedModelSupportsImages else {
            imageSelectionError = AppLocalizations.string(
                "attachment.image.unsupported",
                defaultValue: "The current model does not support image input."
            )
            return
        }

        let imageProviders = providers.filter(providerContainsImage)
        guard !imageProviders.isEmpty else {
            imageSelectionError = AppLocalizations.string(
                "attachment.image.clipboardEmpty",
                defaultValue: "There are no pasteable images on the clipboard."
            )
            return
        }

        let storesImagesLocally = !isPrivateConversationSelected
        Task {
            var attachments = [ChatImageAttachment]()
            for provider in imageProviders.prefix(maxImageAttachmentCount) {
                guard let attachment = await imageAttachment(
                    from: provider,
                    storesLocally: storesImagesLocally
                ) else { continue }
                attachments.append(attachment)
            }

            appendPendingImageAttachments(
                attachments,
                source: AppLocalizations.string("attachment.source.clipboard", defaultValue: "clipboard")
            )
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

    @discardableResult
    private func selectBuiltInDefaultPromptForCurrentConfiguration() -> AIConfiguration {
        if configurations.isEmpty {
            let configuration = AIConfiguration()
            configurations = [configuration]
            selectedConfigurationID = configuration.id
        }

        guard let index = configurations.firstIndex(where: { $0.id == currentConfiguration.id }) ?? configurations.indices.first else {
            return currentConfiguration
        }

        var promptPresets = AIConfigurationStore.loadPromptPresets(configurations: configurations)
        let defaultPromptPreset = AIConfigurationStore.builtInDefaultPromptPreset(in: &promptPresets)
        configurations[index].selectPromptPreset(defaultPromptPreset.id, from: promptPresets)
        configurations[index].updatedAt = Date()
        selectedConfigurationID = configurations[index].id
        AIConfigurationStore.saveSelectedConfigurationID(configurations[index].id)
        AIConfigurationStore.savePromptPresets(promptPresets)
        AIConfigurationStore.saveConfigurations(configurations)
        return configurations[index]
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
            activeSkillIDs = Set(conversation.activeSkillIDs)
            activeMCPServerIDs = Set(conversation.activeMCPServerIDs)
            resetMarkdownCache(for: messages)
            activeAssistantHasReasoning = false
            activeAssistantHasContent = false
            activeAssistantReasoningIsExpanded = false
            activeAssistantDidCollapseReasoningAfterThinking = false
            liveAssistantDisplays = [:]
            restoreChatScrollAfterConversationChange()
            aiService.resetConversation(
                with: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            saveSelectedConversationIDIfStored(conversation.id)
            saveStoredConversations()
        }
    }

    private func ensureCurrentConversation() {
        if selectedConversationID == nil || !conversations.contains(where: { $0.id == selectedConversationID }) {
            let conversation = AIConversation()
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
            activeSkillIDs = []
            activeMCPServerIDs = []
            saveSelectedConversationIDIfStored(conversation.id)
            saveStoredConversations()
        }
    }

    private func selectConversation(_ id: UUID) {
        selectConversation(id, closesSidebar: true)
    }

    private func selectConversation(_ id: UUID, closesSidebar: Bool) {
        guard id != privateConversationID,
              let conversation = conversations.first(where: { $0.id == id }) else {
            return
        }

        if isPrivateConversationSelected {
            discardPrivateConversation()
        } else {
            prepareCurrentConversationForNavigation()
        }

        restoreConversation(conversation, closesSidebar: closesSidebar)
    }

    private func prepareCurrentConversationForNavigation() {
        if let selectedConversationID,
           let generation = activeConversationGenerations[selectedConversationID] {
            cancelScheduledFlush(for: selectedConversationID)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: selectedConversationID,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
            persistConversation(selectedConversationID, refreshesUpdatedAt: false)
        } else {
            persistCurrentConversation(refreshesUpdatedAt: false)
        }

        detachVisibleGenerationState()
    }

    private func discardPrivateConversation() {
        guard let privateConversationID else { return }

        if let generation = activeConversationGenerations[privateConversationID] {
            generation.service.cancelStreaming()
        }
        cancelScheduledFlush(for: privateConversationID)
        activeConversationGenerations[privateConversationID] = nil

        let wasSelected = selectedConversationID == privateConversationID
        conversations.removeAll { $0.id == privateConversationID }
        self.privateConversationID = nil

        if wasSelected {
            speechInputController.cancelRecording()
            selectedConversationID = nil
            messages = []
            activeSkillIDs = []
            activeMCPServerIDs = []
            resetMarkdownCache(for: messages)
            inputDraft.clearText()
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
            isGenerating = false
            restoreChatScrollAfterConversationChange()
            aiService.resetConversation(
                with: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            ConversationStore.clearSelectedConversationID()
        }

        updateBackgroundRequestKeeper()
        removeUnreferencedConversationImages()
    }

    private func detachVisibleGenerationState() {
        activeAssistantMessageID = nil
        liveAssistantDisplays = [:]
        activeAssistantHasReasoning = false
        activeAssistantHasContent = false
        activeAssistantReasoningIsExpanded = false
        activeAssistantDidCollapseReasoningAfterThinking = false
        isGenerating = false
        streamingOutputHaptics.reset()
        streamingTokenBuffer = StreamingTokenBuffer()
        isFlushScheduled = false
        flushTask = nil
    }

    private func attachVisibleGenerationStateIfNeeded(for conversationID: UUID) {
        guard let generation = activeConversationGenerations[conversationID] else {
            isGenerating = false
            activeAssistantMessageID = nil
            return
        }

        isGenerating = true
        activeAssistantMessageID = generation.assistantMessageID
        streamingTokenBuffer = generation.tokenBuffer
        activeAssistantHasReasoning = generation.hasReasoning
        activeAssistantHasContent = generation.hasContent
        activeAssistantReasoningIsExpanded = generation.reasoningIsExpanded
        activeAssistantDidCollapseReasoningAfterThinking = generation.didCollapseReasoningAfterThinking
        liveAssistantDisplays[generation.assistantMessageID] = AssistantLiveDisplay()
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: conversationID,
            invalidatesMarkdownCache: false,
            requestsAutoScroll: false
        )
        resetLiveContentDisplay(for: generation.assistantMessageID)
        if generation.reasoningIsExpanded {
            publishLiveReasoningReset(for: generation.assistantMessageID, appendsProgressively: true)
        }
        prepareStreamingOutputHapticsIfNeeded()
    }

    private func restoreConversation(_ conversation: AIConversation, closesSidebar: Bool) {
        speechInputController.cancelRecording()
        selectedConversationID = conversation.id
        messages = conversation.messages
        activeSkillIDs = Set(conversation.activeSkillIDs)
        activeMCPServerIDs = Set(conversation.activeMCPServerIDs)
        resetMarkdownCache(for: messages)
        inputDraft.clearText()
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
        restoreChatScrollAfterConversationChange()
        aiService.resetConversation(
            with: messages,
            systemPrompt: currentConfiguration.systemPrompt,
            usesImageAttachments: currentConfiguration.selectedModelSupportsImages
        )
        attachVisibleGenerationStateIfNeeded(for: conversation.id)
        saveSelectedConversationIDIfStored(conversation.id)

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func openConfigurationFromSidebar(closesSidebar: Bool) {
        hideKeyboard()
        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
        showConfiguration = true
    }

    private func handleTopConversationAction() {
        if showsTemporaryChatNotice {
            exitTemporaryConversation()
        } else if showsPrivateConversationAction {
            startPrivateConversation(closesSidebar: true)
        } else {
            createConversation()
        }
    }

    private func createConversation() {
        createConversation(closesSidebar: true)
    }

    private func startPrivateConversation(closesSidebar: Bool) {
        guard canCreateConversation,
              currentConversationIsBlank,
              !isPrivateConversationSelected else {
            createConversation(closesSidebar: closesSidebar)
            return
        }

        let defaultPromptConfiguration = selectBuiltInDefaultPromptForCurrentConfiguration()
        discardPrivateConversation()
        prepareCurrentConversationForNavigation()

        let conversation = AIConversation()
        privateConversationID = conversation.id
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        messages = []
        activeSkillIDs = []
        activeMCPServerIDs = []
        resetMarkdownCache(for: messages)
        speechInputController.cancelRecording()
        inputDraft.clearText()
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
        isGenerating = false
        restoreChatScrollAfterConversationChange()
        aiService.resetConversation(
            with: [],
            systemPrompt: defaultPromptConfiguration.systemPrompt,
            usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages
        )
        ConversationStore.clearSelectedConversationID()

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func exitTemporaryConversation() {
        guard showsTemporaryChatNotice else { return }

        discardPrivateConversation()

        if let emptyConversation = storedConversations.first(where: { !$0.hasInformation }) {
            restoreConversation(emptyConversation, closesSidebar: false)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        restoreConversation(conversation, closesSidebar: false)
        saveStoredConversations()
    }

    private func createConversation(closesSidebar: Bool) {
        guard canCreateConversation else {
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        let defaultPromptConfiguration = selectBuiltInDefaultPromptForCurrentConfiguration()

        let wasPrivateConversationSelected = isPrivateConversationSelected
        if wasPrivateConversationSelected {
            discardPrivateConversation()
        } else {
            prepareCurrentConversationForNavigation()
        }

        if !wasPrivateConversationSelected, currentConversationIsBlank {
            aiService.resetConversation(
                with: [],
                systemPrompt: defaultPromptConfiguration.systemPrompt,
                usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages
            )
            if closesSidebar {
                setConversationSidebarVisibility(false)
            }
            return
        }

        if let emptyConversation = storedConversations.first(where: { conversation in
            conversation.id != selectedConversationID && !conversation.hasInformation
        }) {
            selectConversation(emptyConversation.id, closesSidebar: closesSidebar)
            return
        }

        let conversation = AIConversation()
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
        messages = []
        activeSkillIDs = []
        activeMCPServerIDs = []
        resetMarkdownCache(for: messages)
        speechInputController.cancelRecording()
        inputDraft.clearText()
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
        isGenerating = false
        restoreChatScrollAfterConversationChange()
        aiService.resetConversation(
            with: [],
            systemPrompt: defaultPromptConfiguration.systemPrompt,
            usesImageAttachments: defaultPromptConfiguration.selectedModelSupportsImages
        )
        saveSelectedConversationIDIfStored(conversation.id)
        saveStoredConversations()

        if closesSidebar {
            setConversationSidebarVisibility(false)
        }
    }

    private func beginRenamingConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        hideKeyboard()
        renamingConversationID = id
        renamingConversationTitle = conversation.title
        isRenameConversationAlertPresented = true
    }

    private func commitRenamingConversation() {
        guard let renamingConversationID else {
            resetRenamingConversationState()
            return
        }

        renameConversation(id: renamingConversationID, title: renamingConversationTitle)
        resetRenamingConversationState()
    }

    private func resetRenamingConversationState() {
        renamingConversationID = nil
        renamingConversationTitle = ""
    }

    private func renameConversation(id: UUID, title: String) {
        persistCurrentConversation(refreshesUpdatedAt: false)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        conversations[index].title = normalizedManualConversationTitle(title)
        conversations[index].hasGeneratedTitle = true
        saveStoredConversations()
    }

    private func normalizedManualConversationTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty
            ? AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
            : trimmedTitle
    }

    private func toggleConversationPin(_ id: UUID) {
        persistCurrentConversation(refreshesUpdatedAt: false)
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        conversations[index].isPinned.toggle()
        saveStoredConversations()
    }

    private func beginExportingConversation(_ id: UUID) {
        hideKeyboard()

        if let generation = activeConversationGenerations[id] {
            cancelScheduledFlush(for: id)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: id,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
        }

        persistConversation(id, refreshesUpdatedAt: false)

        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        conversationExportDocument = ConversationMarkdownDocument(
            text: ConversationMarkdownExporter.markdown(for: conversation)
        )
        conversationExportFileName = ConversationMarkdownExporter.defaultFileName(for: conversation)
        isConversationExporterPresented = true
    }

    private func handleConversationExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            conversationExportErrorMessage = nil
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }
            conversationExportErrorMessage = AppLocalizations.format(
                "markdown.exportFailed",
                defaultValue: "Unable to export Markdown file: %@",
                arguments: [error.localizedDescription]
            )
        }
    }

    private func deleteConversation(_ id: UUID) {
        if conversations.count <= 1 {
            cancelActiveGeneration(in: id, marksStopped: false)

            let conversation = AIConversation()
            conversations = [conversation]
            selectedConversationID = conversation.id
            messages = []
            activeSkillIDs = []
            activeMCPServerIDs = []
            resetMarkdownCache(for: messages)
            speechInputController.cancelRecording()
            inputDraft.clearText()
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
            isGenerating = false
            restoreChatScrollAfterConversationChange()
            setConversationSidebarVisibility(false)
            aiService.resetConversation(
                with: [],
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            saveSelectedConversationIDIfStored(conversation.id)
            saveStoredConversations()
            removeUnreferencedConversationImages()
            return
        }

        cancelActiveGeneration(in: id, marksStopped: false)

        conversations.removeAll { $0.id == id }

        if selectedConversationID == id || selectedConversationID == nil {
            let nextConversation = conversations[0]
            selectedConversationID = nextConversation.id
            messages = nextConversation.messages
            activeSkillIDs = Set(nextConversation.activeSkillIDs)
            activeMCPServerIDs = Set(nextConversation.activeMCPServerIDs)
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
            restoreChatScrollAfterConversationChange()
            aiService.resetConversation(
                with: messages,
                systemPrompt: currentConfiguration.systemPrompt,
                usesImageAttachments: currentConfiguration.selectedModelSupportsImages
            )
            attachVisibleGenerationStateIfNeeded(for: nextConversation.id)
            saveSelectedConversationIDIfStored(nextConversation.id)
        }

        saveStoredConversations()
        removeUnreferencedConversationImages()
    }

    private func persistApplicationStateForLifecycle() {
        let activeConversationIDs = Array(activeConversationGenerations.keys)
        for conversationID in activeConversationIDs {
            guard let generation = activeConversationGenerations[conversationID] else { continue }
            cancelScheduledFlush(for: conversationID)
            flushPendingTokens(
                for: generation.assistantMessageID,
                in: conversationID,
                invalidatesMarkdownCache: false,
                requestsAutoScroll: false
            )
            persistConversation(
                conversationID,
                refreshesUpdatedAt: true
            )
        }

        if let selectedConversationID,
           !activeConversationIDs.contains(selectedConversationID) {
            persistCurrentConversation(synchronize: true, refreshesUpdatedAt: false)
        } else {
            saveStoredConversations(synchronize: true)
        }

        updateBackgroundRequestKeeper()
    }

    private func updateAssistantMessage(
        _ messageID: UUID,
        in conversationID: UUID,
        refreshesUpdatedAt: Bool,
        update: (inout ChatMessage) -> Void
    ) {
        if selectedConversationID == conversationID {
            guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            update(&messages[index])
            persistCurrentConversation(refreshesUpdatedAt: refreshesUpdatedAt)
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
              let messageIndex = conversations[conversationIndex]
                .messages
                .firstIndex(where: { $0.id == messageID }) else {
            return
        }

        update(&conversations[conversationIndex].messages[messageIndex])
        updateActiveMessageRevisionSnapshots(
            in: conversationIndex,
            with: conversations[conversationIndex].messages
        )
        if refreshesUpdatedAt {
            conversations[conversationIndex].updatedAt = Date()
        }
        saveConversationsPreservingSelectedConversation()
    }

    private func persistConversation(
        _ conversationID: UUID,
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        if selectedConversationID == conversationID {
            persistCurrentConversation(
                synchronize: synchronize,
                refreshesUpdatedAt: refreshesUpdatedAt
            )
            return
        }

        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        updateActiveMessageRevisionSnapshots(
            in: conversationIndex,
            with: conversations[conversationIndex].messages
        )
        if refreshesUpdatedAt {
            conversations[conversationIndex].updatedAt = Date()
        }
        saveConversationsPreservingSelectedConversation(synchronize: synchronize)
    }

    private func updateBackgroundRequestKeeper() {
        backgroundRequestKeeper.update(
            activeRequestCount: activeConversationGenerations.count,
            isSceneBackgrounded: scenePhase == .inactive || scenePhase == .background
        ) {
            persistApplicationStateForLifecycle()
        }
    }

    @discardableResult
    private func saveStoredConversations(synchronize: Bool = false) -> Bool {
        let conversationsForStorage = storedConversations
        guard !conversationsForStorage.isEmpty else { return false }
        return ConversationStore.saveConversations(conversationsForStorage, synchronize: synchronize)
    }

    private func saveSelectedConversationIDIfStored(_ id: UUID) {
        guard privateConversationID != id,
              storedConversations.contains(where: { $0.id == id }) else {
            ConversationStore.clearSelectedConversationID()
            return
        }

        ConversationStore.saveSelectedConversationID(id)
    }

    @discardableResult
    private func saveConversationsPreservingSelectedConversation(synchronize: Bool = false) -> Bool {
        flushSelectedGenerationForStorage()
        synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: false)
        return saveStoredConversations(synchronize: synchronize)
    }

    private func flushSelectedGenerationForStorage() {
        guard let selectedConversationID,
              let generation = activeConversationGenerations[selectedConversationID] else {
            return
        }

        cancelScheduledFlush(for: selectedConversationID)
        flushPendingTokens(
            for: generation.assistantMessageID,
            in: selectedConversationID,
            invalidatesMarkdownCache: false,
            requestsAutoScroll: false
        )
    }

    @discardableResult
    private func synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: Bool) -> Bool {
        guard let selectedConversationID,
              let index = conversations.firstIndex(where: { $0.id == selectedConversationID }) else {
            return false
        }

        conversations[index].messages = messages
        conversations[index].activeSkillIDs = Array(activeSkillIDs)
        conversations[index].activeMCPServerIDs = Array(activeMCPServerIDs)
        updateActiveMessageRevisionSnapshots(in: index, with: messages)
        if refreshesUpdatedAt {
            conversations[index].updatedAt = Date()
        }
        return true
    }

    private func persistCurrentConversation(
        synchronize: Bool = false,
        refreshesUpdatedAt: Bool = true
    ) {
        guard synchronizeSelectedConversationSnapshot(refreshesUpdatedAt: refreshesUpdatedAt) else {
            return
        }
        saveStoredConversations(synchronize: synchronize)
    }

    private func removeUnreferencedConversationImages() {
        var retainedConversations = storedConversations
        if let selectedConversationID,
           selectedConversationID != privateConversationID,
           let index = retainedConversations.firstIndex(where: { $0.id == selectedConversationID }) {
            retainedConversations[index].messages = messages
        }
        let retainedPendingImageAttachments = isPrivateConversationSelected ? [] : pendingImageAttachments
        ConversationImageStore.removeUnreferencedImages(
            retainedBy: retainedConversations,
            additionalAttachments: retainedPendingImageAttachments
        )
    }

    private func generateTitleIfNeeded() {
        guard let selectedConversationID else { return }
        generateTitleIfNeeded(for: selectedConversationID, configuration: currentConfiguration)
    }

    private func generateTitleIfNeeded(for conversationID: UUID, configuration: AIConfiguration) {
        guard conversationID != privateConversationID else { return }

        if selectedConversationID == conversationID {
            persistCurrentConversation(refreshesUpdatedAt: false)
        }

        guard let index = conversations.firstIndex(where: { $0.id == conversationID }),
              !conversations[index].hasGeneratedTitle,
              conversations[index].messages.contains(where: { $0.role == "assistant" && !$0.content.isEmpty }) else {
            return
        }

        let titleMessages = conversations[index].messages
        let configuration = currentConfiguration
        let trimmedBaseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiFormat = configuration.apiFormat
        let trimmedAPIKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomHeaders = configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelParameters = configuration.selectedModelConfiguration
        let anthropicMaxTokens = configuration.anthropicMaxTokens
        let anthropicClaudeCodeImpersonationEnabled = configuration.anthropicClaudeCodeImpersonationEnabled
        let reasoningEnabled = configuration.selectedModelSupportsReasoning ? configuration.reasoningEnabled : nil
        let reasoningEffort = reasoningEnabled == true ? configuration.reasoningEffort : nil

        guard !model.isEmpty else { return }

        AIService().generateConversationTitle(
            messages: titleMessages,
            baseURL: trimmedBaseURL,
            apiFormat: apiFormat,
            apiKey: trimmedAPIKey,
            customHeaders: trimmedCustomHeaders,
            model: model,
            modelParameters: modelParameters,
            anthropicMaxTokens: anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: anthropicClaudeCodeImpersonationEnabled,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEffort
        ) { title in
            if self.selectedConversationID == conversationID {
                persistCurrentConversation(refreshesUpdatedAt: false)
            }

            guard let title,
                  let currentIndex = conversations.firstIndex(where: { $0.id == conversationID }),
                  !conversations[currentIndex].hasGeneratedTitle,
                  !title.isEmpty else {
                return
            }

            conversations[currentIndex].title = title
            conversations[currentIndex].hasGeneratedTitle = true
            saveConversationsPreservingSelectedConversation()
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
    let revisionNavigationState: MessageRevisionNavigationState?
    let onSelect: () -> Void
    let onReasoningExpansionChanged: (Bool) -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void
    let onSelectPreviousRevision: () -> Void
    let onSelectNextRevision: () -> Void
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
                Text(message.isStopped
                    ? AppLocalizations.string("chat.message.stopped", defaultValue: "Generation stopped.")
                    : AppLocalizations.string("chat.message.generating", defaultValue: "Generating response..."))
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

            if let revisionNavigationState {
                revisionNavigationControl(revisionNavigationState)
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

    private func revisionNavigationControl(_ state: MessageRevisionNavigationState) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelectPreviousRevision()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(!state.canMovePrevious)
            .opacity(state.canMovePrevious ? 1 : 0.32)

            Text(state.displayText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 54)

            Button {
                onSelectNextRevision()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(!state.canMoveNext)
            .opacity(state.canMoveNext ? 1 : 0.32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalizations.format(
            "accessibility.messageRevision",
            defaultValue: "Message version %@",
            arguments: [state.displayText]
        ))
    }

    private var assistantMessageStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.toolExchanges.isEmpty {
                toolActivityBlock
            }

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

    private var toolActivityTitleIsActive: Bool {
        guard isStreaming else { return false }

        return message.toolExchanges.contains { exchange in
            exchange.toolCalls.contains { call in
                !exchange.toolResults.contains { $0.toolCallID == call.id }
            }
        }
    }

    private var reasoningTitleIsActive: Bool {
        isStreaming && hasStreamingReasoning && !hasStreamingContent
    }

    private var toolActivityBlock: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.toolExchanges) { exchange in
                    ForEach(exchange.toolCalls) { call in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                Text(call.displayName.isEmpty ? call.name : call.displayName)
                                    .fontWeight(.semibold)
                            }

                            if let result = exchange.toolResults.first(where: { $0.toolCallID == call.id }) {
                                Text(result.isError
                                    ? AppLocalizations.string("toolCall.failed", defaultValue: "Call failed")
                                    : AppLocalizations.string("toolCall.completed", defaultValue: "Call completed"))
                                    .foregroundStyle(result.isError ? Color.red : Color.secondary)

                                toolResultContent(result)
                            } else {
                                Text(AppLocalizations.string("toolCall.calling", defaultValue: "Calling..."))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(.secondary)

                MovingHighlightTitle(
                    text: AppLocalizations.string("toolCall.title", defaultValue: "Tool Calls"),
                    isActive: toolActivityTitleIsActive
                )

                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func toolResultContent(_ result: ChatToolResult) -> some View {
        let searchResults = result.isError ? [] : toolSearchResults(from: result.content)

        if !searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(searchResults) { item in
                    Link(destination: item.url) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption2.weight(.semibold))

                            Text(item.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(toolResultBackground)
        } else {
            let content = toolResultPreview(result.content)
            if !content.isEmpty {
                Text(content)
                    .font(.caption2.monospaced())
                    .foregroundStyle(result.isError ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(toolResultBackground)
            }
        }
    }

    private var toolResultBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05))
    }

    private func toolResultPreview(_ content: String) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }

        let limit = 4_000
        guard trimmedContent.count > limit else { return trimmedContent }
        return AppLocalizations.format(
            "toolResult.previewTruncated",
            defaultValue: "%@\n\n...(Result too long, display truncated)",
            arguments: [String(trimmedContent.prefix(limit))]
        )
    }

    private func toolSearchResults(from content: String) -> [ToolSearchResult] {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return []
        }

        var visitedStrings = Set<String>()
        var candidates = toolSearchResultCandidates(fromJSONString: trimmedContent, depth: 0, visitedStrings: &visitedStrings)
        if candidates.isEmpty {
            candidates = scannedToolSearchResultCandidates(from: trimmedContent)
        }
        var seenURLs = Set<String>()

        return candidates.enumerated().compactMap { index, candidate in
            let key = candidate.url.absoluteString
            guard seenURLs.insert(key).inserted else { return nil }

            return ToolSearchResult(
                id: "\(index)-\(key)",
                title: candidate.title,
                url: candidate.url
            )
        }
    }

    private func toolSearchResultCandidates(
        fromJSONString jsonString: String,
        depth: Int,
        visitedStrings: inout Set<String>
    ) -> [ToolSearchResultCandidate] {
        guard depth < 6 else { return [] }

        let trimmedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty,
              visitedStrings.insert(trimmedString).inserted,
              let data = trimmedString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return []
        }

        return toolSearchResultCandidates(fromJSONObject: object, depth: depth, visitedStrings: &visitedStrings)
    }

    private func toolSearchResultCandidates(
        fromJSONObject object: Any,
        depth: Int,
        visitedStrings: inout Set<String>
    ) -> [ToolSearchResultCandidate] {
        guard depth < 6 else { return [] }

        if let string = object as? String {
            return toolSearchResultCandidates(fromJSONString: string, depth: depth + 1, visitedStrings: &visitedStrings)
        }

        if let array = object as? [Any] {
            let directCandidates = array.compactMap(toolSearchResultCandidate)
            if !directCandidates.isEmpty {
                return directCandidates
            }

            return array.flatMap {
                toolSearchResultCandidates(fromJSONObject: $0, depth: depth + 1, visitedStrings: &visitedStrings)
            }
        }

        guard let dictionary = object as? [String: Any] else {
            return []
        }

        var candidates = [ToolSearchResultCandidate]()

        if let results = dictionary["results"] {
            candidates.append(contentsOf: toolSearchResultCandidates(fromJSONObject: results, depth: depth + 1, visitedStrings: &visitedStrings))
        }

        for key in ["structuredContent", "structured_content", "data", "result"] {
            if let nestedObject = dictionary[key] {
                candidates.append(contentsOf: toolSearchResultCandidates(fromJSONObject: nestedObject, depth: depth + 1, visitedStrings: &visitedStrings))
            }
        }

        if let content = dictionary["content"] {
            candidates.append(contentsOf: toolSearchResultCandidates(fromJSONObject: content, depth: depth + 1, visitedStrings: &visitedStrings))
        }

        for key in ["text", "json", "output"] {
            if let nestedString = dictionary[key] as? String,
               looksLikeJSON(nestedString) {
                candidates.append(contentsOf: toolSearchResultCandidates(fromJSONString: nestedString, depth: depth + 1, visitedStrings: &visitedStrings))
            }
        }

        if candidates.isEmpty,
           let directCandidate = toolSearchResultCandidate(from: dictionary) {
            candidates.append(directCandidate)
        }

        return candidates
    }

    private func toolSearchResultCandidate(from object: Any) -> ToolSearchResultCandidate? {
        guard let dictionary = object as? [String: Any] else { return nil }

        return toolSearchResultCandidate(from: dictionary)
    }

    private func toolSearchResultCandidate(from dictionary: [String: Any]) -> ToolSearchResultCandidate? {
        guard let rawURL = firstStringValue(in: dictionary, forKeys: ["url", "link"]),
              let url = searchResultURL(from: rawURL) else {
            return nil
        }

        let rawTitle = firstStringValue(in: dictionary, forKeys: ["title", "name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty
            ? (fallbackTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString)
            : rawTitle

        return ToolSearchResultCandidate(title: title, url: url)
    }

    private func searchResultURL(from rawURL: String) -> URL? {
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        return url
    }

    private func firstStringValue(in dictionary: [String: Any], forKeys keys: [String]) -> String? {
        for key in keys {
            if let string = dictionary[key] as? String {
                return string
            }
        }

        return nil
    }

    private func looksLikeJSON(_ string: String) -> Bool {
        guard let firstCharacter = string.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return false
        }

        return firstCharacter == "{" || firstCharacter == "["
    }

    private func scannedToolSearchResultCandidates(from content: String) -> [ToolSearchResultCandidate] {
        let urlMatches = jsonStringMatches(forKey: "url", in: content)
        let titleMatches = jsonStringMatches(forKey: "title", in: content)
        guard !urlMatches.isEmpty else { return [] }

        return urlMatches.compactMap { urlMatch in
            guard let url = searchResultURL(from: urlMatch.value) else { return nil }

            let title = titleMatches
                .filter { $0.range.location > urlMatch.range.location }
                .min { $0.range.location < $1.range.location }?
                .value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 }
                ?? fallbackTitle.flatMap { $0.isEmpty ? nil : $0 }
                ?? url.absoluteString

            return ToolSearchResultCandidate(title: resolvedTitle, url: url)
        }
    }

    private func jsonStringMatches(forKey key: String, in content: String) -> [(value: String, range: NSRange)] {
        let pattern = #""# + NSRegularExpression.escapedPattern(for: key) + #""\s*:\s*"((?:\\.|[^"\\])*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        return regex.matches(in: content, range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }

            let rawValue = nsContent.substring(with: match.range(at: 1))
            return (unescapedJSONStringValue(rawValue), match.range)
        }
    }

    private func unescapedJSONStringValue(_ value: String) -> String {
        let jsonString = "\"\(value)\""
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return value
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
        }

        return decoded
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
                        .foregroundStyle(.secondary)

                    MovingHighlightTitle(
                        text: AppLocalizations.string("reasoning.title", defaultValue: "Reasoning"),
                        isActive: reasoningTitleIsActive
                    )
                        .font(.caption.weight(.semibold))

                    Spacer()
                }
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
                Text(AppLocalizations.string("chat.message.stopped", defaultValue: "Generation stopped."))
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
        guard let separatorRange = normalized.range(of: "\n\n") ?? normalized.range(of: "\n") else {
            return nil
        }

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
            || summary.hasPrefix("Request failed")
            || summary.hasPrefix("解析失败")
            || summary.hasPrefix("Parsing failed")
            || summary.hasPrefix("模型列表解析失败")
            || summary.hasPrefix("Failed to parse model list")
            || summary.hasPrefix("流式请求失败")
            || summary.hasPrefix("Streaming request failed")
            || summary.contains("状态码")
            || summary.contains("status code")
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
    @State private var didCopy = false

    private var languageName: String {
        let value = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "text"
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045)
    }

    private var headerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.055)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(languageName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Button {
                    copyCode()
                } label: {
                    Label(didCopy
                        ? AppLocalizations.string("code.copy.copied", defaultValue: "Copied")
                        : AppLocalizations.string("code.copy", defaultValue: "Copy"),
                        systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(didCopy ? Color.green : Color.secondary)
                        .frame(minWidth: 58, minHeight: 24)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(didCopy ? Color.green.opacity(0.12) : Color.secondary.opacity(0.10))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy
                    ? AppLocalizations.string("accessibility.codeCopied", defaultValue: "Code copied")
                    : AppLocalizations.string("accessibility.copyCode", defaultValue: "Copy code"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(headerColor)

            Divider()
                .opacity(0.55)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(content.isEmpty ? " " : content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }

    private func copyCode() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: content]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(120)
            ]
        )
        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
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
                    containerTitle = rawTitle.isEmpty
                        ? AppLocalizations.string("markdown.container.defaultTitle", defaultValue: "Note")
                        : rawTitle
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

private struct ChatInputComposer<OptionsMenu: View>: View {
    @ObservedObject var inputDraft: ChatInputDraft
    @Environment(\.colorScheme) private var colorScheme

    let isGenerating: Bool
    let isEditingMessage: Bool
    let isSpeechRecording: Bool
    let hasPendingAttachments: Bool
    let inputGlassTint: Color
    let controlGlassHighlight: Color
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onExpandInput: () -> Void
    let onToggleSpeechInput: () -> Void
    let onStopGenerating: () -> Void
    let onSendMessage: () -> Void
    let onCancelEditingMessage: () -> Void
    let onSaveEditingMessageOnly: () -> Void
    let onSaveEditingMessageAndRegenerate: () -> Void
    let optionsMenu: () -> OptionsMenu

    init(
        inputDraft: ChatInputDraft,
        isGenerating: Bool,
        isEditingMessage: Bool,
        isSpeechRecording: Bool,
        hasPendingAttachments: Bool,
        inputGlassTint: Color,
        controlGlassHighlight: Color,
        onPasteImageProviders: @escaping ([NSItemProvider]) -> Void,
        onExpandInput: @escaping () -> Void,
        onToggleSpeechInput: @escaping () -> Void,
        onStopGenerating: @escaping () -> Void,
        onSendMessage: @escaping () -> Void,
        onCancelEditingMessage: @escaping () -> Void,
        onSaveEditingMessageOnly: @escaping () -> Void,
        onSaveEditingMessageAndRegenerate: @escaping () -> Void,
        @ViewBuilder optionsMenu: @escaping () -> OptionsMenu
    ) {
        self.inputDraft = inputDraft
        self.isGenerating = isGenerating
        self.isEditingMessage = isEditingMessage
        self.isSpeechRecording = isSpeechRecording
        self.hasPendingAttachments = hasPendingAttachments
        self.inputGlassTint = inputGlassTint
        self.controlGlassHighlight = controlGlassHighlight
        self.onPasteImageProviders = onPasteImageProviders
        self.onExpandInput = onExpandInput
        self.onToggleSpeechInput = onToggleSpeechInput
        self.onStopGenerating = onStopGenerating
        self.onSendMessage = onSendMessage
        self.onCancelEditingMessage = onCancelEditingMessage
        self.onSaveEditingMessageOnly = onSaveEditingMessageOnly
        self.onSaveEditingMessageAndRegenerate = onSaveEditingMessageAndRegenerate
        self.optionsMenu = optionsMenu
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            optionsMenu()

            textInputArea

            speechInputControl

            inputActionControl
        }
    }

    private var textInputArea: some View {
        ZStack(alignment: .topTrailing) {
            ImagePastingTextView(
                text: inputDraft.text,
                textRevision: inputDraft.textRevision,
                isFocused: $inputDraft.isFocused,
                focusRequestID: inputDraft.focusRequestID,
                focusDelay: 0,
                placeholder: AppLocalizations.string("input.placeholder", defaultValue: "Type a message..."),
                maxVisibleLineCount: 4,
                fillsAvailableHeight: false,
                trailingAccessoryInset: 34,
                allowsFocus: true,
                onTextChanged: inputDraft.updateFromTextView,
                onMeasuredLineCountChanged: inputDraft.updateMeasuredLineCount,
                onPasteImageProviders: onPasteImageProviders
            )
            .font(.body)
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if inputDraft.showsExpandedInputButton {
                Button {
                    onExpandInput()
                } label: {
                    expandInputIcon
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.expandInput", defaultValue: "Expand input"))
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandInputIcon: some View {
        ZStack {
            Image(systemName: "arrow.up.left")
                .offset(x: -3, y: -3)
            Image(systemName: "arrow.down.right")
                .offset(x: 3, y: 3)
        }
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.primary)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText || hasPendingAttachments
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
        isSpeechRecording
            ? Color.red.opacity(colorScheme == .dark ? 0.22 : 0.12)
            : inputGlassTint
    }

    private var speechInputControl: some View {
        Button {
            onToggleSpeechInput()
        } label: {
            controlGlassIcon(
                systemName: isSpeechRecording ? "mic.fill" : "mic",
                size: 18,
                weight: .semibold,
                frame: 40,
                tint: speechControlBackground,
                foreground: isSpeechRecording ? .red : .primary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeechRecording
            ? AppLocalizations.string("accessibility.stopSpeechInput", defaultValue: "Stop speech input")
            : AppLocalizations.string("accessibility.startSpeechInput", defaultValue: "Start speech input"))
    }

    @ViewBuilder
    private var inputActionControl: some View {
        if isEditingMessage {
            HStack(spacing: 8) {
                Button {
                    onCancelEditingMessage()
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
                .accessibilityLabel(AppLocalizations.string("accessibility.cancelEdit", defaultValue: "Cancel edit"))

                Menu {
                    Button("仅修改") {
                        onSaveEditingMessageOnly()
                    }

                    Button("修改并发送") {
                        onSaveEditingMessageAndRegenerate()
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
                    onStopGenerating()
                } else {
                    onSendMessage()
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

    private func controlGlassBackground(_ tint: Color) -> some View {
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
}

private struct ExpandedChatInputView: View {
    @ObservedObject var inputDraft: ChatInputDraft
    @Environment(\.colorScheme) private var colorScheme

    let isGenerating: Bool
    let isEditingMessage: Bool
    let isSpeechRecording: Bool
    let hasPendingAttachments: Bool
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onDismiss: () -> Void
    let onToggleSpeechInput: () -> Void
    let onStopGenerating: () -> Void
    let onSendMessage: () -> Void
    let onCancelEditingMessage: () -> Void
    let onSaveEditingMessageOnly: () -> Void
    let onSaveEditingMessageAndRegenerate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.collapseInput", defaultValue: "Collapse input"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            GeometryReader { geometry in
                ImagePastingTextView(
                    text: inputDraft.text,
                    textRevision: inputDraft.textRevision,
                    isFocused: .constant(true),
                    focusRequestID: 1,
                    focusDelay: 0.25,
                    placeholder: AppLocalizations.string("input.placeholder", defaultValue: "Type a message..."),
                    maxVisibleLineCount: 200,
                    fillsAvailableHeight: true,
                    trailingAccessoryInset: 0,
                    allowsFocus: true,
                    onTextChanged: inputDraft.updateFromExpandedTextView,
                    onMeasuredLineCountChanged: { _ in },
                    onPasteImageProviders: onPasteImageProviders
                )
                .font(.body)
                .foregroundStyle(Color.primary)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 6)
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                speechInputControl

                Spacer(minLength: 0)

                inputActionControl
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private var canSendMessage: Bool {
        inputDraft.hasSubmittableText || hasPendingAttachments
    }

    private var activeControlTint: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
    }

    private var quietControlTint: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    private var cancelControlTint: Color {
        Color.red.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }

    private var speechInputControl: some View {
        Button {
            onToggleSpeechInput()
        } label: {
            expandedControlIcon(
                systemName: isSpeechRecording ? "mic.fill" : "mic",
                foreground: isSpeechRecording ? .red : .primary,
                tint: isSpeechRecording ? cancelControlTint : quietControlTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpeechRecording
            ? AppLocalizations.string("accessibility.stopSpeechInput", defaultValue: "Stop speech input")
            : AppLocalizations.string("accessibility.startSpeechInput", defaultValue: "Start speech input"))
    }

    @ViewBuilder
    private var inputActionControl: some View {
        if isEditingMessage {
            HStack(spacing: 10) {
                Button {
                    onCancelEditingMessage()
                } label: {
                    expandedControlIcon(
                        systemName: "xmark",
                        foreground: .red,
                        tint: cancelControlTint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string("accessibility.cancelEdit", defaultValue: "Cancel edit"))

                Menu {
                    Button("仅修改") {
                        onSaveEditingMessageOnly()
                    }

                    Button("修改并发送") {
                        onSaveEditingMessageAndRegenerate()
                    }
                } label: {
                    expandedControlIcon(
                        systemName: "checkmark",
                        tint: canSendMessage ? activeControlTint : quietControlTint
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
                .accessibilityLabel(AppLocalizations.string("accessibility.saveEdit", defaultValue: "Save edit"))
            }
        } else {
            Button {
                if isGenerating {
                    onStopGenerating()
                } else {
                    onSendMessage()
                }
            } label: {
                expandedControlIcon(
                    systemName: isGenerating ? "stop.fill" : "paperplane.fill",
                    tint: isGenerating || canSendMessage ? activeControlTint : quietControlTint
                )
            }
            .buttonStyle(.plain)
            .disabled(!isGenerating && !canSendMessage)
            .accessibilityLabel(isGenerating
                ? AppLocalizations.string("accessibility.stopGenerating", defaultValue: "Stop generating")
                : AppLocalizations.string("accessibility.sendMessage", defaultValue: "Send message"))
        }
    }

    private func expandedControlIcon(
        systemName: String,
        foreground: Color = .primary,
        tint: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(tint))

            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .frame(width: 48, height: 48)
    }
}

struct ImagePastingTextView: UIViewRepresentable {
    let text: String
    let textRevision: Int
    @Binding var isFocused: Bool
    let focusRequestID: Int
    let focusDelay: TimeInterval
    let placeholder: String
    let maxVisibleLineCount: Int
    let fillsAvailableHeight: Bool
    let trailingAccessoryInset: CGFloat
    let allowsFocus: Bool
    let onTextChanged: (String) -> Void
    let onMeasuredLineCountChanged: (Int) -> Void
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
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.returnKeyType = .default
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: ImagePastingUITextView, context: Context) {
        textView.configure(
            maxVisibleLineCount: maxVisibleLineCount,
            fillsAvailableHeight: fillsAvailableHeight,
            trailingAccessoryInset: trailingAccessoryInset
        )

        var didApplyExternalText = false
        if context.coordinator.lastAppliedTextRevision != textRevision,
           (textView.text ?? "") != text {
            let previousText = textView.text ?? ""
            let previousSelectedRange = textView.selectedRange
            textView.text = text
            didApplyExternalText = true
            textView.selectedRange = context.coordinator.restoredSelectedRange(
                previousText: previousText,
                newText: text,
                previousSelectedRange: previousSelectedRange
            )
            textView.scrollCaretToVisibleIfNeeded()
        }
        context.coordinator.lastAppliedTextRevision = textRevision

        context.coordinator.onTextChanged = onTextChanged
        context.coordinator.onMeasuredLineCountChanged = onMeasuredLineCountChanged
        textView.onPasteImageProviders = onPasteImageProviders
        textView.isEditable = true
        textView.isSelectable = true
        textView.placeholderText = placeholder
        textView.accessibilityLabel = placeholder
        textView.updatePlaceholderVisibility()
        textView.updateScrollingBehavior()
        textView.scrollCaretToVisibleIfNeeded()
        if didApplyExternalText || context.coordinator.needsScheduledLayoutStateRefresh(for: textView) {
            context.coordinator.scheduleLayoutStateRefresh(for: textView)
        }

        context.coordinator.updateFocus(
            for: textView,
            shouldBeFocused: isFocused,
            allowsFocus: allowsFocus,
            requestID: focusRequestID,
            focusDelay: focusDelay
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 0
        let fittingWidth = width > 0 ? width : UIScreen.main.bounds.width
        let lineHeight = uiView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        if fillsAvailableHeight, let proposedHeight = proposal.height, proposedHeight > 0 {
            return CGSize(width: fittingWidth, height: max(proposedHeight, lineHeight))
        }

        let fittingSize = uiView.sizeThatFits(
            CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        )

        let maxHeight = lineHeight * CGFloat(max(maxVisibleLineCount, 1))
        let height = min(max(fittingSize.height, lineHeight), maxHeight)
        return CGSize(width: fittingWidth, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isFocused: $isFocused,
            onTextChanged: onTextChanged,
            onMeasuredLineCountChanged: onMeasuredLineCountChanged
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let isFocused: Binding<Bool>
        var onTextChanged: (String) -> Void
        var onMeasuredLineCountChanged: (Int) -> Void
        private var lastHandledFocusRequestID: Int?
        private var pendingDelayedFocusRequestID: Int?
        var lastAppliedTextRevision: Int?
        private var lastScheduledLayoutRefreshKey: LayoutRefreshKey?

        private struct LayoutRefreshKey: Equatable {
            let width: CGFloat
            let trailingInset: CGFloat
        }

        init(
            isFocused: Binding<Bool>,
            onTextChanged: @escaping (String) -> Void,
            onMeasuredLineCountChanged: @escaping (Int) -> Void
        ) {
            self.isFocused = isFocused
            self.onTextChanged = onTextChanged
            self.onMeasuredLineCountChanged = onMeasuredLineCountChanged
        }

        func textViewDidChange(_ textView: UITextView) {
            let updatedText = textView.text ?? ""
            onTextChanged(updatedText)
            (textView as? ImagePastingUITextView)?.updatePlaceholderVisibility()
            if let textView = textView as? ImagePastingUITextView {
                refreshLayoutState(for: textView)
            } else {
                publishMeasuredLineCount(for: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? ImagePastingUITextView)?.scrollCaretToVisibleIfNeeded()
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
            allowsFocus: Bool,
            requestID: Int,
            focusDelay: TimeInterval
        ) {
            let isNewRequest = lastHandledFocusRequestID != requestID
            guard allowsFocus else {
                lastHandledFocusRequestID = requestID
                pendingDelayedFocusRequestID = nil
                if textView.isFirstResponder {
                    textView.resignFirstResponder()
                }
                return
            }

            guard isNewRequest || (shouldBeFocused && !textView.isFirstResponder) else { return }

            if isNewRequest {
                lastHandledFocusRequestID = requestID
                pendingDelayedFocusRequestID = nil
            }

            if shouldBeFocused, focusDelay > 0 {
                guard pendingDelayedFocusRequestID != requestID else { return }

                pendingDelayedFocusRequestID = requestID
                retryFocus(
                    to: textView,
                    shouldBeFocused: shouldBeFocused,
                    attemptsRemaining: 4,
                    delay: focusDelay
                )
                return
            }

            if shouldBeFocused, textView.window != nil {
                if !textView.becomeFirstResponder() {
                    retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
                }
                return
            }

            if shouldBeFocused {
                retryFocus(to: textView, shouldBeFocused: shouldBeFocused, attemptsRemaining: 4)
            } else if isNewRequest, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        private func retryFocus(
            to textView: ImagePastingUITextView,
            shouldBeFocused: Bool,
            attemptsRemaining: Int,
            delay: TimeInterval = 0.01
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak textView] in
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

        func refreshLayoutState(for textView: ImagePastingUITextView) {
            textView.updateScrollingBehavior()
            publishMeasuredLineCount(for: textView)
            textView.scrollCaretToVisibleIfNeeded()
        }

        func needsScheduledLayoutStateRefresh(for textView: ImagePastingUITextView) -> Bool {
            guard textView.bounds.width > 0 else { return false }

            let key = LayoutRefreshKey(
                width: Self.roundedLayoutValue(textView.bounds.width),
                trailingInset: Self.roundedLayoutValue(textView.textContainerInset.right)
            )
            guard lastScheduledLayoutRefreshKey != key else { return false }

            lastScheduledLayoutRefreshKey = key
            return true
        }

        func scheduleLayoutStateRefresh(for textView: ImagePastingUITextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.refreshLayoutState(for: textView)
            }
        }

        func restoredSelectedRange(
            previousText: String,
            newText: String,
            previousSelectedRange: NSRange
        ) -> NSRange {
            let previousTextLength = (previousText as NSString).length
            let newTextLength = (newText as NSString).length

            if previousSelectedRange.location >= previousTextLength {
                return NSRange(location: newTextLength, length: 0)
            }

            let location = min(max(previousSelectedRange.location, 0), newTextLength)
            let availableLength = max(newTextLength - location, 0)
            let length = min(max(previousSelectedRange.length, 0), availableLength)
            return NSRange(location: location, length: length)
        }

        private func publishMeasuredLineCount(for textView: UITextView) {
            if let textView = textView as? ImagePastingUITextView {
                guard textView.bounds.width > 0 else { return }
                onMeasuredLineCountChanged(textView.measuredVisualLineCount())
            } else {
                let lineHeight = max(
                    textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight,
                    1
                )
                let verticalInsets = textView.textContainerInset.top + textView.textContainerInset.bottom
                let contentHeight = max(textView.contentSize.height - verticalInsets, lineHeight)
                let lineCount = Int(ceil(contentHeight / lineHeight))
                onMeasuredLineCountChanged(lineCount)
            }
        }

        private static func roundedLayoutValue(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }
    }
}

final class ImagePastingUITextView: UITextView {
    var onPasteImageProviders: (([NSItemProvider]) -> Void)?
    private let placeholderLabel = UILabel()
    private var placeholderTrailingConstraint: NSLayoutConstraint?
    private var maxVisibleLineCount = 5
    private var fillsAvailableHeight = false

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

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollingBehavior()
    }

    func configure(
        maxVisibleLineCount: Int,
        fillsAvailableHeight: Bool,
        trailingAccessoryInset: CGFloat
    ) {
        let clampedLineCount = max(maxVisibleLineCount, 1)
        var didChangeLayoutBehavior = false

        if self.maxVisibleLineCount != clampedLineCount {
            self.maxVisibleLineCount = clampedLineCount
            didChangeLayoutBehavior = true
        }

        if self.fillsAvailableHeight != fillsAvailableHeight {
            self.fillsAvailableHeight = fillsAvailableHeight
            didChangeLayoutBehavior = true
        }

        alwaysBounceVertical = fillsAvailableHeight

        if abs(textContainerInset.right - trailingAccessoryInset) > 0.5 {
            textContainerInset.right = trailingAccessoryInset
            placeholderTrailingConstraint?.constant = -trailingAccessoryInset
            didChangeLayoutBehavior = true
        }

        if didChangeLayoutBehavior {
            setNeedsLayout()
        }
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    func updateScrollingBehavior() {
        if !isScrollEnabled {
            isScrollEnabled = true
        }

        showsVerticalScrollIndicator = fillsAvailableHeight || measuredVisualLineCount() > maxVisibleLineCount
    }

    func scrollCaretToVisibleIfNeeded() {
        guard isFirstResponder, isScrollEnabled else { return }

        let textLength = ((text ?? "") as NSString).length
        let caretLocation = min(selectedRange.location + selectedRange.length, textLength)
        scrollRangeToVisible(NSRange(location: caretLocation, length: 0))
    }

    func measuredVisualLineCount() -> Int {
        let textWidth = bounds.width
            - textContainerInset.left
            - textContainerInset.right
            - textContainer.lineFragmentPadding * 2
        guard textWidth > 0 else { return 1 }

        let text = text ?? ""
        guard !text.isEmpty else { return 1 }

        let font = font ?? .preferredFont(forTextStyle: .body)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )

        let baseLineCount = Int(ceil(max(boundingRect.height, font.lineHeight) / max(font.lineHeight, 1)))
        let lineCount = text.hasSuffix("\n") ? baseLineCount + 1 : baseLineCount
        return max(lineCount, 1)
    }

    private func setupPlaceholder() {
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = font ?? .preferredFont(forTextStyle: .body)
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        let trailingConstraint = placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        placeholderTrailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            trailingConstraint
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
