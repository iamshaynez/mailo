import CoreKit
import MirrorKit
import SwiftUI

/// Slate Concept 三栏主壳（JOURNEY-008/010 · DESIGN-003/004/005）。
/// 系统 NavigationSplitView + 中性 toolbar；外观、动效与所有窗口共享。
public struct MailoShell: View {
    @ObservedObject var root: MailoRootModel
    @State private var selection: String?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openWindow) private var openWindow

    /// 便捷入口（测试/预览）：单模型直接成壳。
    public init(model: MailoAppModel) {
        self.root = MailoRootModel(live: model)
    }

    /// 测试/预览：以指定邮件直接装配阅读态（JOURNEY-008）。
    init(model: MailoAppModel, initialSelection: String?) {
        self.root = MailoRootModel(live: model)
        _selection = State(initialValue: initialSelection)
    }

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some View {
        MainSurface(
            root: root, selection: $selection,
            searchText: $searchText, searchFocused: $searchFocused,
            columnVisibility: $columnVisibility, sizeClass: sizeClass ?? .regular,
            openWindow: openWindow
        )
        .mailoAppearance()
    }
}

/// 实际表面；live/demo 切换时整体重建，状态与转场保持在壳层。
private struct MainSurface: View {
    @ObservedObject var root: MailoRootModel
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @Binding var searchText: String
    @FocusState.Binding var searchFocused: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sizeClass: UserInterfaceSizeClass
    let openWindow: OpenWindowAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCardAnchor: CGRect?

    init(root: MailoRootModel, selection: Binding<String?>,
         searchText: Binding<String>, searchFocused: FocusState<Bool>.Binding,
         columnVisibility: Binding<NavigationSplitViewVisibility>, sizeClass: UserInterfaceSizeClass,
         openWindow: OpenWindowAction) {
        self.root = root
        self.model = root.active
        _selection = selection
        _searchText = searchText
        _searchFocused = searchFocused
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
            if let id = model.readingStableId {
                openCompose(model.composeDraft(for: id, kind: .reply) ?? ComposeDraft(kind: .reply))
            }
        case .forward:
            if let id = model.readingStableId {
                openCompose(model.composeDraft(for: id, kind: .forward) ?? ComposeDraft(kind: .forward))
            }
        case .setAside:
            if let id = model.readingStableId { try? model.setAside(stableId: id) }
        case .toggleUnread:
            if let id = model.readingStableId { model.toggleUnread(stableId: id) }
        case .delete:
            // JOURNEY-022：删除后选中移到相邻邮件（next 优先、末位回退），无相邻回占位
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

    // MARK: 宽屏三栏

    private var wideLayout: some View {
        VStack(spacing: 0) {
            if root.demo != nil { demoStrip }
            screenerBanner
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(model: model, root: root)
                    .navigationSplitViewColumnWidth(min: 160, ideal: DesignTokens.sidebarWidth, max: 240)
            } content: {
                listColumn
                    .navigationSplitViewColumnWidth(min: 340, ideal: DesignTokens.listWidth, max: 520)
            } detail: {
                readerPane
                    .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                             reduceMotion: reduceMotion), value: colorScheme)
                    .padding(.trailing, ReaderSurfaceSpec.trailingGutter)
                    .padding(.bottom, ReaderSurfaceSpec.bottomGutter)
                    .background(DesignTokens.surfaceToolbar)
            }
            .navigationSplitViewStyle(.balanced)
            .coordinateSpace(name: "MailoShellCanvas")
            .onPreferenceChange(SelectedCardAnchorPreference.self) { selectedCardAnchor = $0 }
            .overlay {
                if let selectedCardAnchor {
                    ConnectionShadow(anchor: selectedCardAnchor)
                        .transition(.opacity)
                }
            }
            .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                     reduceMotion: reduceMotion), value: selectedCardAnchor != nil)
        }
        .navigationTitle("Mailo")
        #if os(macOS)
        .toolbarBackground(DesignTokens.surfaceToolbar, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #else
        .toolbarBackground(DesignTokens.surfaceToolbar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar { toolbarContent }
        .background(DesignTokens.surfaceToolbar)
    }

    private var demoStrip: some View {
        HStack(spacing: 8) {
            Circle().fill(DesignTokens.bucketColor(.setAside)).frame(width: 6, height: 6)
            Text(L10n.t("demo.badge"))
                .font(DesignTokens.Typo.meta)
            Spacer()
            Button(L10n.t("demo.exit")) { root.exitDemo() }
                .buttonStyle(MailoButtonStyle(variant: .ghost))
        }
        .foregroundColor(DesignTokens.inkSecondary)
        .padding(.horizontal, DesignTokens.spacingColumn)
        .padding(.vertical, 3)
        .background(DesignTokens.surfaceControl)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderHairline).frame(height: 1)
        }
    }

    @ViewBuilder
    private var listColumn: some View {
        Group {
            if searchText.isEmpty {
                MailListView(model: model, selection: $selection)
            } else {
                SearchResultsView(model: model, selection: $selection)
            }
        }
        .transition(.opacity)
        .background(DesignTokens.surfaceList)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: model.selectedBucket)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: searchText.isEmpty)
    }

    @ViewBuilder
    private var readerPane: some View {
        if let selection {
            GeometryReader { proxy in
                MailReaderView(model: model, stableId: selection, viewportHeight: proxy.size.height,
                                   viewportWidth: proxy.size.width)
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

    // MARK: 中性顶栏：Search + Account

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            searchField
        }
        ToolbarItem(placement: .primaryAction) {
            AccountMenuView(root: root, model: model)
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
                .accessibilityLabel(L10n.t("toolbar.search.placeholder"))
            }
        }
        .foregroundColor(DesignTokens.searchInk)
        .padding(.horizontal, 11)
        .frame(minWidth: 220, idealWidth: 374, maxWidth: 440)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusSearch).fill(DesignTokens.surfaceSearch))
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                    .strokeBorder(DesignTokens.borderHairline, lineWidth: 0.5)
                RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                    .strokeBorder(DesignTokens.brandBlue, lineWidth: 2)
                    .opacity(searchFocused ? 1 : 0)
            }
        }
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
    private var screenerBanner: some View {
        let count = model.bucketCounts[Bucket.screener.rawValue] ?? 0
        if count > 0 {
            HStack(spacing: 8) {
                Circle().fill(DesignTokens.bucketColor(.screener)).frame(width: 6, height: 6)
                Text(L10n.t("screener.banner", count))
                    .font(DesignTokens.Typo.caption)
                Spacer()
                Button(L10n.t("screener.review")) {
                    selection = nil
                    try? model.load(bucket: .screener)
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost))
            }
            .foregroundColor(DesignTokens.brandBlueDeep)
            .padding(.horizontal, DesignTokens.spacingColumn)
            .padding(.vertical, 3)
            .background(DesignTokens.brandBlueWash)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignTokens.brandBlueBorder).frame(height: 1)
            }
            .transition(.opacity)
        }
    }

    // MARK: 紧凑 iPhone

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Group {
                    if searchText.isEmpty {
                        MailListView(model: model, selection: $selection)
                    } else {
                        SearchResultsView(model: model, selection: $selection)
                    }
                }
                if let selection {
                    GeometryReader { proxy in
                        MailReaderView(model: model, stableId: selection, viewportHeight: proxy.size.height,
                                   viewportWidth: proxy.size.width)
                            .overlay(alignment: .topLeading) {
                                Button {
                                    self.selection = nil
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                                .padding(8)
                                .accessibilityLabel(L10n.t("reader.select"))
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
                        .foregroundColor(DesignTokens.brandBlue)
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

/// 顶栏账户菜单；iOS 用 sheet，macOS 使用原生 Settings 场景。
private struct AccountMenuView: View {
    @ObservedObject var root: MailoRootModel
    @ObservedObject var model: MailoAppModel
    @State private var showSettings = false

    private var accountLabel: String {
        if case .connected(let email) = model.phase { return email }
        if case .demo = model.phase { return "demo@local" }
        return L10n.t("account.notConnected")
    }

    var body: some View {
        Menu {
            #if os(macOS)
            SettingsLink {
                Label(L10n.t("account.menu"), systemImage: "gearshape")
            }
            #else
            Button {
                showSettings = true
            } label: {
                Label(L10n.t("account.menu"), systemImage: "gearshape")
            }
            #endif
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(accountLabel)
                        .font(DesignTokens.Typo.caption)
                        .foregroundColor(DesignTokens.inkPrimary)
                        .lineLimit(1)
                    Text(L10n.t("account.online"))
                        .font(DesignTokens.Typo.micro)
                        .foregroundColor(DesignTokens.statusSuccessFg)
                }
                MailoAvatar(address: accountLabel, color: DesignTokens.bucketColor(.paperTrail), size: 28)
                Image(systemName: "chevron.down")
                    .font(DesignTokens.Typo.iconTiny)
                    .foregroundColor(DesignTokens.inkMuted)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.t("account.menu"))
        #if os(iOS)
        .sheet(isPresented: $showSettings) { MailoSettingsView(root: root) }
        #endif
    }
}

/// 搜索结果与普通列表共用卡片视觉和 List selection（JOURNEY-007/008/019）。
struct SearchResultsView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var dateIndex = MailDateIndex(entries: [])

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(L10n.t("search.title"))
                    .font(DesignTokens.Typo.head)
                    .foregroundColor(DesignTokens.inkPrimary)
                Text("\(model.searchResults.count)")
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkFaint)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.spacingColumn)
            .padding(.vertical, 14)

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
                            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                            .listRowSeparator(.hidden)
                            .listRowBackground(DesignTokens.surfaceList)
                            .contextMenu { rowContextMenu(row) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
