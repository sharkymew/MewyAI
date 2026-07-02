//
//  MewyAIAppIntents.swift
//  AI Client
//
//  Created by SharkyMew on 2026/7/2.
//

import AppIntents
import Foundation
import UIKit

// MARK: - Shared runner

@MainActor
enum MewyAIIntentRunner {
    enum Failure: LocalizedError, Equatable {
        case configurationNotFound(name: String)
        case missingAPIKey
        case missingModel
        case conversationNotFound(id: String)
        case clipboardEmpty
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .configurationNotFound(let name):
                return AppLocalizations.format(
                    "appIntent.error.configurationNotFound",
                    defaultValue: "AI configuration not found: %@",
                    arguments: [name]
                )
            case .missingAPIKey:
                return AppLocalizations.string(
                    "appIntent.error.missingAPIKey",
                    defaultValue: "The selected AI configuration does not have an API key set."
                )
            case .missingModel:
                return AppLocalizations.string(
                    "appIntent.error.missingModel",
                    defaultValue: "The selected AI configuration does not have a model selected."
                )
            case .conversationNotFound(let id):
                return AppLocalizations.format(
                    "appIntent.error.conversationNotFound",
                    defaultValue: "Conversation not found: %@",
                    arguments: [id]
                )
            case .clipboardEmpty:
                return AppLocalizations.string(
                    "appIntent.error.clipboardEmpty",
                    defaultValue: "The system clipboard is empty."
                )
            case .saveFailed:
                return AppLocalizations.string(
                    "appIntent.error.saveFailed",
                    defaultValue: "The AI reply was generated, but the conversation could not be saved."
                )
            }
        }

        static func == (lhs: Failure, rhs: Failure) -> Bool {
            lhs.errorDescription == rhs.errorDescription
        }
    }

    static func resolveConfiguration(named name: String?) throws -> AIConfiguration {
        let configurations = AIConfigurationStore.loadConfigurations()
        let selectedID = AIConfigurationStore.loadSelectedConfigurationID()
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmedName.isEmpty {
            guard let match = configurations.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedName
            }) else {
                throw Failure.configurationNotFound(name: trimmedName)
            }
            return match
        }

        return AIConfigurationStore.selectedConfiguration(from: configurations, selectedID: selectedID)
    }

    static func validate(_ configuration: AIConfiguration) throws {
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingAPIKey
        }
        guard !configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingModel
        }
    }

    static func sendNonStreaming(
        message: String,
        configuration: AIConfiguration,
        contextMessages: [ChatMessage] = []
    ) async throws -> String {
        let service = AIService()
        service.resetConversation(
            with: contextMessages,
            systemPrompt: configuration.systemPrompt,
            usesImageAttachments: false
        )
        return try await service.sendMessageAsync(
            message: message,
            baseURL: configuration.requestURLString,
            apiFormat: configuration.apiFormat,
            apiKey: configuration.apiKey,
            customHeaders: configuration.customHeaders,
            model: configuration.selectedModel,
            modelParameters: configuration.selectedModelConfiguration,
            anthropicMaxTokens: configuration.anthropicMaxTokens,
            reasoningEnabled: configuration.reasoningEnabled,
            reasoningEffort: configuration.reasoningEffort,
            usesImageAttachments: false
        )
    }

    static func titleForNewConversation(from userText: String) -> String {
        let maxLength = 40
        let flattened = userText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = flattened
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !trimmed.isEmpty else {
            return AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
        }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    static func persistNewConversation(
        userText: String,
        assistantReply: String
    ) throws {
        var conversation = AIConversation()
        conversation.title = titleForNewConversation(from: userText)
        let now = Date()
        conversation.createdAt = now
        conversation.updatedAt = now
        conversation.messages = [
            ChatMessage(role: "user", content: userText),
            ChatMessage(role: "assistant", content: assistantReply)
        ]
        conversation.hasGeneratedTitle = false
        guard ConversationPersistenceCoordinator.saveConversationFromExternalSource(
            conversation,
            synchronize: true
        ) != nil else {
            throw Failure.saveFailed
        }
    }

    static func persistContinuedConversation(
        _ conversation: AIConversation,
        userText: String,
        assistantReply: String
    ) throws {
        var updated = conversation
        updated.messages.append(ChatMessage(role: "user", content: userText))
        updated.messages.append(ChatMessage(role: "assistant", content: assistantReply))
        updated.updatedAt = Date()
        guard ConversationPersistenceCoordinator.saveConversationFromExternalSource(
            updated,
            synchronize: true
        ) != nil else {
            throw Failure.saveFailed
        }
    }
}

// MARK: - SendMessageIntent

struct SendMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message to AI"
    static var description = IntentDescription(
        "Sends a message to AI using the current (or named) configuration and returns the AI's reply."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message")
    var message: String

    @Parameter(title: "Configuration Name", default: "")
    var configurationName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to AI") {
            \.$configurationName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let configuration = try MewyAIIntentRunner.resolveConfiguration(named: configurationName)
        try MewyAIIntentRunner.validate(configuration)
        let reply = try await MewyAIIntentRunner.sendNonStreaming(
            message: message,
            configuration: configuration
        )
        try MewyAIIntentRunner.persistNewConversation(userText: message, assistantReply: reply)
        return .result(value: reply)
    }
}

// MARK: - SummarizeTextIntent

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Text"
    static var description = IntentDescription(
        "Summarizes the provided long text using the current AI configuration."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Text to Summarize")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let configuration = try MewyAIIntentRunner.resolveConfiguration(named: nil)
        try MewyAIIntentRunner.validate(configuration)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .result(value: AppLocalizations.string(
                "appIntent.summarize.emptyInput",
                defaultValue: "There is nothing to summarize."
            ))
        }
        let prompt = AppLocalizations.format(
            "appIntent.summarize.prompt",
            defaultValue: "请用中文总结以下内容：\n\n%@",
            arguments: [trimmedText]
        )
        let userText = prompt
        let reply = try await MewyAIIntentRunner.sendNonStreaming(
            message: prompt,
            configuration: configuration
        )
        try MewyAIIntentRunner.persistNewConversation(userText: userText, assistantReply: reply)
        return .result(value: reply)
    }
}

// MARK: - AskAboutClipboardIntent

struct AskAboutClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask AI About Clipboard"
    static var description = IntentDescription(
        "Asks the AI a question about the current contents of the system clipboard."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question) about the clipboard")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let configuration = try MewyAIIntentRunner.resolveConfiguration(named: nil)
        try MewyAIIntentRunner.validate(configuration)

        let clipboardText = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardText.isEmpty else { throw MewyAIIntentRunner.Failure.clipboardEmpty }

        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText: String
        if trimmedQuestion.isEmpty {
            userText = AppLocalizations.format(
                "appIntent.clipboard.promptWithoutQuestion",
                defaultValue: "剪贴板内容：\n%@",
                arguments: [clipboardText]
            )
        } else {
            userText = AppLocalizations.format(
                "appIntent.clipboard.prompt",
                defaultValue: "剪贴板内容：\n%@\n\n用户问题：%@",
                arguments: [clipboardText, trimmedQuestion]
            )
        }

        let reply = try await MewyAIIntentRunner.sendNonStreaming(
            message: userText,
            configuration: configuration
        )
        try MewyAIIntentRunner.persistNewConversation(userText: userText, assistantReply: reply)
        return .result(value: reply)
    }
}

// MARK: - ContinueConversationIntent

struct ContinueConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Conversation"
    static var description = IntentDescription(
        "Sends a new message in an existing AI conversation and returns the AI's reply."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Conversation ID")
    var conversationID: String

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Continue \(\.$conversationID) with \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trimmedID = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmedID) else {
            throw MewyAIIntentRunner.Failure.conversationNotFound(id: trimmedID)
        }

        guard let conversation = ConversationStore.loadConversation(id: uuid) else {
            throw MewyAIIntentRunner.Failure.conversationNotFound(id: trimmedID)
        }

        let configuration = try MewyAIIntentRunner.resolveConfiguration(named: nil)
        try MewyAIIntentRunner.validate(configuration)

        let contextMessages = conversation.messages
        let reply = try await MewyAIIntentRunner.sendNonStreaming(
            message: message,
            configuration: configuration,
            contextMessages: contextMessages
        )

        try MewyAIIntentRunner.persistContinuedConversation(
            conversation,
            userText: message,
            assistantReply: reply
        )
        return .result(value: reply)
    }
}

// MARK: - App Shortcuts Provider

struct MewyAIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendMessageIntent(),
            phrases: [
                "Send a message to \(.applicationName)",
                "Ask \(.applicationName) to send a message",
                "向 \(.applicationName) 发送消息"
            ],
            shortTitle: "Send Message",
            systemImageName: "paperplane.fill"
        )
        AppShortcut(
            intent: SummarizeTextIntent(),
            phrases: [
                "Summarize text with \(.applicationName)",
                "Ask \(.applicationName) to summarize",
                "用 \(.applicationName) 总结文本"
            ],
            shortTitle: "Summarize",
            systemImageName: "doc.text.magnifyingglass"
        )
        AppShortcut(
            intent: AskAboutClipboardIntent(),
            phrases: [
                "Ask \(.applicationName) about the clipboard",
                "问 \(.applicationName) 剪贴板内容",
                "用 \(.applicationName) 问答剪贴板"
            ],
            shortTitle: "Ask Clipboard",
            systemImageName: "clipboard"
        )
        AppShortcut(
            intent: ContinueConversationIntent(),
            phrases: [
                "Continue a conversation in \(.applicationName)",
                "用 \(.applicationName) 继续对话"
            ],
            shortTitle: "Continue Chat",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
