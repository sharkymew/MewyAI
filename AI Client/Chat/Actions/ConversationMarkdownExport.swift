import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ConversationMarkdownDocument: FileDocument {
    static let contentType = UTType(filenameExtension: "md") ?? .plainText
    static var readableContentTypes: [UTType] { [contentType] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            self.text = ""
            return
        }

        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum ConversationMarkdownExporter {
    static func markdown(for conversation: AIConversation) -> String {
        var parts: [String] = [
            "# \(displayTitle(for: conversation))",
            "",
            AppLocalizations.format(
                "markdown.createdAt",
                defaultValue: "- Created: %@",
                arguments: [formattedDate(conversation.createdAt)]
            ),
            AppLocalizations.format(
                "markdown.updatedAt",
                defaultValue: "- Updated: %@",
                arguments: [formattedDate(conversation.updatedAt)]
            ),
            AppLocalizations.format(
                "markdown.messageCount",
                defaultValue: "- Messages: %d",
                arguments: [conversation.messages.count]
            ),
            ""
        ]

        guard !conversation.messages.isEmpty else {
            parts.append(AppLocalizations.string("markdown.emptyConversation", defaultValue: "(Empty conversation)"))
            parts.append("")
            return parts.joined(separator: "\n")
        }

        for (index, message) in conversation.messages.enumerated() {
            parts.append("## \(index + 1). \(displayName(for: message.role))")
            parts.append("")

            appendAttachmentSummary(for: message, to: &parts)
            appendReasoning(for: message, to: &parts)

            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(content.isEmpty
                ? AppLocalizations.string("markdown.emptyContent", defaultValue: "(Empty content)")
                : message.content)

            appendKnowledgeSources(for: message, to: &parts)

            if message.isStopped {
                parts.append("")
                parts.append(AppLocalizations.string("markdown.stoppedBlockquote", defaultValue: "> Generation stopped"))
            }

            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    static func defaultFileName(for conversation: AIConversation) -> String {
        let baseName = sanitizedFileName(from: displayTitle(for: conversation))
        let fallbackName = baseName.isEmpty
            ? AppLocalizations.string("markdown.fileName.fallback", defaultValue: "Conversation")
            : baseName
        return "\(fallbackName)-\(fileDateString(conversation.updatedAt))"
    }

    private static func displayTitle(for conversation: AIConversation) -> String {
        let title = conversation.title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            ? AppLocalizations.string("conversation.newTitle", defaultValue: "New Chat")
            : title
    }

    private static func appendAttachmentSummary(for message: ChatMessage, to parts: inout [String]) {
        guard !message.imageAttachments.isEmpty
                || !message.fileAttachments.isEmpty
                || !message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        parts.append(AppLocalizations.string("markdown.attachmentsHeading", defaultValue: "**Attachments**"))
        parts.append("")

        for (index, attachment) in message.imageAttachments.enumerated() {
            let name = attachment.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if let name, !name.isEmpty {
                displayName = name
            } else {
                displayName = AppLocalizations.format(
                    "markdown.imageFallbackName",
                    defaultValue: "Image %d",
                    arguments: [index + 1]
                )
            }
            parts.append(AppLocalizations.format(
                "markdown.imageAttachmentLine",
                defaultValue: "- Image: %@ (%@, %@)",
                arguments: [displayName, attachment.mimeType, formattedByteCount(attachment.byteCount)]
            ))
        }

        let imageDescription = message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !imageDescription.isEmpty {
            parts.append(AppLocalizations.format(
                "markdown.imageDescriptionLine",
                defaultValue: "- Image description: %@",
                arguments: [imageDescription]
            ))
        }

        for attachment in message.fileAttachments {
            var details = AppLocalizations.format(
                "markdown.fileDetails",
                defaultValue: "%@, %d characters",
                arguments: [formattedByteCount(attachment.byteCount), attachment.characterCount]
            )
            if attachment.isTruncated {
                details += AppLocalizations.string("markdown.fileTruncatedSuffix", defaultValue: ", truncated")
            }
            parts.append(AppLocalizations.format(
                "markdown.fileAttachmentLine",
                defaultValue: "- File: %@ (%@)",
                arguments: [attachment.name, details]
            ))
        }

        parts.append("")
    }

    private static func appendReasoning(for message: ChatMessage, to parts: inout [String]) {
        let reasoning = reasoningText(for: message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reasoning.isEmpty else { return }

        parts.append("<details>")
        parts.append(AppLocalizations.string("markdown.reasoningSummary", defaultValue: "<summary>Reasoning</summary>"))
        parts.append("")
        parts.append(reasoning)
        parts.append("")
        parts.append("</details>")
        parts.append("")
    }

    private static func appendKnowledgeSources(for message: ChatMessage, to parts: inout [String]) {
        guard !message.knowledgeCitations.isEmpty else { return }
        parts.append("")
        parts.append("**知识来源**")
        parts.append("")
        for (index, citation) in message.knowledgeCitations.enumerated() {
            let location = citation.location.isEmpty ? "" : " · \(citation.location)"
            parts.append("- [KB:\(index + 1)] \(citation.knowledgeBaseName) · \(citation.documentName)\(location)")
        }
    }

    private static func reasoningText(for message: ChatMessage) -> String {
        if !message.reasoningContent.isEmpty {
            return message.reasoningContent
        }

        return message.reasoningChunks.joined()
    }

    private static func displayName(for role: String) -> String {
        switch role {
        case "user":
            return AppLocalizations.string("chat.role.user", defaultValue: "User")
        case "assistant":
            return AppLocalizations.string("chat.role.assistant", defaultValue: "Assistant")
        case "system":
            return AppLocalizations.string("chat.role.system", defaultValue: "System")
        default:
            return role
        }
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func fileDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: date)
    }

    private static func formattedByteCount(_ byteCount: Int) -> String {
        guard byteCount > 0 else {
            return AppLocalizations.string("file.unknownSize", defaultValue: "Unknown size")
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private static func sanitizedFileName(from title: String) -> String {
        var fileName = title
        for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"] {
            fileName = fileName.replacingOccurrences(of: character, with: "-")
        }
        fileName = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)

        guard fileName.count > 80 else { return fileName }
        return String(fileName.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
