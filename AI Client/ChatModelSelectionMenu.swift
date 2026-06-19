import SwiftUI

struct ChatModelSelectionMenu<MenuLabel: View>: View {
    let configuration: AIConfiguration
    let conversationUsageSummaryText: String?
    let includesPromptSettings: Bool
    let isDisabled: Bool
    let onSelectModel: (String) -> Void
    let onOpenConfiguration: () -> Void
    let onOpenPromptSettings: () -> Void
    let label: () -> MenuLabel

    var body: some View {
        Menu {
            if let conversationUsageSummaryText {
                Section(AppLocalizations.string("chat.usage.conversationSectionTitle", defaultValue: "Usage in this chat")) {
                    Text(conversationUsageSummaryText)
                }
            }

            modelChoiceMenuItems
            Divider()

            if includesPromptSettings {
                Button {
                    onOpenPromptSettings()
                } label: {
                    Label("提示词设置", systemImage: "text.quote")
                }
            }

            Button {
                onOpenConfiguration()
            } label: {
                Label("管理模型", systemImage: "slider.horizontal.3")
            }
        } label: {
            label()
        }
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var modelChoiceMenuItems: some View {
        ForEach(configuration.models) { model in
            Button {
                onSelectModel(model.name)
            } label: {
                if model.name == configuration.selectedModel {
                    Label(model.displayName, systemImage: "checkmark")
                } else {
                    Text(model.displayName)
                }
            }
        }
    }
}

struct ChatModelTitleMenuLabel: View {
    let title: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: width - 38, alignment: .center)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
    }
}
