import SwiftUI

struct KnowledgeBaseManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var manager: KnowledgeBaseManager
    let configurations: [AIConfiguration]

    @State private var newName = ""
    @State private var selectedProviderID: UUID?
    @State private var selectedModelName = ""
    @State private var importTargetID: UUID?
    @State private var isFileImporterPresented = false
    @State private var previewDocument: KnowledgeDocument?
    @State private var renameDrafts: [UUID: String] = [:]
    @State private var pendingKnowledgeBaseDeletionID: UUID?
    @State private var pendingDocumentDeletion: (knowledgeBaseID: UUID, documentID: UUID)?

    private var embeddingProviders: [AIConfiguration] {
        configurations.filter { configuration in
            configuration.embeddingConfiguration?.models.contains(where: { $0.validatedDimensions != nil }) == true
        }
    }

    private var selectedProvider: AIConfiguration? {
        let id = selectedProviderID ?? embeddingProviders.first?.id
        return embeddingProviders.first { $0.id == id }
    }

    private var validatedModels: [AIEmbeddingModelConfiguration] {
        selectedProvider?.embeddingConfiguration?.models.filter { $0.validatedDimensions != nil } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                createSection
                knowledgeBasesSection
                if let statusMessage = manager.statusMessage {
                    Section("状态") {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let progress = manager.progress {
                    Section("索引进度") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(progress.fileName) · \(progress.phase.rawValue)")
                            ProgressView(value: progress.fractionCompleted)
                        }
                        Button("取消", role: .cancel) {
                            manager.cancelWork()
                        }
                    }
                }
            }
            .navigationTitle("知识库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: KnowledgeDocumentProcessor.supportedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                guard let knowledgeBaseID = importTargetID else { return }
                if case .success(let urls) = result {
                    manager.startImportFiles(
                        urls,
                        into: knowledgeBaseID,
                        configurations: configurations
                    )
                } else if case .failure(let error) = result {
                    manager.statusMessage = error.localizedDescription
                }
                importTargetID = nil
            }
            .sheet(item: $previewDocument) { document in
                NavigationStack {
                    ScrollView {
                        Text(document.extractedText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(document.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .confirmationDialog(
                "删除这个知识库？",
                isPresented: deletionConfirmationBinding(for: .knowledgeBase),
                titleVisibility: .visible
            ) {
                Button("删除知识库", role: .destructive) {
                    if let id = pendingKnowledgeBaseDeletionID {
                        manager.delete(id)
                    }
                    pendingKnowledgeBaseDeletionID = nil
                }
            } message: {
                Text("本机保存的抽取文本、分块和向量会一并删除，原始文件不受影响。")
            }
            .confirmationDialog(
                "删除这个文件的知识索引？",
                isPresented: deletionConfirmationBinding(for: .document),
                titleVisibility: .visible
            ) {
                Button("删除文件索引", role: .destructive) {
                    if let pendingDocumentDeletion {
                        manager.deleteDocument(
                            pendingDocumentDeletion.documentID,
                            from: pendingDocumentDeletion.knowledgeBaseID
                        )
                    }
                    pendingDocumentDeletion = nil
                }
            } message: {
                Text("本机保存的抽取文本、分块和向量会被删除，原始文件不受影响。")
            }
            .onAppear {
                manager.reload()
                manager.markStaleProfiles(configurations: configurations)
                renameDrafts = Dictionary(uniqueKeysWithValues: manager.knowledgeBases.map { ($0.id, $0.name) })
                normalizeProviderSelection()
            }
            .onChange(of: selectedProviderID) { _, _ in
                selectedModelName = validatedModels.first?.name ?? ""
            }
        }
    }

    private var createSection: some View {
        Section {
            if embeddingProviders.isEmpty {
                Text("请先在 Provider 设置中启用 Embedding、添加模型并完成测试。")
                    .foregroundStyle(.secondary)
            } else {
                TextField("知识库名称", text: $newName)
                Picker("Embedding Provider", selection: providerSelectionBinding) {
                    ForEach(embeddingProviders) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                Picker("Embedding 模型", selection: modelSelectionBinding) {
                    ForEach(validatedModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                Button {
                    createKnowledgeBase()
                } label: {
                    if manager.isWorking {
                        ProgressView()
                    } else {
                        Label("创建知识库", systemImage: "plus")
                    }
                }
                .disabled(manager.isWorking || selectedProvider == nil || selectedModelName.isEmpty)
            }
        } header: {
            Text("新建")
        } footer: {
            Text("文件内容会发送给所选 Embedding Provider。聊天引用时，召回片段会发送给当前聊天 Provider。")
        }
    }

    private var knowledgeBasesSection: some View {
        Section("知识库") {
            if manager.knowledgeBases.isEmpty {
                Text("还没有知识库。")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.knowledgeBases) { knowledgeBase in
                DisclosureGroup {
                    HStack {
                        TextField(
                            "知识库名称",
                            text: Binding(
                                get: { renameDrafts[knowledgeBase.id] ?? knowledgeBase.name },
                                set: { renameDrafts[knowledgeBase.id] = $0 }
                            )
                        )
                        Button("保存") {
                            manager.rename(
                                knowledgeBase.id,
                                to: renameDrafts[knowledgeBase.id] ?? knowledgeBase.name
                            )
                        }
                        .disabled(manager.isWorking)
                    }

                    if knowledgeBase.documents.isEmpty {
                        Text("尚未导入文件。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(knowledgeBase.documents) { document in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                previewDocument = KnowledgeBaseStore.loadDocument(
                                    knowledgeBaseID: knowledgeBase.id,
                                    documentID: document.id
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.name)
                                    Text(documentSummary(document))
                                        .font(.caption)
                                        .foregroundStyle(document.status == .failed ? Color.red : Color.secondary)
                                }
                            }
                            .disabled(document.extractedText.isEmpty && document.chunks.isEmpty)

                            if let errorMessage = document.errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            HStack {
                                if document.status == .failed {
                                    if document.chunks.isEmpty {
                                        Button("重新选择并重试") {
                                            importTargetID = knowledgeBase.id
                                            isFileImporterPresented = true
                                        }
                                    } else {
                                        Button("重试 Embedding") {
                                            manager.startRetryDocument(
                                                document.id,
                                                in: knowledgeBase.id,
                                                configurations: configurations
                                            )
                                        }
                                    }
                                }
                                Button("删除", role: .destructive) {
                                    pendingDocumentDeletion = (knowledgeBase.id, document.id)
                                }
                            }
                            .font(.caption)
                        }
                    }

                    Button {
                        importTargetID = knowledgeBase.id
                        isFileImporterPresented = true
                    } label: {
                        Label("导入文件", systemImage: "doc.badge.plus")
                    }
                    .disabled(manager.isWorking)

                    Menu {
                        ForEach(embeddingProviders) { provider in
                            if let embedding = provider.embeddingConfiguration {
                                Menu(provider.name) {
                                    ForEach(embedding.models.filter { $0.validatedDimensions != nil }) { model in
                                        Button(model.displayName) {
                                            manager.startRebuild(
                                                knowledgeBase.id,
                                                provider: provider,
                                                embeddingConfiguration: embedding,
                                                model: model
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("更换 Embedding 配置并重建", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(manager.isWorking || knowledgeBase.documents.isEmpty)

                    Button(role: .destructive) {
                        pendingKnowledgeBaseDeletionID = knowledgeBase.id
                    } label: {
                        Label("删除知识库", systemImage: "trash")
                    }
                    .disabled(manager.isWorking)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(knowledgeBase.name)
                        Text("\(knowledgeBase.documents.count) 个文件 · \(knowledgeBase.indexedChunkCount) 分块 · \(knowledgeBase.profile.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if knowledgeBase.needsReindex {
                            Text("需要重建")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var providerSelectionBinding: Binding<UUID> {
        Binding(
            get: { selectedProviderID ?? embeddingProviders.first?.id ?? UUID() },
            set: { selectedProviderID = $0 }
        )
    }

    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: { selectedModelName.isEmpty ? validatedModels.first?.name ?? "" : selectedModelName },
            set: { selectedModelName = $0 }
        )
    }

    private func normalizeProviderSelection() {
        if selectedProvider == nil {
            selectedProviderID = embeddingProviders.first?.id
        }
        if !validatedModels.contains(where: { $0.name == selectedModelName }) {
            selectedModelName = validatedModels.first?.name ?? ""
        }
    }

    private func createKnowledgeBase() {
        guard let provider = selectedProvider,
              let embedding = provider.embeddingConfiguration,
              let model = validatedModels.first(where: { $0.name == selectedModelName }) else {
            return
        }
        Task {
            do {
                try await manager.create(
                    name: newName,
                    provider: provider,
                    embeddingConfiguration: embedding,
                    model: model
                )
                newName = ""
                manager.statusMessage = "知识库已创建。"
            } catch {
                manager.statusMessage = error.localizedDescription
            }
        }
    }

    private func documentSummary(_ document: KnowledgeDocument) -> String {
        switch document.status {
        case .indexed:
            return "\(document.characterCount) 字符 · \(document.chunks.count) 分块"
        case .failed:
            return "索引失败"
        case .pending, .extracting, .embedding:
            return document.status.rawValue
        }
    }

    private enum DeletionKind {
        case knowledgeBase
        case document
    }

    private func deletionConfirmationBinding(for kind: DeletionKind) -> Binding<Bool> {
        Binding(
            get: {
                switch kind {
                case .knowledgeBase:
                    return pendingKnowledgeBaseDeletionID != nil
                case .document:
                    return pendingDocumentDeletion != nil
                }
            },
            set: { isPresented in
                guard !isPresented else { return }
                switch kind {
                case .knowledgeBase:
                    pendingKnowledgeBaseDeletionID = nil
                case .document:
                    pendingDocumentDeletion = nil
                }
            }
        )
    }
}
