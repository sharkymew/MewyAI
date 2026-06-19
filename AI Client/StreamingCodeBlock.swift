import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct StreamingCodeBlock: View {
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
