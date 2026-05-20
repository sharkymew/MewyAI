import SwiftUI

struct ConversationSidebarView: View {
    let conversations: [AIConversation]
    let selectedConversationID: UUID?
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onDelete: (UUID) -> Void
    let canCreateConversation: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("对话")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onCreate) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(!canCreateConversation)
            }
            .padding()
            
            Divider()
            
            GeometryReader { geometry in
                let rowWidth = max(0, geometry.size.width - 16)
                
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(conversations) { conversation in
                            conversationRow(conversation, rowWidth: rowWidth)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(.regularMaterial)
    }
    
    private func conversationRow(_ conversation: AIConversation, rowWidth: CGFloat) -> some View {
        let isSelected = conversation.id == selectedConversationID
        
        return HStack(spacing: 8) {
            Button {
                onSelect(conversation.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    
                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button(role: .destructive) {
                onDelete(conversation.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0.64)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(width: rowWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipped()
    }
}
