import SwiftUI

struct ChatMemorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ChatMemoryStore.memoryEnabledKey)
    private var isGlobalMemoryEnabled = ChatMemoryStore.defaultMemoryEnabled
    @AppStorage(ChatMemoryStore.historyRecallEnabledKey)
    private var isHistoryRecallEnabled = ChatMemoryStore.defaultHistoryRecallEnabled

    @State private var configurations = AIConfigurationStore.loadConfigurations()
    @State private var selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
    @State private var entries = ChatMemoryStore.loadEntries()
    @State private var summarySections: [ChatMemorySummarySection] = []
    @State private var isGeneratingSummary = false
    @State private var summaryError: String?
    @State private var memoryManagementInput = ""
    @State private var isProposingOperations = false
    @State private var proposalMessage: String?
    @State private var pendingProposal: MemoryOperationProposal?
    @State private var isClearConfirmationPresented = false
    @State private var summaryRequestToken = UUID()
    @State private var proposalRequestToken = UUID()

    private let auxiliaryAIService = ChatAuxiliaryAIService()

    private var sortedEntries: [ChatMemoryEntry] {
        entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var currentConfiguration: AIConfiguration {
        AIConfigurationStore.selectedConfiguration(
            from: configurations,
            selectedID: selectedConfigurationID
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                toggleSection
                summarySection
                memoryManagementSection
                proposalSection
                entriesSection
            }
            .navigationTitle("全局记忆")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                reloadState()
                generateMemorySummary()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "清空所有记忆？",
                isPresented: $isClearConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("清空所有记忆", role: .destructive) {
                    clearAllMemories()
                }
            } message: {
                Text("已保存的记忆会全部删除，且无法恢复。")
            }
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle("启用全局记忆", isOn: $isGlobalMemoryEnabled)
            Toggle("参考历史对话", isOn: $isHistoryRecallEnabled)
        } footer: {
            Text("全局记忆：每次对话完成后用当前模型在后台提取值得长期记住的信息，注入到之后的所有对话（不分配置和模型）。\n参考历史对话：为支持工具调用的模型提供搜索和查阅全部历史对话的工具，模型在需要时自行调用，不需要先保存记忆；Vertex Express 与不支持工具的模型自动不启用。\n临时聊天不参与两者，也不会被检索到。")
        }
    }

    private var summarySection: some View {
        Section {
            if entries.isEmpty {
                Text("暂无记忆。和 AI 聊聊你自己、你的偏好或正在做的事，记忆会自动积累。")
                    .foregroundStyle(.secondary)
            } else {
                if isGeneratingSummary, summarySections.isEmpty {
                    ProgressView("正在用当前模型整理记忆…")
                }

                if !summarySections.isEmpty {
                    ForEach(summarySections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                            MemorySummarySelectableTextView(text: section.body) { selectedText in
                                proposeForgettingSelectedSummary(selectedText)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let summaryError {
                    Text(summaryError)
                        .foregroundStyle(.secondary)
                }

                Button {
                    generateMemorySummary()
                } label: {
                    Label(
                        isGeneratingSummary ? "正在重新生成摘要" : "重新生成摘要",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isGeneratingSummary)
            }
        } header: {
            Text("最新摘要")
        } footer: {
            if !entries.isEmpty {
                Text("进入此页面会用当前选用的模型重新整理已有记忆。选中摘要中的一段文字后，可在长按菜单里选择“不再提到”。")
            }
        }
    }

    private var memoryManagementSection: some View {
        Section {
            TextField("告诉 AI 你想怎样更新记忆", text: $memoryManagementInput, axis: .vertical)
                .lineLimit(2...5)

            Button {
                proposeMemoryManagementInstruction()
            } label: {
                Label("生成变更预览", systemImage: "sparkles")
            }
            .disabled(
                isProposingOperations
                    || memoryManagementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if isProposingOperations {
                ProgressView("正在分析记忆变更…")
            }

            if let proposalMessage {
                Text(proposalMessage)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("通过对话更新")
        } footer: {
            Text("这里的对话只用于管理记忆，不会保存到聊天历史，也不会触发自动记忆提取。")
        }
    }

    @ViewBuilder
    private var proposalSection: some View {
        if let pendingProposal {
            Section {
                ForEach(proposalPreviewRows(for: pendingProposal)) { row in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                            if !row.detail.isEmpty {
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(row.tint)
                    }
                }

                HStack {
                    Button("取消") {
                        self.pendingProposal = nil
                    }
                    Spacer()
                    Button("应用变更") {
                        applyPendingProposal()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("待应用的变更")
            } footer: {
                Text(pendingProposal.title)
            }
        }
    }

    private var entriesSection: some View {
        Section {
            if sortedEntries.isEmpty {
                Text("暂无已保存的原始记忆。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.content)
                        Text(entry.updatedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteEntries)

                Button(role: .destructive) {
                    isClearConfirmationPresented = true
                } label: {
                    Label("清空所有记忆", systemImage: "trash")
                }
            }
        } header: {
            Text("已保存的记忆")
        } footer: {
            if !sortedEntries.isEmpty {
                Text("左滑可删除单条记忆。")
            }
        }
    }

    private func reloadState() {
        configurations = AIConfigurationStore.loadConfigurations()
        selectedConfigurationID = AIConfigurationStore.loadSelectedConfigurationID()
        entries = ChatMemoryStore.loadEntries()
    }

    private func generateMemorySummary() {
        reloadState()
        pendingProposal = nil
        summaryError = nil
        summarySections = []

        guard !entries.isEmpty else {
            isGeneratingSummary = false
            summaryRequestToken = UUID()
            return
        }

        let requestContext: MemoryRequestContext
        switch makeMemoryRequestContext() {
        case let .success(context):
            requestContext = context
        case let .failure(error):
            isGeneratingSummary = false
            summaryError = error
            return
        }

        let requestToken = UUID()
        summaryRequestToken = requestToken
        isGeneratingSummary = true
        let snapshot = entries

        auxiliaryAIService.generateMemorySummary(
            memoryEntries: snapshot,
            baseURL: requestContext.baseURL,
            apiFormat: requestContext.apiFormat,
            apiKey: requestContext.apiKey,
            customHeaders: requestContext.customHeaders,
            model: requestContext.model,
            modelParameters: requestContext.modelParameters,
            anthropicMaxTokens: requestContext.anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: requestContext.anthropicClaudeCodeImpersonationEnabled,
            reasoningEnabled: requestContext.reasoningEnabled,
            reasoningEffort: requestContext.reasoningEffort
        ) { sections in
            guard summaryRequestToken == requestToken else { return }
            isGeneratingSummary = false

            guard let sections else {
                summaryError = "摘要生成失败。请检查当前配置、模型和网络后重试。"
                return
            }

            summarySections = sections
            summaryError = sections.isEmpty ? "当前记忆还不足以生成可用摘要。" : nil
        }
    }

    private func proposeMemoryManagementInstruction() {
        let instruction = memoryManagementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        requestMemoryOperationProposal(
            title: "根据你的说明更新记忆",
            instruction: instruction
        )
    }

    private func proposeForgettingSelectedSummary(_ selectedText: String) {
        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let instruction = """
        请不再提到下面这段摘要涉及的内容。删除或改写已有记忆中支持这段内容的条目；如果它只是摘要措辞，请只移除对应含义，不要新增禁提规则。

        \(trimmedText)
        """

        requestMemoryOperationProposal(
            title: "不再提到选中的摘要内容",
            instruction: instruction
        )
    }

    private func requestMemoryOperationProposal(
        title: String,
        instruction: String
    ) {
        reloadState()
        pendingProposal = nil
        proposalMessage = nil

        let requestContext: MemoryRequestContext
        switch makeMemoryRequestContext() {
        case let .success(context):
            requestContext = context
        case let .failure(error):
            proposalMessage = error
            return
        }

        let requestToken = UUID()
        proposalRequestToken = requestToken
        isProposingOperations = true
        let snapshot = entries

        auxiliaryAIService.proposeMemoryManagementOperations(
            memoryEntries: snapshot,
            userInstruction: instruction,
            baseURL: requestContext.baseURL,
            apiFormat: requestContext.apiFormat,
            apiKey: requestContext.apiKey,
            customHeaders: requestContext.customHeaders,
            model: requestContext.model,
            modelParameters: requestContext.modelParameters,
            anthropicMaxTokens: requestContext.anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: requestContext.anthropicClaudeCodeImpersonationEnabled,
            reasoningEnabled: requestContext.reasoningEnabled,
            reasoningEffort: requestContext.reasoningEffort
        ) { operations in
            guard proposalRequestToken == requestToken else { return }
            isProposingOperations = false

            guard let operations else {
                proposalMessage = "没有生成可用的记忆变更。请换一种说法或稍后重试。"
                return
            }

            guard !operations.isEmpty else {
                proposalMessage = "模型判断当前不需要修改记忆。"
                return
            }

            pendingProposal = MemoryOperationProposal(
                title: title,
                operations: operations,
                snapshotEntries: snapshot
            )
        }
    }

    private func applyPendingProposal() {
        guard let pendingProposal else { return }

        let currentEntries = ChatMemoryStore.loadEntries()
        let updatedEntries = ChatMemoryStore.applying(
            pendingProposal.operations,
            to: currentEntries,
            snapshotIDs: pendingProposal.snapshotIDs,
            sourceConversationID: nil
        )

        guard ChatMemoryStore.saveEntries(updatedEntries) else {
            proposalMessage = "保存记忆失败。"
            return
        }

        entries = updatedEntries
        self.pendingProposal = nil
        memoryManagementInput = ""
        proposalMessage = "记忆已更新。"
        generateMemorySummary()
    }

    private func clearAllMemories() {
        entries = []
        summarySections = []
        summaryError = nil
        proposalMessage = nil
        pendingProposal = nil
        ChatMemoryStore.clearEntries()
        summaryRequestToken = UUID()
        proposalRequestToken = UUID()
        isGeneratingSummary = false
        isProposingOperations = false
    }

    private func deleteEntries(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { sortedEntries[$0].id })
        entries.removeAll { removedIDs.contains($0.id) }
        ChatMemoryStore.saveEntries(entries)
        pendingProposal = nil
        generateMemorySummary()
    }

    private func makeMemoryRequestContext() -> MemoryRequestContextLoadResult {
        let configuration = currentConfiguration
        let model = configuration.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return .failure("当前配置没有选择模型。")
        }

        let baseURL = configuration.requestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            return .failure("当前配置没有可用的请求地址。")
        }

        let reasoningEnabled = configuration.selectedModelSupportsReasoning
            ? configuration.reasoningEnabled
            : nil

        return .success(MemoryRequestContext(
            baseURL: baseURL,
            apiFormat: configuration.apiFormat,
            apiKey: configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            customHeaders: configuration.customHeaders.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            modelParameters: configuration.selectedModelConfiguration,
            anthropicMaxTokens: configuration.anthropicMaxTokens,
            anthropicClaudeCodeImpersonationEnabled: configuration.anthropicClaudeCodeImpersonationEnabled,
            reasoningEnabled: reasoningEnabled,
            reasoningEffort: reasoningEnabled == true ? configuration.reasoningEffort : nil
        ))
    }

    private func proposalPreviewRows(for proposal: MemoryOperationProposal) -> [MemoryOperationPreviewRow] {
        proposal.operations.enumerated().map { offset, operation in
            switch operation.action {
            case .add:
                return MemoryOperationPreviewRow(
                    id: offset,
                    title: "新增记忆",
                    detail: operation.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    systemImage: "plus.circle",
                    tint: .green
                )
            case .update:
                let original = snapshotEntry(for: operation, in: proposal)?.content ?? "未找到原记忆"
                let updated = operation.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return MemoryOperationPreviewRow(
                    id: offset,
                    title: "修改记忆",
                    detail: "\(original)\n→ \(updated)",
                    systemImage: "pencil.circle",
                    tint: .orange
                )
            case .delete:
                let original = snapshotEntry(for: operation, in: proposal)?.content ?? "未找到原记忆"
                return MemoryOperationPreviewRow(
                    id: offset,
                    title: "删除记忆",
                    detail: original,
                    systemImage: "minus.circle",
                    tint: .red
                )
            }
        }
    }

    private func snapshotEntry(
        for operation: ChatMemoryOperation,
        in proposal: MemoryOperationProposal
    ) -> ChatMemoryEntry? {
        guard let index = operation.index,
              index >= 1,
              index <= proposal.snapshotEntries.count else {
            return nil
        }

        return proposal.snapshotEntries[index - 1]
    }
}

private struct MemoryRequestContext {
    let baseURL: String
    let apiFormat: AIAPIFormat
    let apiKey: String
    let customHeaders: String
    let model: String
    let modelParameters: AIModelConfiguration?
    let anthropicMaxTokens: Int
    let anthropicClaudeCodeImpersonationEnabled: Bool
    let reasoningEnabled: Bool?
    let reasoningEffort: ReasoningEffort?
}

private enum MemoryRequestContextLoadResult {
    case success(MemoryRequestContext)
    case failure(String)
}

private struct MemoryOperationProposal: Identifiable {
    let id = UUID()
    let title: String
    let operations: [ChatMemoryOperation]
    let snapshotEntries: [ChatMemoryEntry]

    var snapshotIDs: [UUID] {
        snapshotEntries.map(\.id)
    }
}

private struct MemoryOperationPreviewRow: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

#Preview {
    ChatMemorySettingsView()
}
