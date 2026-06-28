import SwiftUI
import UIKit

extension MarkdownRenderStyle {
    @MainActor
    static func chatDefault(colorScheme: ColorScheme) -> MarkdownRenderStyle {
        chatDefault(
            colorScheme: colorScheme,
            displayScale: UIScreen.main.scale
        )
    }

    static func chatDefault(
        colorScheme: ColorScheme,
        displayScale: CGFloat
    ) -> MarkdownRenderStyle {
        MarkdownRenderStyle(
            textColor: .label,
            baseFont: .preferredFont(forTextStyle: .body),
            textAlignment: .left,
            userInterfaceStyle: colorScheme == .dark ? .dark : .light,
            displayScale: displayScale
        )
    }
}

extension MarkdownRenderCacheController {
    func prepareChatCaches(
        for messages: [ChatMessage],
        colorScheme: ColorScheme
    ) {
        prepareCaches(
            for: messages,
            style: .chatDefault(colorScheme: colorScheme)
        )
    }

    func prepareChatCache(
        for messageID: UUID,
        in messages: [ChatMessage],
        colorScheme: ColorScheme,
        onPrepared: (() -> Void)? = nil
    ) {
        prepareCache(
            for: messageID,
            in: messages,
            style: .chatDefault(colorScheme: colorScheme),
            onPrepared: onPrepared
        )
    }

    func prepareChatCache(
        for messageID: UUID,
        content: String,
        colorScheme: ColorScheme,
        onPrepared: (() -> Void)? = nil
    ) {
        prepareCache(
            for: messageID,
            content: content,
            style: .chatDefault(colorScheme: colorScheme),
            onPrepared: onPrepared
        )
    }

    func resetChatCaches(
        for messages: [ChatMessage],
        colorScheme: ColorScheme
    ) {
        reset(
            for: messages,
            style: .chatDefault(colorScheme: colorScheme)
        )
    }
}
