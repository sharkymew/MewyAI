import Foundation
import SwiftUI
import UIKit

struct StreamingAssistantMarkdownText: View {
    let content: String
    let streamingChannel: StreamingTextUpdateChannel?
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderedContent: String
    @State private var pendingAppendChunks: [String] = []
    @State private var renderedSegments: [StreamingChatMarkdownSegment]
    @State private var renderCache = PreparedMarkdownBlockCache()
    @State private var renderTask: Task<Void, Never>?
    @State private var renderTaskID: UUID?
    @State private var detachedRenderTask: Task<StreamingMarkdownRenderResult?, Never>?
    // Monotonic render invalidation token. Comparing this is O(1), so long
    // streaming responses do not force MainActor to scan entire strings.
    @State private var renderVersion: Int = 0
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
            renderVersion += 1
            renderedContent = newContent
            scheduleRender()
        }
        .onChange(of: colorScheme) { _, _ in
            renderVersion += 1
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

        let taskID = UUID()
        renderTaskID = taskID
        renderTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                // A cancelled task must release the render lock before it exits;
                // otherwise renderTask stays non-nil and future tokens cannot
                // schedule another render. The task ID prevents an old cancelled
                // task from clearing a newer render task that replaced it.
                clearRenderTaskIfCurrent(taskID)
                return
            }

            applyPendingChunks()
            let contentSnapshot = renderedContent
            // Capture the version immediately before the detached render. Doing
            // this after applyPendingChunks preserves the 50ms batch window while
            // still letting us reject stale detached results with an O(1) check.
            let versionSnapshot = renderVersion
            let style = renderStyle
            let cacheSnapshot = renderCache
            let detachedTask = Task.detached(priority: .userInitiated) {
                await Self.renderSegments(
                    for: contentSnapshot,
                    style: style,
                    cache: cacheSnapshot
                )
            }
            detachedRenderTask = detachedTask
            let result = await detachedTask.value

            guard !Task.isCancelled else {
                // Same lock-release rule applies after the detached renderer
                // returns: every cancellation exit must unblock the state machine.
                clearRenderTaskIfCurrent(taskID)
                return
            }

            guard let result else {
                // nil is the renderer's explicit cancellation sentinel. It means
                // the detached task cooperatively stopped before producing a full
                // render, so MainActor must not treat it as a valid empty result
                // or apply it over the currently displayed content.
                clearRenderTaskIfCurrent(taskID)
                let shouldRenderAgain = needsRenderAfterCurrentTask || !pendingAppendChunks.isEmpty
                needsRenderAfterCurrentTask = false
                if shouldRenderAgain {
                    scheduleRender()
                }
                return
            }

            // Version guard replaces renderedContent == contentSnapshot. That
            // avoids repeatedly scanning large streamed transcripts on MainActor.
            if renderVersion == versionSnapshot {
                renderedSegments = result.segments
                renderCache = result.cache
            } else {
                needsRenderAfterCurrentTask = true
            }
            // Clear before tail-scheduling; otherwise scheduleRender() would see
            // the current task and set needsRenderAfterCurrentTask instead of
            // starting the next render.
            clearRenderTaskIfCurrent(taskID)
            let shouldRenderAgain = needsRenderAfterCurrentTask || !pendingAppendChunks.isEmpty
            needsRenderAfterCurrentTask = false
            if shouldRenderAgain {
                scheduleRender()
            }
        }
    }

    private func clearRenderTaskIfCurrent(_ taskID: UUID) {
        guard renderTaskID == taskID else { return }
        renderTask = nil
        renderTaskID = nil
        detachedRenderTask = nil
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
            renderVersion += 1
            renderedContent = update.chunks.joined()
            renderCache = PreparedMarkdownBlockCache()
            renderedSegments = Self.fallbackSegments(for: renderedContent)
            if !renderedContent.isEmpty {
                scheduleRender(delay: .zero)
            }
            return
        }

        guard !update.chunks.isEmpty else { return }
        renderVersion += 1
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
        detachedRenderTask?.cancel()
        renderTask = nil
        renderTaskID = nil
        detachedRenderTask = nil
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
    ) async -> StreamingMarkdownRenderResult? {
        let previousBlockCache = cache
        var nextBlockCache = PreparedMarkdownBlockCache()
        var segments: [StreamingChatMarkdownSegment] = []

        for segment in ChatMarkdownBlockSegment.split(content) {
            guard !Task.isCancelled else {
                // Task.detached does not inherit the outer renderTask's
                // cancellation automatically, so cancelRenderTask() explicitly
                // cancels the detached task handle. This checkpoint is the
                // renderer's cooperative stop sign: once cancellation is visible
                // here, return immediately instead of spending CPU/battery on
                // Markdown parsing, layout preparation, code blocks, or formulas
                // for content that MainActor will discard anyway. nil is used
                // deliberately here to distinguish "cancelled before completion"
                // from a successful render whose content legitimately produced
                // an empty segment array.
                return nil
            }

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
                        guard !Task.isCancelled else {
                            // A single Markdown text segment can still contain
                            // many streaming paragraph/table/list groups. Check
                            // again at this finer boundary so a cancelled long
                            // reply stops between expensive renderBlocks calls.
                            // nil carries the same cancellation semantic at this
                            // finer boundary: this is not a valid empty render.
                            return nil
                        }

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
                        guard !Task.isCancelled else {
                            // If cancellation arrived while renderBlocks was
                            // preparing UIKit/Markdown output, do not merge or
                            // publish work that is already obsolete.
                            // nil prevents partially obsolete renderBlocks output
                            // from being confused with a completed empty result.
                            return nil
                        }

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
