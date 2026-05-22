import SwiftUI
import UIKit
import MarkdownUI

struct ChatCodeBlock: View {
    let content: String
    let language: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopy = false

    init(configuration: CodeBlockConfiguration) {
        content = configuration.content
        language = configuration.language
    }

    init(content: String, language: String?) {
        self.content = content
        self.language = language
    }

    private var languageName: String {
        let language = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        return language?.isEmpty == false ? language! : "text"
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
                    Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
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
                .accessibilityLabel(didCopy ? "代码已复制" : "复制代码")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(headerColor)

            Divider()
                .opacity(0.55)

            ScrollView(.horizontal, showsIndicators: true) {
                ChatCodeSyntaxHighlighter()
                    .highlightCode(content, language: language)
                    .font(.system(size: 13, design: .monospaced))
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
        .markdownMargin(top: 6, bottom: 12)
    }

    private func copyCode() {
        UIPasteboard.general.string = content
        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }
}
