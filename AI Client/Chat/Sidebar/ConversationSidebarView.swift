import SwiftUI

private enum ConversationSidebarTimeBucket: CaseIterable, Hashable {
    case today
    case yesterday
    case withinWeek
    case withinMonth
    case older

    var title: String {
        switch self {
        case .today:
            AppLocalizations.string("sidebar.bucket.today", defaultValue: "Today")
        case .yesterday:
            AppLocalizations.string("sidebar.bucket.yesterday", defaultValue: "Yesterday")
        case .withinWeek:
            AppLocalizations.string("sidebar.bucket.withinWeek", defaultValue: "Within a Week")
        case .withinMonth:
            AppLocalizations.string("sidebar.bucket.withinMonth", defaultValue: "Within a Month")
        case .older:
            AppLocalizations.string("sidebar.bucket.older", defaultValue: "Older than a Month")
        }
    }

    static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> ConversationSidebarTimeBucket {
        if calendar.isDateInToday(date) {
            return .today
        }

        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        if date >= oneWeekAgo {
            return .withinWeek
        }

        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        if date >= oneMonthAgo {
            return .withinMonth
        }

        return .older
    }
}

struct ConversationSidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPinnedSectionExpanded = true
    @State private var expandedTimeBuckets = Set(ConversationSidebarTimeBucket.allCases)
    @State private var isSuppressingRowActions = false
    @State private var rowActionSuppressionResetTask: Task<Void, Never>?
    @State private var searchText = ""

    let conversations: [AIConversation]
    let conversationForSearch: (AIConversation) -> AIConversation
    let searchConversationIDs: (String) -> Set<UUID>?
    let selectedConversationID: UUID?
    let topSafeAreaInset: CGFloat
    let onSelect: (UUID) -> Void
    let onOpenConfiguration: () -> Void
    let onRename: (UUID) -> Void
    let onTogglePinned: (UUID) -> Void
    let onExport: (UUID) -> Void
    let onDelete: (UUID) -> Void

    private let topControlSize: CGFloat = 44
    private let topControlsTopPadding: CGFloat = 8
    private let topControlsHorizontalPadding: CGFloat = 16
    private let searchBarHeight: CGFloat = 38
    private let searchBarTopGap: CGFloat = 10
    private let topFadeBottomPadding: CGFloat = 155
    private let topFadeVerticalOffset: CGFloat = -55
    private let topGlassFadeExclusionInset: CGFloat = 8
    private let rowActionSuppressionMinimumDistance: CGFloat = 10
    private let rowActionSuppressionHorizontalRatio: CGFloat = 1.2
    private let rowActionSuppressionResetDelayNanoseconds: UInt64 = 180_000_000

    private var glassTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.14)
    }

    private var glassHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.26) : Color.white.opacity(0.74)
    }

    private var topFadeTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.36) : Color.white.opacity(0.56)
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if colorScheme == .dark {
            Color.clear
        } else {
            Color.white.opacity(0.94)
        }
    }

    private var topFadeHeight: CGFloat {
        topControlsTopPadding + topControlSize + topFadeBottomPadding
    }

    private func topScrollContentPadding(topSafeAreaInset: CGFloat) -> CGFloat {
        topSafeAreaInset + topControlsTopPadding + topControlSize + searchBarTopGap + searchBarHeight + 18
    }

    @ViewBuilder
    private var fadeBase: some View {
        if colorScheme == .dark {
            Rectangle()
                .fill(Color.black)
        } else {
            Rectangle()
                .fill(.thickMaterial)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = geometry.size.width
            let rowWidth = max(0, sidebarWidth - 16)

            sidebarContentWithBlurMask(
                sidebarWidth: sidebarWidth,
                sidebarHeight: geometry.size.height,
                rowWidth: rowWidth
            )
        }
        .clipped()
    }

    private func sidebarContentWithBlurMask(sidebarWidth: CGFloat, sidebarHeight: CGFloat, rowWidth: CGFloat) -> some View {
        ZStack(alignment: .top) {
            sidebarBackground
                .allowsHitTesting(false)

            sidebarContent(
                rowWidth: rowWidth,
                topPadding: topScrollContentPadding(topSafeAreaInset: topSafeAreaInset)
            )

            topFadeBackdrop(
                topSafeAreaInset: topSafeAreaInset,
                sidebarWidth: sidebarWidth
            )

            topFloatingControls(topSafeAreaInset: topSafeAreaInset)

            topSearchBar(topSafeAreaInset: topSafeAreaInset)
        }
        .frame(width: sidebarWidth, height: sidebarHeight, alignment: .top)
    }

    private func sidebarContent(rowWidth: CGFloat, topPadding: CGFloat) -> some View {
        let queryTerms = ConversationSearchFilter.queryTerms(from: searchText)
        let isSearching = !queryTerms.isEmpty
        let sortedConversations = sortedConversations()
        let matchingIDs = isSearching ? searchConversationIDs(searchText) : nil
        let visibleConversations = isSearching
            ? sortedConversations.filter {
                if let matchingIDs {
                    return matchingIDs.contains($0.id)
                }
                return ConversationSearchFilter.matches(conversationForSearch($0), queryTerms: queryTerms)
            }
            : sortedConversations
        let pinnedConversations = visibleConversations.filter(\.isPinned)
        let now = Date()

        return ScrollView {
            VStack(spacing: 4) {
                if isSearching, visibleConversations.isEmpty {
                    Text(AppLocalizations.string(
                        "sidebar.search.noResults",
                        defaultValue: "No matching conversations"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                }

                conversationSection(
                    title: AppLocalizations.string("sidebar.section.pinned", defaultValue: "Pinned"),
                    conversations: pinnedConversations,
                    isExpanded: isSearching ? .constant(true) : $isPinnedSectionExpanded,
                    rowWidth: rowWidth
                )

                ForEach(ConversationSidebarTimeBucket.allCases, id: \.self) { bucket in
                    conversationSection(
                        title: bucket.title,
                        conversations: conversations(
                            in: bucket,
                            from: visibleConversations,
                            now: now
                        ),
                        isExpanded: isSearching ? .constant(true) : timeBucketExpansionBinding(for: bucket),
                        rowWidth: rowWidth
                    )
                }
            }
            .padding(8)
            .padding(.top, topPadding)
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(rowActionSuppressionGesture)
    }

    private func topSearchBar(topSafeAreaInset: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                AppLocalizations.string("sidebar.search.placeholder", defaultValue: "Search conversations"),
                text: $searchText
            )
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizations.string(
                    "accessibility.clearConversationSearch",
                    defaultValue: "Clear conversation search"
                ))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: searchBarHeight)
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(glassTint), in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(glassTint))
                    .overlay(
                        Capsule()
                            .stroke(glassHighlight, lineWidth: 1)
                            .blendMode(.screen)
                    )
            }
        }
        .padding(.horizontal, topControlsHorizontalPadding)
        .padding(.top, topSafeAreaInset + topControlsTopPadding + topControlSize + searchBarTopGap)
    }

    private func topFade(topSafeAreaInset: CGFloat) -> some View {
        fadeBase
            .overlay(topFadeTint)
            .mask(
                FunctionOpacityMask(
                    topOpacity: 0.90,
                    maxOpacity: 0.90,
                    fadeInEnd: 0.22,
                    holdEnd: 0.48,
                    fadeOutEnd: 0.88
                )
            )
            .allowsHitTesting(false)
    }

    private func topFadeBackdrop(topSafeAreaInset: CGFloat, sidebarWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            topFade(topSafeAreaInset: topSafeAreaInset)
                .frame(width: sidebarWidth, height: topSafeAreaInset + topFadeHeight)
                .offset(y: topFadeVerticalOffset)
                .ignoresSafeArea(edges: .top)

            Capsule()
                .frame(
                    width: max(topControlSize - topGlassFadeExclusionInset * 2, 0),
                    height: max(topControlSize - topGlassFadeExclusionInset * 2, 0)
                )
                .position(
                    x: sidebarWidth - topControlsHorizontalPadding - topControlSize / 2,
                    y: topSafeAreaInset + topControlsTopPadding + topControlSize / 2
                )
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func topFloatingControls(topSafeAreaInset: CGFloat) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            topGlassControl {
                Button(action: onOpenConfiguration) {
                    topIconLabel(systemName: "slider.horizontal.3")
                }
            }
            .accessibilityLabel(AppLocalizations.string("accessibility.openAIConfiguration", defaultValue: "Open AI configuration"))
        }
        .padding(.horizontal, topControlsHorizontalPadding)
        .padding(.top, topSafeAreaInset + topControlsTopPadding)
    }

    @ViewBuilder
    private func topGlassControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .buttonStyle(
                FixedTopGlassButtonStyle(
                    tint: glassTint,
                    highlight: glassHighlight
                )
            )
    }

    private func topIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: topControlSize, height: topControlSize)
            .contentShape(Circle())
    }

    private var rowActionSuppressionGesture: some Gesture {
        DragGesture(minimumDistance: rowActionSuppressionMinimumDistance)
            .onChanged { value in
                if isHorizontalRowSwipe(value.translation) {
                    rowActionSuppressionResetTask?.cancel()
                    isSuppressingRowActions = true
                }
            }
            .onEnded { value in
                if isHorizontalRowSwipe(value.translation) {
                    isSuppressingRowActions = true
                }

                scheduleRowActionSuppressionReset()
            }
    }

    private func isHorizontalRowSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) >= rowActionSuppressionMinimumDistance
            && abs(translation.width) > abs(translation.height) * rowActionSuppressionHorizontalRatio
    }

    private func scheduleRowActionSuppressionReset() {
        rowActionSuppressionResetTask?.cancel()
        rowActionSuppressionResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: rowActionSuppressionResetDelayNanoseconds)
            guard !Task.isCancelled else { return }
            isSuppressingRowActions = false
            rowActionSuppressionResetTask = nil
        }
    }

    private func sortedConversations() -> [AIConversation] {
        conversations.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private func conversations(
        in bucket: ConversationSidebarTimeBucket,
        from sortedConversations: [AIConversation],
        now: Date
    ) -> [AIConversation] {
        sortedConversations.filter { conversation in
            !conversation.isPinned
                && ConversationSidebarTimeBucket.bucket(for: conversation.updatedAt, now: now) == bucket
        }
    }

    private func timeBucketExpansionBinding(for bucket: ConversationSidebarTimeBucket) -> Binding<Bool> {
        Binding {
            expandedTimeBuckets.contains(bucket)
        } set: { isExpanded in
            if isExpanded {
                expandedTimeBuckets.insert(bucket)
            } else {
                expandedTimeBuckets.remove(bucket)
            }
        }
    }

    @ViewBuilder
    private func conversationSection(
        title: String,
        conversations: [AIConversation],
        isExpanded: Binding<Bool>,
        rowWidth: CGFloat
    ) -> some View {
        if !conversations.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                sectionHeader(
                    title: title,
                    count: conversations.count,
                    isExpanded: isExpanded.wrappedValue,
                    rowWidth: rowWidth
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizations.format(
                "accessibility.conversationSection",
                defaultValue: "%@, %d conversations",
                arguments: [title, conversations.count]
            ))
            .accessibilityValue(isExpanded.wrappedValue
                ? AppLocalizations.string("accessibility.expanded", defaultValue: "Expanded")
                : AppLocalizations.string("accessibility.collapsed", defaultValue: "Collapsed"))

            if isExpanded.wrappedValue {
                VStack(spacing: 4) {
                    ForEach(conversations) { conversation in
                        conversationRow(conversation, rowWidth: rowWidth)
                    }
                }
            }
        }
    }

    private func sectionHeader(
        title: String,
        count: Int,
        isExpanded: Bool,
        rowWidth: CGFloat
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)

            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(width: rowWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func conversationRow(_ conversation: AIConversation, rowWidth: CGFloat) -> some View {
        let isSelected = conversation.id == selectedConversationID

        return Button {
            guard !isSuppressingRowActions else { return }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: rowWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onRename(conversation.id)
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button {
                onTogglePinned(conversation.id)
            } label: {
                Label(
                    conversation.isPinned
                        ? AppLocalizations.string("sidebar.unpin", defaultValue: "Unpin")
                        : AppLocalizations.string("sidebar.pin", defaultValue: "Pin"),
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }

            Button {
                onExport(conversation.id)
            } label: {
                Label("导出为 Markdown", systemImage: "doc.text")
            }

            Button(role: .destructive) {
                guard !isSuppressingRowActions else { return }
                onDelete(conversation.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .clipped()
    }
}
