import CoreKit
import MirrorKit
import SwiftUI

/// 列表栏（JOURNEY-008 · DESIGN-003/004）：`List(selection:)` 键盘导航，
/// 分段三段按规范（New / Previously seen / Set aside——第三段直读 Set Aside 桶）。
struct MailListView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var segment = 0 // 0 New / 1 Previously seen / 2 Set aside
    @State private var segmentSnapshot: [BucketEntry] = [] // JOURNEY-018：段内成员稳定
    @State private var dateIndex = MailDateIndex(entries: []) // PERF-004
    @Namespace private var segmentNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            if displayGroups.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(displayGroups, id: \.label) { group in
                        Section {
                            ForEach(group.entries, id: \.stableId) { entry in
                                MailRowView(entry: entry,
                                            bucket: segment == 2 ? .setAside : model.selectedBucket,
                                            selected: entry.stableId == selection,
                                            timeText: dateIndex.timeLabel(for: entry.stableId))
                                    .tag(entry.stableId)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(DesignTokens.surfaceList)
                                    .contextMenu { rowContextMenu(entry) }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deleteWithSelectionHandoff(entry.stableId)
                                        } label: {
                                            Label(L10n.t("reader.menu.delete"), systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text(group.label)
                                .font(DesignTokens.Typo.micro)
                                .tracking(1.1)
                                .foregroundColor(DesignTokens.inkFaint)
                                .padding(.leading, 12)
                                .padding(.top, 4)
                        }
                    }
                    // 滚动按需回填（SYNC-016 v2/018）：滚到底自动拉下一批，取代后台全量
                    if segment != 2, model.hasMoreHistory, !displayEntries.isEmpty {
                        Section {
                            historyFooter
                                .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                                .listRowSeparator(.hidden)
                                .listRowBackground(DesignTokens.surfaceList)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, DesignTokens.rowHeight)
                // DESIGN-004：分类/移出列表保留既有 spring。
                .animation(DesignTokens.Motion.spring(reduceMotion: reduceMotion),
                           value: displayEntries.map(\.stableId))
            }
        }
        .background(DesignTokens.surfaceList)
        // JOURNEY-018 v2：任何数据刷新（阅读标记/轮询/回填/同步）都走 merge——
        // 只增不删：已读留原位、移出桶的行消失、新邮件插入；后台刷新永不抽走阅读中的行。
        .onAppear { rebuildSnapshot() }
        .onChange(of: model.entries) { _ in
            segmentSnapshot = SegmentSnapshot.merge(segment: segment,
                                                    snapshot: segmentSnapshot,
                                                    incoming: model.entries)
            rebuildIndex()
        }
        .onChange(of: model.selectedBucket) { _ in rebuildSnapshot() } // 显式切桶 → 全量重算
        .onChange(of: segment) { newSegment in
            if newSegment == 2 { model.loadAsideEntries() } // 第三段直读 Set Aside 桶
            rebuildSnapshot() // 显式切段 → 全量重算
        }
    }

    /// 重建段快照（显式切换入口：按最新 flags 全量重算）。
    private func rebuildSnapshot() {
        segmentSnapshot = SegmentSnapshot.build(segment: segment, entries: model.entries)
        rebuildIndex()
    }

    private func rebuildIndex() {
        dateIndex = MailDateIndex(entries: displayEntries, reusing: dateIndex)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(model.selectedBucket.title)
                    .font(DesignTokens.Typo.head)
                    .foregroundColor(DesignTokens.inkPrimary)
                Text("\(displayEntries.count)")
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkFaint)
                Spacer()
                Button {
                    model.syncNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                .disabled(!model.isSyncCapable)
                .help(L10n.t("menu.syncNow"))
                .accessibilityLabel(L10n.t("menu.syncNow"))
            }
            .padding(.horizontal, DesignTokens.spacingColumn)
            .padding(.top, 8)
            .padding(.bottom, 6)
            segmented
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            if let progress = model.backfillProgress {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: Double(progress.fetched),
                                 total: Double(max(progress.total, 1)))
                        .tint(DesignTokens.brandBlue)
                    Text(L10n.t("list.backfill", progress.fetched))
                        .font(DesignTokens.Typo.micro)
                        .foregroundColor(DesignTokens.inkMuted)
                }
                .padding(.horizontal, DesignTokens.spacingColumn).padding(.bottom, 10)
            }
        }
    }

    /// 分段控件：浮起选择块以 matchedGeometryEffect 滑动（DESIGN-004 / JOURNEY-018）。
    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Array(segmentTitles.enumerated()), id: \.offset) { index, title in
                Button {
                    segment = index
                } label: {
                    Text(title)
                        .font(DesignTokens.Typo.caption)
                        .foregroundColor(segment == index ? DesignTokens.inkPrimary : DesignTokens.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if segment == index {
                                RoundedRectangle(cornerRadius: DesignTokens.radiusSearch)
                                    .fill(DesignTokens.surfaceCard)
                                    .matchedGeometryEffect(id: "activeSegment", in: segmentNamespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusButton)
            .fill(DesignTokens.surfaceControl))
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                 reduceMotion: reduceMotion), value: segment)
    }

    private var segmentTitles: [String] {
        [L10n.t("segment.new"), L10n.t("segment.seen"), L10n.t("segment.aside")]
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(DesignTokens.Typo.iconMedium)
                .foregroundColor(DesignTokens.inkFaint.opacity(0.6))
            Text(L10n.t("list.empty"))
                .font(DesignTokens.Typo.body)
                .foregroundColor(DesignTokens.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 数据选择（过滤 + Set aside 段）

    private var displayEntries: [BucketEntry] {
        segment == 2 ? model.asideEntries : segmentSnapshot
    }

    private var displayGroups: [(label: String, entries: [BucketEntry])] {
        MailDateGrouping.group(entries: displayEntries, index: dateIndex)
    }

    /// 历史加载行：滚入视口即拉下一批；批进行中转菊花（fetchingHistory 防重入）。
    @ViewBuilder
    private var historyFooter: some View {
        HStack(spacing: 8) {
            if model.fetchingHistory {
                ProgressView().controlSize(.small)
                Text(L10n.t("list.loadingMore"))
            } else {
                Text(L10n.t("list.loadMore"))
            }
        }
        .font(DesignTokens.Typo.caption)
        .foregroundColor(DesignTokens.inkMuted)
        .frame(maxWidth: .infinity)
        .onAppear { Task { await model.fetchMoreHistory() } }
    }

    @ViewBuilder
    private func rowContextMenu(_ entry: BucketEntry) -> some View {
        Button(L10n.t("reader.reply")) {
            model.setReading(entry.stableId)
            model.request(.reply)
        }
        Button(L10n.t("reader.setAside")) { try? model.setAside(stableId: entry.stableId) }
        if entry.flags.contains("\\Seen") {
            Button(L10n.t("reader.menu.markUnread")) { model.markUnread(stableId: entry.stableId) }
        } else {
            Button(L10n.t("reader.menu.markRead")) { model.markRead(stableId: entry.stableId) }
        }
        Divider()
        Button(L10n.t("reader.menu.copySender")) { Clipboard.copy(entry.fromAddress ?? "") }
        Button(L10n.t("reader.menu.delete"), role: .destructive) { deleteWithSelectionHandoff(entry.stableId) }
    }

    /// 删除并交接选中（JOURNEY-022）：删除前按当前可见顺序算相邻回退，避免阅读窗格悬空。
    private func deleteWithSelectionHandoff(_ stableId: String) {
        let replacement = MailSelectionBridge(entries: displayEntries).replacement(after: stableId)
        try? model.delete(stableId: stableId)
        if selection == stableId { selection = replacement }
    }
}

// MARK: - 分段快照（JOURNEY-018：段内成员稳定，flags 原位合并）

/// 分段快照的纯函数面（JOURNEY-018 v2，测试锁定）：
/// build = 显式切换（切段/切桶/进入视图）时按最新 flags 全量重算；
/// merge = 任意后台数据刷新的合并语义——**只增不删**：
/// 已在快照的行 flags 原位合并（已读变轻但不消失）、被移出桶的行删除、
/// 新到达的合格行按 date 归位插入；其余不动。
@MainActor
enum SegmentSnapshot {
    static func build(segment: Int, entries: [BucketEntry]) -> [BucketEntry] {
        switch segment {
        case 0: return entries.filter { !$0.flags.contains("\\Seen") }
        case 1: return entries.filter { $0.flags.contains("\\Seen") }
        default: return entries
        }
    }

    static func merge(segment: Int, snapshot: [BucketEntry], incoming: [BucketEntry]) -> [BucketEntry] {
        // PERF-005：同成员、同顺序、同日期的 flags-only 更新只做原位合并。
        if snapshot.count == incoming.count,
           zip(snapshot, incoming).allSatisfy({ old, new in
               old.stableId == new.stableId && old.date == new.date
           }) {
            var out = snapshot
            for i in out.indices { out[i].flags = incoming[i].flags }
            return out
        }

        let latest = Set(incoming.map(\.stableId))
        var out = snapshot.filter { latest.contains($0.stableId) } // 移出桶的行删除（用户显式移走）

        // flags 原位合并（已读变轻、未读点熄灭——成员不动）
        let byId = Dictionary(uniqueKeysWithValues: incoming.map { ($0.stableId, $0.flags) })
        for i in out.indices {
            if let flags = byId[out[i].stableId] {
                out[i].flags = flags
            }
        }

        // 只增：不在快照中且符合当前段的合格新行（新邮件到达）
        let existing = Set(out.map(\.stableId))
        let additions = build(segment: segment, entries: incoming).filter { !existing.contains($0.stableId) }
        out.append(contentsOf: additions)

        // 稳定按 date 倒序（ISO 字符串序；已有相对顺序保持）
        let withIndex = out.enumerated().map { (i: $0.offset, e: $0.element) }
        return withIndex.sorted {
            let l = $0.e.date ?? "", r = $1.e.date ?? ""
            return l == r ? $0.i < $1.i : l > r
        }.map(\.e)
    }
}

// MARK: - 日期分组与索引（PERF-004：加载时一次解析，行渲染零分配）

@MainActor
enum MailDateGrouping {
    /// 双格式解析（JOURNEY-020）：入库 ISO8601 优先，存量 RFC2822 原文兜底。
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return CoreKit.MailDateFormat.parse(raw)
    }

    /// RFC2822 解析器（静态缓存；全 UI 共享）。
    static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 按日分组：今天/昨天/更早日期标签；保持入参（日期倒序）顺序。
    static func group(entries: [BucketEntry], index: MailDateIndex) -> [(label: String, entries: [BucketEntry])] {
        var out: [(String, [BucketEntry])] = []
        var buckets: [String: Int] = [:]
        for entry in entries {
            let label = index.dayLabel(for: entry.stableId)
            if let i = buckets[label] {
                out[i].1.append(entry)
            } else {
                buckets[label] = out.count
                out.append((label, [entry]))
            }
        }
        return out.map { (label: $0.0, entries: $0.1) }
    }
}

/// 列表日期索引（PERF-004）：一次构建，同一 raw 字符串只解析一次；
/// 行渲染路径全部是字典查找 + 静态 formatter（跟随系统语言，DESIGN-003）。
/// `parseCount` 为测试观测口。
@MainActor
struct MailDateIndex {
    struct Labels {
        let day: String
        let time: String
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.locale = Locale.current; return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale.current; return f
    }()
    static var parseCount = 0

    private let dates: [String: Date]
    private let rawDates: [String: String]
    private let labels: [String: Labels]

    /// 按 stableId/raw 增量复用；day/time 标签只在索引变化时计算（PERF-004/005）。
    init(entries: [BucketEntry], reusing previous: MailDateIndex? = nil) {
        Self.parseCount = 0
        var rawCache: [String: Date] = [:]
        var dates: [String: Date] = [:]
        var rawDates: [String: String] = [:]
        var labels: [String: Labels] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for entry in entries {
            guard let raw = entry.date else { continue }
            rawDates[entry.stableId] = raw
            if previous?.rawDates[entry.stableId] == raw,
               let existing = previous?.labels[entry.stableId] {
                dates[entry.stableId] = previous?.dates[entry.stableId]
                labels[entry.stableId] = existing
                continue
            }

            let parsed: Date?
            if let cached = rawCache[raw] {
                parsed = cached
            } else {
                parsed = MailDateGrouping.parse(raw)
                if parsed != nil { Self.parseCount += 1 }
                rawCache[raw] = parsed
            }
            guard let date = parsed else { continue }
            dates[entry.stableId] = date

            let day = calendar.startOfDay(for: date)
            let gap = calendar.dateComponents([.day], from: day, to: today).day ?? 99
            let dayLabel = gap == 0 ? L10n.t("date.today")
                : gap == 1 ? L10n.t("date.yesterday")
                : Self.dayFormatter.string(from: date).uppercased()
            let timeLabel = gap == 0 ? Self.timeFormatter.string(from: date)
                : Self.dayFormatter.string(from: date)
            labels[entry.stableId] = Labels(day: dayLabel, time: timeLabel)
        }

        self.dates = dates
        self.rawDates = rawDates
        self.labels = labels
    }

    func date(for stableId: String) -> Date? { dates[stableId] }
    func dayLabel(for stableId: String) -> String {
        labels[stableId]?.day ?? L10n.t("date.undated")
    }
    func timeLabel(for stableId: String) -> String {
        labels[stableId]?.time ?? ""
    }
}

/// 行强调档位（JOURNEY-019）：未读=粗体+蓝点，已读=regular（Mail.app 式编码）。
/// 纯函数面：字重/未读点由档位唯一决定，视图零分叉。
@MainActor
enum RowEmphasis: Equatable {
    case unread
    case read

    init(isUnread: Bool) {
        self = isUnread ? .unread : .read
    }

    init(entry: BucketEntry) {
        self.init(isUnread: !entry.flags.contains("\\Seen"))
    }

    var showsDot: Bool { self == .unread }

    var senderWeight: Font.Weight {
        self == .unread ? .bold : .regular
    }

    var subjectWeight: Font.Weight {
        self == .unread ? .semibold : .regular
    }

    var senderFont: Font {
        DesignTokens.Typo.meta.weight(senderWeight)
    }

    var subjectFont: Font {
        DesignTokens.Typo.bodyStrong.weight(subjectWeight)
    }
}

/// 独立邮件卡片（Slate Concept §5）：主题/双行摘要/底部联系人元信息。
/// 选中以表面和阴影表达，未读仍由 RowEmphasis + 蓝点统一驱动（JOURNEY-019）。
struct MailRowView: View {
    let entry: BucketEntry
    let bucket: Bucket
    let selected: Bool
    var timeText: String = ""
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var isUnread: Bool { !entry.flags.contains("\\Seen") }
    private var emphasis: RowEmphasis { RowEmphasis(isUnread: isUnread) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 6) {
                Text(entry.subject ?? L10n.t("row.noSubject"))
                    .font(emphasis.subjectFont)
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isUnread {
                    Circle().fill(DesignTokens.brandBlue).frame(width: 6, height: 6)
                }
            }

            Text(entry.snippet ?? "")
                .font(DesignTokens.Typo.meta)
                .foregroundColor(DesignTokens.inkMuted)
                .lineLimit(2)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                MailoAvatar(address: entry.fromAddress, color: DesignTokens.bucketColor(bucket))
                Text(entry.fromAddress ?? L10n.t("row.unknown"))
                    .font(emphasis.senderFont)
                    .foregroundColor(DesignTokens.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(timeText)
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkFaint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                    .fill(hovered && !selected ? DesignTokens.surfaceHover : DesignTokens.surfaceCard)
                RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                    .fill(DesignTokens.surfaceCardSelected)
                    .shadow(color: DesignTokens.shadowColor.opacity(colorScheme == .light ? 0.10 : 0.24),
                            radius: ConnectionShadowSpec.blur,
                            x: ConnectionShadowSpec.x, y: ConnectionShadowSpec.y)
                    .opacity(selected ? 1 : 0)
            }
        }
        .background {
            if selected {
                GeometryReader { proxy in
                    Color.clear.preference(key: SelectedCardAnchorPreference.self,
                                           value: proxy.frame(in: .named("MailoShellCanvas")))
                }
            }
        }
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                .fill(DesignTokens.surfaceCardSelected)
                .frame(width: ReaderSurfaceSpec.cardTrailingAllowance + DesignTokens.radiusCard)
                .offset(x: (ReaderSurfaceSpec.cardTrailingAllowance + DesignTokens.radiusCard) / 2)
                .opacity(selected ? 1 : 0)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                .strokeBorder(selected ? DesignTokens.cardSelectedBorder : DesignTokens.borderHairline,
                              lineWidth: selected ? 1 : 0.5)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignTokens.surfaceCardSelected)
                .frame(width: 2)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusCard))
        .onHover { hovered = $0 }
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: hovered)
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.fromAddress ?? ""), \(entry.subject ?? "")\(isUnread ? ", \(L10n.t("segment.new"))" : "")")
    }
}
