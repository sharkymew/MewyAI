import Foundation
import Observation

@MainActor
@Observable
final class MarkdownRenderCacheController {
    private var entries: [UUID: MarkdownRenderCacheEntry] = [:]

    @ObservationIgnored
    private var tasks: [UUID: Task<Void, Never>] = [:]

    subscript(messageID: UUID) -> MarkdownRenderCacheEntry? {
        entries[messageID]
    }

    func prepareCaches(
        for messages: [ChatMessage],
        style: MarkdownRenderStyle
    ) {
        messages
            .filter { $0.role == "assistant" && !$0.content.isEmpty }
            .forEach { prepareCache(for: $0.id, content: $0.content, style: style) }
    }

    func prepareCache(
        for messageID: UUID,
        in messages: [ChatMessage],
        style: MarkdownRenderStyle,
        onPrepared: (() -> Void)? = nil
    ) {
        guard let message = messages.first(where: { $0.id == messageID && $0.role == "assistant" }),
              !message.content.isEmpty else {
            invalidate(for: messageID)
            onPrepared?()
            return
        }
        prepareCache(for: messageID, content: message.content, style: style, onPrepared: onPrepared)
    }

    func prepareCache(
        for messageID: UUID,
        content: String,
        style: MarkdownRenderStyle,
        onPrepared: (() -> Void)? = nil
    ) {
        if ErrorDetailContent.parse(content) != nil {
            invalidate(for: messageID)
            onPrepared?()
            return
        }

        let signature = MarkdownRenderCacheEntry.signature(for: content, style: style)
        guard entries[messageID]?.signature != signature else {
            onPrepared?()
            return
        }

        tasks[messageID]?.cancel()
        tasks[messageID] = Task { @MainActor in
            let entry = await Task.detached(priority: .utility) {
                await MarkdownRenderCacheEntry.make(content: content, style: style)
            }.value

            guard !Task.isCancelled else { return }
            entries[messageID] = entry
            tasks[messageID] = nil
            onPrepared?()
        }
    }

    func invalidate(for messageID: UUID) {
        tasks[messageID]?.cancel()
        tasks[messageID] = nil
        entries[messageID] = nil
    }

    func reset(
        for messages: [ChatMessage],
        style: MarkdownRenderStyle
    ) {
        cancelAllTasks()
        entries = [:]
        prepareCaches(for: messages, style: style)
    }

    func prune(validMessageIDs: Set<UUID>) {
        entries = entries.filter { validMessageIDs.contains($0.key) }
        for (messageID, task) in tasks where !validMessageIDs.contains(messageID) {
            task.cancel()
            tasks[messageID] = nil
        }
    }

    var cachedMessageIDs: Set<UUID> {
        Set(entries.keys)
    }

    var pendingMessageIDs: Set<UUID> {
        Set(tasks.keys)
    }

    private func cancelAllTasks() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }
}
