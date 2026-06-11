import SwiftUI

struct ChatMemorySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ChatMemoryStore.memoryEnabledKey)
    private var isGlobalMemoryEnabled = ChatMemoryStore.defaultMemoryEnabled
    @State private var entries = ChatMemoryStore.loadEntries()
    @State private var isClearConfirmationPresented = false

    private var sortedEntries: [ChatMemoryEntry] {
        entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                toggleSection
                entriesSection
            }
            .navigationTitle("全局记忆")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                entries = ChatMemoryStore.loadEntries()
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
                    entries = []
                    ChatMemoryStore.clearEntries()
                }
            } message: {
                Text("已保存的记忆会全部删除，且无法恢复。")
            }
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle("启用全局记忆", isOn: $isGlobalMemoryEnabled)
        } footer: {
            Text("开启后，每次对话完成都会用当前模型在后台提取值得长期记住的信息，并注入到之后的所有对话中（不分配置和模型）。临时聊天不会读取或写入记忆。")
        }
    }

    private var entriesSection: some View {
        Section {
            if sortedEntries.isEmpty {
                Text("暂无记忆。和 AI 聊聊你自己、你的偏好或正在做的事，记忆会自动积累。")
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

    private func deleteEntries(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { sortedEntries[$0].id })
        entries.removeAll { removedIDs.contains($0.id) }
        ChatMemoryStore.saveEntries(entries)
    }
}

#Preview {
    ChatMemorySettingsView()
}
