import CoreKit
import MirrorKit
import SwiftUI

/// Inbox Reference 三栏主壳（JOURNEY-008/010/024 · DESIGN-003/004/005）。
/// 原生 NavigationSplitView + 列表搜索/筛选 + 阅读区快速回复。
public struct MailoShell: View {
    @ObservedObject var root: MailoRootModel
    @State private var selection: String?
    @State private var searchText = ""
    @State private var segment = SegmentSnapshot.defaultSegment
    @State private var quickReplyStore = QuickReplyStore()
    @State private var replyFocusRequest = 0
    @FocusState private var searchFocused: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openWindow) private var openWindow

    /// 便捷入口（测试/预览）：单模型直接成壳。
    public init(model: MailoAppModel) {
        self.root = MailoRootModel(live: model)
    }

    /// 测试/预览：以指定邮件直接装配阅读态（JOURNEY-008）。
    init(model: MailoAppModel, initialSelection: String?, initialSegment: Int = SegmentSnapshot.defaultSegment) {
        self.root = MailoRootModel(live: model)
        _selection = State(initialValue: initialSelection)
        _segment = State(initialValue: initialSegment)
    }

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some View {
        MainSurface(
            root: root, selection: $selection,
            searchText: $searchText, searchFocused: $searchFocused, segment: $segment,
            quickReplyStore: $quickReplyStore, replyFocusRequest: $replyFocusRequest,
            columnVisibility: $columnVisibility, sizeClass: sizeClass ?? .regular,
            openWindow: openWindow
        )
        .mailoAppearance()
        .preferredColorScheme(MailoReferenceTheme.colorScheme)
        .onChange(of: root.demo != nil) { _ in prepareDemo() }
        .onAppear { prepareDemo() }
    }

    /// Demo 切换由最外层壳处理，避免 MainSurface 已挂载时收不到首次 onAppear。
    private func prepareDemo() {
        selection = nil
        searchText = ""
        quickReplyStore = QuickReplyStore()
        guard let demo = root.demo else { return }
        guard let target = demo.entries.first(where: { $0.subject?.contains("Visual Design") == true })
                ?? demo.entries.first else { return }
        selection = target.stableId
        quickReplyStore.setText(L10n.t("quickReply.referenceDraft"), for: target.stableId)
    }
}

/// 实际表面；live/demo 切换时整体重建，列表筛选与回复草稿由壳层保留。
private struct MainSurface: View {
    @ObservedObject var root: MailoRootModel
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @Binding var searchText: String
    @FocusState.Binding var searchFocused: Bool
    @Binding var segment: Int
    @Binding var quickReplyStore: QuickReplyStore
    @Binding var replyFocusRequest: Int
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sizeClass: UserInterfaceSizeClass
    let openWindow: OpenWindowAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(root: MailoRootModel, selection: Binding<String?>,
         searchText: Binding<String>, searchFocused: FocusState<Bool>.Binding, segment: Binding<Int>,
         quickReplyStore: Binding<QuickReplyStore>, replyFocusRequest: Binding<Int>,
         columnVisibility: Binding<NavigationSplitViewVisibility>, sizeClass: UserInterfaceSizeClass,
         openWindow: OpenWindowAction) {
        self.root = root
        self.model = root.active
        _selection = selection
        _searchText = searchText
        _searchFocused = searchFocused
        _segment = segment
        _quickReplyStore = quickReplyStore
        _replyFocusRequest = replyFocusRequest
        _columnVisibility = columnVisibility
        self.sizeClass = sizeClass
        self.openWindow = openWindow
    }

    var body: some View {
        Group {
            switch model.phase {
            case .demo, .connected:
                if sizeClass == .compact {
                    compactLayout
                } else {
                    wideLayout
                }
            case .empty, .connecting, .failed:
                AccountSetupView(root: root)
            }
        }
        #if os(iOS)
        .sheet(item: $root.composeDraft) { draft in
            ComposeView(model: model, draft: draft, onDismiss: { root.composeDraft = nil })
        }
        #endif
        .onChange(of: model.commandRequest) { request in
            guard let request else { return }
            handle(request.command)
        }
        .onChange(of: selection) { model.setReading($0) }
        .onChange(of: model.selectedBucket) { _ in selection = nil }
    }

    private func handle(_ command: MailoUICommand) {
        switch command {
        case .compose:
            openCompose(ComposeDraft())
        case .reply:
            if model.readingStableId != nil { replyFocusRequest += 1 }
        case .forward:
            if let id = model.readingStableId {
                openCompose(model.composeDraft(for: id, kind: .forward) ?? ComposeDraft(kind: .forward))
            }
        case .setAside:
            if let id = model.readingStableId { try? model.setAside(stableId: id) }
        case .toggleUnread:
            if let id = model.readingStableId { model.toggleUnread(stableId: id) }
        case .delete:
            // JOURNEY-022：删除后选中移到相邻邮件（next 优先、末位回退），无相邻回占位。
            if let id = model.readingStableId {
                let visible = searchText.isEmpty ? model.entries : model.searchResults.map {
                    BucketEntry(stableId: $0.stableId, bucket: "search", flags: $0.flags)
                }
                let replacement = MailSelectionBridge(entries: visible).replacement(after: id)
                try? model.delete(stableId: id)
                selection = replacement
            }
        case .focusSearch:
            searchFocused = true
        }
    }

    private func openCompose(_ draft: ComposeDraft) {
        root.composeDraft = draft
        #if os(macOS)
        openWindow(id: "compose")
        #endif
    }

    private func openFullReply() {
        guard let id = selection else { return }
        let original = model.composeDraft(for: id, kind: .reply) ?? ComposeDraft(kind: .reply)
        openCompose(QuickReplyPayload.draft(userText: quickReplyStore.text(for: id), replyingTo: original))
    }

    // MARK: 宽屏三栏

    private var wideLayout: some View {
        GeometryReader { proxy in
            let columns = ReferenceLayout.columns(totalWidth: proxy.size.width)
            HStack(spacing: 0) {
                SidebarView(model: model, root: root, segment: $segment)
                    .frame(width: columns.sidebar, height: proxy.size.height)
                listColumn
                    .frame(width: columns.list, height: proxy.size.height)
                    .background {
                        Rectangle()
                            .fill(DesignTokens.surfaceList)
                            .shadow(color: DesignTokens.shadowColor.opacity(MailElevationSpec.paneOpacity),
                                    radius: MailElevationSpec.paneRadius, x: MailElevationSpec.paneX, y: 0)
                    }
                    .zIndex(1)
                readerPane
                    .frame(width: columns.reader, height: proxy.size.height)
                    .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                             reduceMotion: reduceMotion), value: colorScheme)
                    .background(DesignTokens.surfaceReader)
            }
        }
        .navigationTitle(root.demo == nil ? "Mailo" : "Mailo — Demo")
        #if os(macOS)
        .toolbarBackground(DesignTokens.surfaceToolbar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #else
        .toolbarBackground(DesignTokens.surfaceToolbar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .background(DesignTokens.surfaceToolbar)
    }

    @ViewBuilder
    private var listColumn: some View {
        VStack(spacing: 0) {
            listHeader
            Group {
                if searchText.isEmpty {
                    MailListView(model: model, selection: $selection, segment: $segment)
                } else {
                    SearchResultsView(model: model, selection: $selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .background(DesignTokens.surfaceList)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: model.selectedBucket)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: searchText.isEmpty)
    }

    /// 参考稿列表顶栏：42pt 白色搜索行，无额外筛选或进度面板。
    private var listHeader: some View {
        searchField
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: DesignTokens.titleBarHeight)
            .background {
                Rectangle()
                    .fill(DesignTokens.surfaceCard)
                    .shadow(color: DesignTokens.shadowColor.opacity(MailElevationSpec.headerOpacity),
                            radius: MailElevationSpec.headerRadius, x: 0, y: MailElevationSpec.headerY)
            }
            .zIndex(1)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignTokens.borderHairline).frame(height: 0.5)
            }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(DesignTokens.Typo.iconSmall)
            TextField(L10n.t("toolbar.search.placeholder"), text: $searchText)
                .font(DesignTokens.Typo.caption)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DesignTokens.Typo.iconSmall)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("search.clear"))
            }
        }
        .foregroundColor(DesignTokens.searchMuted)
        .frame(maxWidth: .infinity)
        .frame(height: DesignTokens.searchHeight)
        .background(DesignTokens.surfaceCard)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: searchFocused)
        .onChange(of: searchText) { q in model.searchDebounced(q) }
        #if os(macOS)
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
                model.clearSearch()
            }
        }
        #endif
    }

    @ViewBuilder
    private var readerPane: some View {
        if let selection {
            GeometryReader { proxy in
                MailReaderView(model: model, stableId: selection, viewportHeight: proxy.size.height,
                               viewportWidth: proxy.size.width,
                               quickReplyStore: $quickReplyStore,
                               replyFocusRequest: replyFocusRequest,
                               onExpandReply: openFullReply)
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "envelope.open")
                    .font(DesignTokens.Typo.iconLarge)
                    .foregroundColor(DesignTokens.inkFaint)
                Text(L10n.t("reader.calm"))
                    .font(DesignTokens.Typo.body)
                    .foregroundColor(DesignTokens.inkMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReaderSurface())
        }
    }

    // MARK: 紧凑 iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                listColumn
                if let selection {
                    GeometryReader { proxy in
                        MailReaderView(model: model, stableId: selection, viewportHeight: proxy.size.height,
                                       viewportWidth: proxy.size.width,
                                       quickReplyStore: $quickReplyStore,
                                       replyFocusRequest: replyFocusRequest,
                                       onExpandReply: openFullReply)
                            .overlay(alignment: .topLeading) {
                                Button {
                                    self.selection = nil
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                                .padding(8)
                                .accessibilityLabel(L10n.t("reader.back"))
                            }
                    }
                    .background(ReaderSurface())
                    .transition(reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(DesignTokens.surfaceList)
            .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                     reduceMotion: reduceMotion), value: selection != nil)
            .navigationTitle("Mailo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.surfaceToolbar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { openCompose(ComposeDraft()) } label: { Image(systemName: "square.and.pencil") }
                        .disabled(!model.canCompose)
                        .foregroundColor(DesignTokens.accentDeep)
                        .accessibilityLabel(L10n.t("menu.newMessage"))
                }
                ToolbarItem(placement: .navigation) {
                    Menu {
                        ForEach(Bucket.navBuckets, id: \.self) { bucket in
                            Button(bucket.title) { try? model.load(bucket: bucket) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel(L10n.t("nav.section.mailboxes"))
                }
            }
        }
    }
}

/// 搜索结果与普通列表共用连续行视觉和 List selection（JOURNEY-007/008/019）。
struct SearchResultsView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var dateIndex = MailDateIndex(entries: [])

    var body: some View {
        VStack(spacing: 0) {
            if model.searchResults.isEmpty {
                Text(L10n.t("search.empty"))
                    .font(DesignTokens.Typo.body)
                    .foregroundColor(DesignTokens.inkMuted)
                    .padding(.top, 60)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(model.searchResults, id: \.stableId) { row in
                        MailRowView(
                            entry: BucketEntry(stableId: row.stableId, subject: row.subject,
                                               fromAddress: row.fromAddress, snippet: row.snippet,
                                               date: row.date, bucket: "search", flags: row.flags),
                            bucket: .imbox,
                            selected: row.stableId == selection,
                            timeText: dateIndex.timeLabel(for: row.stableId))
                            .tag(row.stableId)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(DesignTokens.surfaceList)
                            .contextMenu { rowContextMenu(row) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .environment(\.defaultMinListRowHeight, DesignTokens.rowHeight)
            }
        }
        .background(DesignTokens.surfaceList)
        .onAppear { rebuildIndex() }
        .onChange(of: model.searchResults) { _ in rebuildIndex() }
    }

    private func rebuildIndex() {
        dateIndex = MailDateIndex(entries: model.searchResults.map {
            BucketEntry(stableId: $0.stableId, subject: $0.subject, fromAddress: $0.fromAddress,
                        snippet: $0.snippet, date: $0.date, bucket: "search", flags: $0.flags)
        }, reusing: dateIndex)
    }

    @ViewBuilder
    private func rowContextMenu(_ row: MirrorKit.MailRow) -> some View {
        Button(L10n.t("reader.reply")) {
            model.setReading(row.stableId)
            model.request(.reply)
        }
        Button(L10n.t("reader.setAside")) { try? model.setAside(stableId: row.stableId) }
        if row.flagList.contains("\\Seen") {
            Button(L10n.t("reader.menu.markUnread")) { model.markUnread(stableId: row.stableId) }
        } else {
            Button(L10n.t("reader.menu.markRead")) { model.markRead(stableId: row.stableId) }
        }
        Divider()
        Button(L10n.t("reader.menu.copySender")) { Clipboard.copy(row.fromAddress ?? "") }
        Button(L10n.t("reader.menu.delete"), role: .destructive) {
            let bridge = MailSelectionBridge(entries: model.searchResults.map {
                BucketEntry(stableId: $0.stableId, bucket: "search", flags: $0.flags)
            })
            let replacement = bridge.replacement(after: row.stableId)
            try? model.delete(stableId: row.stableId)
            if selection == row.stableId { selection = replacement }
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
