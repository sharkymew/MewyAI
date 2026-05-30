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
            "- 创建时间：\(formattedDate(conversation.createdAt))",
            "- 更新时间：\(formattedDate(conversation.updatedAt))",
            "- 消息数：\(conversation.messages.count)",
            ""
        ]

        guard !conversation.messages.isEmpty else {
            parts.append("（空对话）")
            parts.append("")
            return parts.joined(separator: "\n")
        }

        for (index, message) in conversation.messages.enumerated() {
            parts.append("## \(index + 1). \(displayName(for: message.role))")
            parts.append("")

            appendAttachmentSummary(for: message, to: &parts)
            appendReasoning(for: message, to: &parts)

            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(content.isEmpty ? "（空内容）" : message.content)

            if message.isStopped {
                parts.append("")
                parts.append("> 已停止生成")
            }

            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    static func defaultFileName(for conversation: AIConversation) -> String {
        let baseName = sanitizedFileName(from: displayTitle(for: conversation))
        let fallbackName = baseName.isEmpty ? "对话" : baseName
        return "\(fallbackName)-\(fileDateString(conversation.updatedAt))"
    }

    private static func displayTitle(for conversation: AIConversation) -> String {
        let title = conversation.title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "新对话" : title
    }

    private static func appendAttachmentSummary(for message: ChatMessage, to parts: inout [String]) {
        guard !message.imageAttachments.isEmpty
                || !message.fileAttachments.isEmpty
                || !message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        parts.append("**附件**")
        parts.append("")

        for (index, attachment) in message.imageAttachments.enumerated() {
            let name = attachment.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName: String
            if let name, !name.isEmpty {
                displayName = name
            } else {
                displayName = "图片 \(index + 1)"
            }
            parts.append("- 图片：\(displayName)（\(attachment.mimeType)，\(formattedByteCount(attachment.byteCount))）")
        }

        let imageDescription = message.imageContextDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !imageDescription.isEmpty {
            parts.append("- 图片描述：\(imageDescription)")
        }

        for attachment in message.fileAttachments {
            var details = "\(formattedByteCount(attachment.byteCount))，\(attachment.characterCount) 字"
            if attachment.isTruncated {
                details += "，已截断"
            }
            parts.append("- 文件：\(attachment.name)（\(details)）")
        }

        parts.append("")
    }

    private static func appendReasoning(for message: ChatMessage, to parts: inout [String]) {
        let reasoning = reasoningText(for: message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reasoning.isEmpty else { return }

        parts.append("<details>")
        parts.append("<summary>推理</summary>")
        parts.append("")
        parts.append(reasoning)
        parts.append("")
        parts.append("</details>")
        parts.append("")
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
            return "用户"
        case "assistant":
            return "助手"
        case "system":
            return "系统"
        default:
            return role
        }
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
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
        guard byteCount > 0 else { return "未知大小" }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private static func sanitizedFileName(from title: String) -> String {
        var fileName = title
        for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"] {
            fileName = fileName.replacingOccurrences(of: character, with: "-")
        }
        fileName = fileName
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard fileName.count > 80 else { return fileName }
        return String(fileName.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
