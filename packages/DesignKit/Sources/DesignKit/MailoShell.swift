import CoreKit
import MirrorKit
import SwiftUI

/// 三栏主壳（JOURNEY-008 骨架原生化 / JOURNEY-010 demo 隔离）：
/// `NavigationSplitView`（212 侧栏 / 392 列表 / flex 阅读，可拖动、⌘⇧C 折叠）+
/// 系统 toolbar 以运通蓝着色承载搜索与 Compose（Blue Box 身份的规范表达）。
/// root 持有 live/demo 双模型：demo 时常驻水印条并可一键退出（内存库随弃）。
public struct MailoShell: View {
    @ObservedObject var root: MailoRootModel
    @State private var selection: String?
    @State private var composeDraft: ComposeDraft?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// 便捷入口（测试/预览）：单模型直接成壳。
    public init(model: MailoAppModel) {
        self.root = MailoRootModel(live: model)
    }

    public init(root: MailoRootModel) {
        self.root = root
    }

    public var body: some View {
        MainSurface(
            root: root, selection: $selection, composeDraft: $composeDraft,
            searchText: $searchText, searchFocused: $searchFocused,
            columnVisibility: $columnVisibility, sizeClass: sizeClass ?? .regular
        )
        .preferredColorScheme(.light) // 设计规范 §7：v1 锁浅色
    }
}

/// 实际表面（持有 active 模型的观察）：active 切换（进/出 demo）时整体重建。
private struct MainSurface: View {
    @ObservedObject var root: MailoRootModel
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @Binding var composeDraft: ComposeDraft?
    @Binding var searchText: String
    @FocusState.Binding var searchFocused: Bool
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let sizeClass: UserInterfaceSizeClass

    init(root: MailoRootModel, selection: Binding<String?>, composeDraft: Binding<ComposeDraft?>,
         searchText: Binding<String>, searchFocused: FocusState<Bool>.Binding,
         columnVisibility: Binding<NavigationSplitViewVisibility>, sizeClass: UserInterfaceSizeClass) {
        self.root = root
        self.model = root.active
        _selection = selection
        _composeDraft = composeDraft
        _searchText = searchText
        _searchFocused = searchFocused
        _columnVisibility = columnVisibility
        self.sizeClass = sizeClass
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
        .sheet(item: $composeDraft) { draft in
            ComposeView(model: model, draft: draft)
        }
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
            composeDraft = ComposeDraft()
        case .reply:
            if let id = model.readingStableId { composeDraft = model.composeDraft(for: id, kind: .reply) }
        case .forward:
            if let id = model.readingStableId { composeDraft = model.composeDraft(for: id, kind: .forward) }
        case .setAside:
            if let id = model.readingStableId { try? model.setAside(stableId: id) }
        case .toggleUnread:
            if let id = model.readingStableId { model.toggleUnread(stableId: id) }
        case .focusSearch:
            searchFocused = true
        }
    }

    // MARK: 宽屏三栏（NavigationSplitView）

    private var wideLayout: some View {
        VStack(spacing: 0) {
            if root.demo != nil { demoStrip }
            screenerBanner
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(model: model)
                    .background(DesignTokens.surfaceMain)
                    .navigationSplitViewColumnWidth(min: 180, ideal: DesignTokens.sidebarWidth, max: 320)
            } content: {
                listColumn
                    .background(DesignTokens.surfaceMain)
                    .navigationSplitViewColumnWidth(min: 320, ideal: DesignTokens.listWidth, max: 560)
            } detail: {
                readerPane
            }
            .navigationSplitViewStyle(.balanced)
        }
        .navigationTitle("Mailo")
        #if os(macOS)
        .toolbarBackground(DesignTokens.brandBlue, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar) // 蓝底上系统自动用浅色内容
        #else
        .toolbarBackground(DesignTokens.brandBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar { toolbarContent }
        .background(DesignTokens.surfaceMain)
    }

    /// Demo 水印条（JOURNEY-010）：常驻 + 一键退出。
    private var demoStrip: some View {
        HStack(spacing: 8) {
            Circle().fill(DesignTokens.bucketColor(.setAside)).frame(width: 7, height: 7)
            Text("Demo — sample mailbox, nothing touches your real account.")
                .font(.system(size: 12))
            Spacer()
            Button("Exit Demo") { root.exitDemo() }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DesignTokens.brandBlue)
                .buttonStyle(.plain)
        }
        .foregroundColor(DesignTokens.inkSecondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(DesignTokens.brandBlueWash)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.brandBlueBorder).frame(height: 1)
        }
    }

    @ViewBuilder
    private var listColumn: some View {
        if searchText.isEmpty {
            MailListView(model: model, selection: $selection)
        } else {
            SearchResultsView(model: model, selection: $selection)
        }
    }

    @ViewBuilder
    private var readerPane: some View {
        if let selection {
            MailReaderView(model: model, stableId: selection)
        } else {
            VStack {
                Spacer()
                Image(systemName: "envelope.open")
                    .font(.system(size: 40))
                    .foregroundColor(DesignTokens.inkFaint.opacity(0.6))
                Text("Imbox is calm.")
                    .foregroundColor(DesignTokens.inkMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(DesignTokens.surfaceWash)
        }
    }

    // MARK: 品牌工具栏（mockup §4：运通蓝标题栏的原生化表达）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            searchField
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                composeDraft = ComposeDraft()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                    Text("Compose")
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
            TextField("Search all mail…", text: $searchText)
                .font(.system(size: 12.5))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘K") // 与 MailoCommandMenu 的 ⌘K 呼应（JOURNEY-009）
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)))
            }
        }
        .foregroundColor(Color.white.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(minWidth: 220, idealWidth: 380, maxWidth: 420)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        .onChange(of: searchText) { q in model.searchDebounced(q) } // JOURNEY-015 防抖
        #if os(macOS)
        .onExitCommand { // Esc：清空搜索恢复列表（macOS）
            if !searchText.isEmpty {
                searchText = ""
                model.clearSearch()
            }
        }
        #endif
    }

    // MARK: Screener 顶条（mockup §5）

    @ViewBuilder
    private var screenerBanner: some View {
        let count = model.bucketCounts[Bucket.screener.rawValue] ?? 0
        if count > 0 {
            HStack(spacing: 8) {
                Circle().fill(DesignTokens.bucketColor(.screener)).frame(width: 7, height: 7)
                Text("\(count) new senders waiting in your Screener — approve once, filed forever.")
                    .font(.system(size: 12.5))
                Spacer()
                Button {
                    selection = nil
                    try? model.load(bucket: .screener)
                } label: {
                    Text("Review →")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(DesignTokens.brandBlue)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(DesignTokens.brandBlueDeep)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(DesignTokens.brandBlueWash)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DesignTokens.brandBlueBorder).frame(height: 1)
            }
        }
    }

    // MARK: 窄屏（iPhone）：NavigationStack 单栏 + 覆盖式阅读 + bucket 菜单

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                if searchText.isEmpty {
                    MailListView(model: model, selection: .constant(nil))
                        .frame(maxWidth: .infinity)
                } else {
                    SearchResultsView(model: model, selection: .constant(nil))
                        .frame(maxWidth: .infinity)
                }
                if let selection {
                    MailReaderView(model: model, stableId: selection)
                        .background(DesignTokens.surfaceMain)
                        .overlay(alignment: .topLeading) {
                            Button {
                                self.selection = nil
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignTokens.brandBlue)
                                    .padding(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.move(edge: .trailing))
                }
            }
            .navigationTitle("Mailo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.brandBlue, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { composeDraft = ComposeDraft() } label: { Image(systemName: "pencil") }
                        .disabled(!model.canCompose)
                }
                ToolbarItem(placement: .navigation) {
                    Menu {
                        ForEach(Bucket.navBuckets, id: \.self) { bucket in
                            Button(bucket.title) { try? model.load(bucket: bucket) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    }
}

/// 搜索结果（JOURNEY-007）：全库命中，与列表同源行视觉 + List selection（JOURNEY-008）。
struct SearchResultsView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var dateIndex = MailDateIndex(entries: [])

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search Results")
                    .font(.system(size: 19, weight: .heavy))
                Text("\(model.searchResults.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.inkFaint)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider().overlay(DesignTokens.borderDefault)
            if model.searchResults.isEmpty {
                Text("No results")
                    .font(.system(size: 13))
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
                            .listRowBackground(row.stableId == selection
                                ? DesignTokens.brandBlueWash
                                : DesignTokens.surfaceMain)
                            .contextMenu { rowContextMenu(row) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(DesignTokens.surfaceMain)
        .onAppear { rebuildIndex() }
        .onChange(of: model.searchResults) { _ in rebuildIndex() }
    }

    private func rebuildIndex() {
        dateIndex = MailDateIndex(entries: model.searchResults.map {
            BucketEntry(stableId: $0.stableId, subject: $0.subject, fromAddress: $0.fromAddress,
                        snippet: $0.snippet, date: $0.date, bucket: "search", flags: $0.flags)
        })
    }

    @ViewBuilder
    private func rowContextMenu(_ row: MirrorKit.MailRow) -> some View {
        Button("Reply") {
            model.setReading(row.stableId)
            model.request(.reply)
        }
        Button("Set Aside") { try? model.setAside(stableId: row.stableId) }
        if row.flagList.contains("\\Seen") {
            Button("Mark Unread") { model.markUnread(stableId: row.stableId) }
        } else {
            Button("Mark as Read") { model.markRead(stableId: row.stableId) }
        }
        Divider()
        Button("Copy Sender") { Clipboard.copy(row.fromAddress ?? "") }
    }
}

/// 剪贴板抽象（context menu 用；macOS NSPasteboard / iOS UIPasteboard）。
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
