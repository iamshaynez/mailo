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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.borderDefault)
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
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(entry.stableId == selection
                                        ? DesignTokens.brandBlueWash
                                        : DesignTokens.surfaceMain)
                                    .contextMenu { rowContextMenu(entry) }
                            }
                        } header: {
                            Text(group.label)
                                .font(DesignTokens.Typo.micro)
                                .tracking(1.2)
                                .foregroundColor(DesignTokens.inkFaint)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, DesignTokens.rowHeight)
                // DESIGN-004：桶动作（决策/Set Aside）行进出走归类 spring；减弱动态无动画
                .animation(DesignTokens.Motion.spring(reduceMotion: reduceMotion),
                           value: model.entries)
            }
        }
        .background(DesignTokens.surfaceMain)
        .onAppear { rebuildSnapshot() }
        // JOURNEY-018：entries 变化分两类——flags 原位合并（阅读标记）只同步旗标；
        // 代际变化（load/同步/回填）才重建段快照（重新过滤成员）。
        .onChange(of: model.entries) {
            segmentSnapshot = SegmentSnapshot.mergeFlags(into: segmentSnapshot, from: $0)
            rebuildIndex()
        }
        .onChange(of: model.entriesGeneration) { _ in rebuildSnapshot() }
        .onChange(of: model.selectedBucket) { _ in rebuildSnapshot() }
        .onChange(of: segment) { newSegment in
            if newSegment == 2 { model.loadAsideEntries() } // 第三段直读 Set Aside 桶
            rebuildSnapshot()
        }
    }

    /// 重建段快照（成员按当前段过滤；JOURNEY-018 入口）。
    private func rebuildSnapshot() {
        segmentSnapshot = SegmentSnapshot.build(segment: segment, entries: model.entries)
        rebuildIndex()
    }

    private func rebuildIndex() {
        dateIndex = MailDateIndex(entries: displayEntries)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedBucket.title)
                    .font(DesignTokens.Typo.head)
                Text("\(displayEntries.count)")
                    .font(DesignTokens.Typo.caption.weight(.regular))
                    .foregroundColor(DesignTokens.inkFaint)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.spacingColumn).padding(.vertical, 10)
            segmented
                .padding(.horizontal, DesignTokens.spacingColumn).padding(.bottom, 10)
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

    /// 分段控件（规范 §5：New / Previously seen / Set aside）。
    private var segmented: some View {
        HStack(spacing: 3) {
            ForEach(Array(segmentTitles.enumerated()), id: \.offset) { index, title in
                Button {
                    segment = index
                } label: {
                    Text(title)
                        .font(DesignTokens.Typo.caption.weight(.semibold))
                        .foregroundColor(segment == index ? DesignTokens.brandBlue : DesignTokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(segment == index ? Color.white : Color.clear)
                                .shadow(color: segment == index ? Color.black.opacity(0.08) : .clear,
                                        radius: 2, y: 1))
                        .contentShape(Rectangle()) // 命中区域铺满分段格（JOURNEY-018）
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusButton)
            .fill(DesignTokens.surfaceSubtle))
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
    }
}

// MARK: - 分段快照（JOURNEY-018：段内成员稳定，flags 原位合并）

/// 分段快照的纯函数面（测试锁定）：
/// build = 进段/代际变化时按 flags 过滤成员；mergeFlags = 段内阅读标记只改旗标不动成员。
@MainActor
enum SegmentSnapshot {
    static func build(segment: Int, entries: [BucketEntry]) -> [BucketEntry] {
        switch segment {
        case 0: return entries.filter { !$0.flags.contains("\\Seen") }
        case 1: return entries.filter { $0.flags.contains("\\Seen") }
        default: return entries
        }
    }

    static func mergeFlags(into snapshot: [BucketEntry], from updated: [BucketEntry]) -> [BucketEntry] {
        let byId = Dictionary(uniqueKeysWithValues: updated.map { ($0.stableId, $0.flags) })
        var out = snapshot
        for i in out.indices {
            if let flags = byId[out[i].stableId] {
                out[i].flags = flags
            }
        }
        return out
    }
}

// MARK: - 日期分组与索引（PERF-004：加载时一次解析，行渲染零分配）

@MainActor
enum MailDateGrouping {
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
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; f.locale = Locale.current; return f
    }()
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale.current; return f
    }()
    static var parseCount = 0

    private let dates: [String: Date]

    init(entries: [BucketEntry]) {
        Self.parseCount = 0
        var rawCache: [String: Date] = [:]
        var out: [String: Date] = [:]
        for entry in entries {
            guard let raw = entry.date else { continue }
            if let cached = rawCache[raw] { out[entry.stableId] = cached; continue }
            guard let parsed = MailDateGrouping.rfc2822.date(from: raw) else { continue }
            Self.parseCount += 1
            rawCache[raw] = parsed
            out[entry.stableId] = parsed
        }
        dates = out
    }

    func date(for stableId: String) -> Date? { dates[stableId] }

    func dayLabel(for stableId: String) -> String {
        guard let date = dates[stableId] else { return L10n.t("date.undated") }
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.startOfDay(for: date)
        let gap = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 99
        if gap == 0 { return L10n.t("date.today") }
        if gap == 1 { return L10n.t("date.yesterday") }
        return Self.dayFormatter.string(from: date).uppercased()
    }

    func timeLabel(for stableId: String) -> String {
        guard let date = dates[stableId] else { return "" }
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.startOfDay(for: date)
        let gap = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 99
        return gap == 0 ? Self.timeFormatter.string(from: date) : Self.dayFormatter.string(from: date)
    }
}

/// 单行邮件（mockup 行视觉：bucket 头像/未读点/两行文本/选中蓝条 + hover）。
struct MailRowView: View {
    let entry: BucketEntry
    let bucket: Bucket
    let selected: Bool
    var timeText: String = ""
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isUnread: Bool { !entry.flags.contains("\\Seen") }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.radiusCard)
                    .fill(DesignTokens.bucketColor(bucket).opacity(0.9))
                Text(String((entry.fromAddress ?? "?").prefix(1)).uppercased())
                    .font(DesignTokens.Typo.bodyStrong)
                    .foregroundColor(.white)
            }
            .frame(width: DesignTokens.avatarSize, height: DesignTokens.avatarSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.fromAddress ?? L10n.t("row.unknown"))
                        .font(DesignTokens.Typo.bodyStrong)
                        .foregroundColor(DesignTokens.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isUnread {
                        Circle().fill(DesignTokens.brandBlue).frame(width: 7, height: 7)
                    }
                    Spacer(minLength: 0)
                    Text(timeText)
                        .font(DesignTokens.Typo.meta)
                        .foregroundColor(DesignTokens.inkFaint)
                }
                Text(entry.subject ?? L10n.t("row.noSubject"))
                    .font(DesignTokens.Typo.bodyStrong.weight(.medium))
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                Text(entry.snippet ?? "")
                    .font(DesignTokens.Typo.meta.weight(.regular))
                    .foregroundColor(DesignTokens.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: DesignTokens.selectionBarWidth / 2)
                    .fill(DesignTokens.brandBlue)
                    .frame(width: DesignTokens.selectionBarWidth, height: 40)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 } // mockup §2：hover 用 surface/wash（macOS 反馈）
        .background(hovered && !selected ? DesignTokens.surfaceWash : Color.clear)
        // DESIGN-004：选中/hover 微交互 120ms；减弱动态无动画
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion),
                   value: hovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.fromAddress ?? ""), \(entry.subject ?? "")\(isUnread ? ", \(L10n.t("segment.new"))" : "")")
    }
}
