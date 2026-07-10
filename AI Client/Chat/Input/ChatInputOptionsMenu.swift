import SwiftUI
import UIKit

struct ChatInputOptionsMenu<MenuLabel: View>: View {
    let configuration: AIConfiguration
    let agentSkills: [AgentSkill]
    let mcpServers: [MCPServerConfiguration]
    let knowledgeBases: [KnowledgeBase]
    let activeKnowledgeBaseIDs: Set<UUID>
    let capabilitySelection: AgentCapabilitySelection
    let onOpenPhotoPicker: () -> Void
    let onOpenCamera: () -> Void
    let onOpenFileImporter: () -> Void
    let onToggleSkill: (UUID) -> Void
    let onToggleMCPServer: (UUID) -> Void
    let onToggleKnowledgeBase: (UUID) -> Void
    let onManageSkills: () -> Void
    let onManageMCPServers: () -> Void
    let onManageKnowledgeBases: () -> Void
    let onSetReasoningEnabled: (Bool) -> Void
    let onSelectReasoningEffort: (ReasoningEffort) -> Void
    let label: () -> MenuLabel

    var body: some View {
        Menu {
            attachmentItems
            Divider()
            knowledgeBaseMenu
            skillMenu
            mcpMenu
            reasoningItems
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizations.string("accessibility.moreInputOptions", defaultValue: "More input options"))
    }

    @ViewBuilder
    private var attachmentItems: some View {
        Button {
            onOpenPhotoPicker()
        } label: {
            Label(
                configuration.selectedModelSupportsImages
                    ? AppLocalizations.string("input.uploadImage", defaultValue: "Upload Image")
                    : AppLocalizations.string("input.imageUnsupported", defaultValue: "Current model does not support images"),
                systemImage: "photo"
            )
        }
        .disabled(!configuration.selectedModelSupportsImages)

        Button {
            onOpenCamera()
        } label: {
            Label(
                AppLocalizations.string("input.takePhoto", defaultValue: "Take Photo"),
                systemImage: "camera"
            )
        }
        .disabled(!configuration.selectedModelSupportsImages || !CameraCaptureViewController.isAvailable)

        Button {
            onOpenFileImporter()
        } label: {
            Label("上传文件", systemImage: "doc")
        }
    }

    private var skillMenu: some View {
        Menu {
            if agentSkills.isEmpty {
                Text("没有可用 Skill")
            } else {
                ForEach(agentSkills) { skill in
                    Button {
                        onToggleSkill(skill.id)
                    } label: {
                        if capabilitySelection.containsSkill(skill.id) {
                            Label(skill.displayName, systemImage: "checkmark")
                        } else {
                            Label(skill.displayName, systemImage: "wand.and.sparkles")
                        }
                    }
                }
            }

            Button {
                onManageSkills()
            } label: {
                Label("管理 Skills", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Agent Skills", systemImage: "wand.and.sparkles")
        }
    }

    private var knowledgeBaseMenu: some View {
        Menu {
            if knowledgeBases.isEmpty {
                Text("没有可用知识库")
            } else {
                ForEach(knowledgeBases) { knowledgeBase in
                    Button {
                        onToggleKnowledgeBase(knowledgeBase.id)
                    } label: {
                        let title = knowledgeBase.needsReindex
                            ? "\(knowledgeBase.name)（需要重建）"
                            : knowledgeBase.name
                        if activeKnowledgeBaseIDs.contains(knowledgeBase.id) {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Label(title, systemImage: "cylinder.split.1x2")
                        }
                    }
                    .disabled(
                        !activeKnowledgeBaseIDs.contains(knowledgeBase.id)
                            && (knowledgeBase.needsReindex || knowledgeBase.indexedChunkCount == 0)
                    )
                }
            }

            Button {
                onManageKnowledgeBases()
            } label: {
                Label("管理知识库", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("知识库", systemImage: "cylinder.split.1x2")
        }
    }

    private var mcpMenu: some View {
        Menu {
            if mcpServers.isEmpty {
                Text("没有可用 MCP")
            } else {
                ForEach(mcpServers) { server in
                    Button {
                        onToggleMCPServer(server.id)
                    } label: {
                        if capabilitySelection.containsMCPServer(server.id) {
                            Label(server.name, systemImage: "checkmark")
                        } else {
                            Label(
                                server.name,
                                systemImage: server.kind == .tavily
                                    ? "globe"
                                    : "point.3.connected.trianglepath.dotted"
                            )
                        }
                    }
                }
            }

            Button {
                onManageMCPServers()
            } label: {
                Label("管理 MCP", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("MCP 工具", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    @ViewBuilder
    private var reasoningItems: some View {
        if configuration.selectedModelSupportsReasoning {
            Divider()

            Button {
                onSetReasoningEnabled(false)
            } label: {
                if configuration.reasoningEnabled {
                    Text(AppLocalizations.string("reasoning.menu.off", defaultValue: "Reasoning: Off"))
                } else {
                    Label(
                        AppLocalizations.string("reasoning.menu.off", defaultValue: "Reasoning: Off"),
                        systemImage: "checkmark"
                    )
                }
            }

            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    onSelectReasoningEffort(effort)
                } label: {
                    if configuration.reasoningEnabled,
                       effort == configuration.reasoningEffort {
                        Label(reasoningTitle(for: effort), systemImage: "checkmark")
                    } else {
                        Text(reasoningTitle(for: effort))
                    }
                }
            }
        }
    }

    private func reasoningTitle(for effort: ReasoningEffort) -> String {
        AppLocalizations.format(
            "reasoning.menu.effort",
            defaultValue: "Reasoning: %@",
            arguments: [effort.title]
        )
    }
}
