import CoreKit
import MirrorKit
import SwiftUI

/// 列表栏（JOURNEY-008）：`List(selection:)` 原生键盘导航（↑↓/type-ahead），
/// 日期分组 Section；分段过滤 New / Seen / All。
struct MailListView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var segment = 0 // 0 New / 1 Seen / 2 All

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.borderDefault)
            if filteredGroups.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(filteredGroups, id: \.label) { group in
                        Section {
                            ForEach(group.entries, id: \.stableId) { entry in
                                MailRowView(entry: entry,
                                            bucket: model.selectedBucket,
                                            selected: entry.stableId == selection)
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
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1.2)
                                .foregroundColor(DesignTokens.inkFaint)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 68)
            }
        }
        .background(DesignTokens.surfaceMain)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedBucket.title)
                    .font(.system(size: 19, weight: .heavy))
                Text("\(filteredGroups.map(\.entries.count).reduce(0, +))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignTokens.inkFaint)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            segmented
                .padding(.horizontal, 16).padding(.bottom, 10)
        }
    }

    /// 分段控件（mockup §5 胶囊三段）。
    private var segmented: some View {
        HStack(spacing: 3) {
            ForEach(Array(["New", "Seen", "All"].enumerated()), id: \.offset) { index, title in
                Button {
                    segment = index
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(segment == index ? DesignTokens.brandBlue : DesignTokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(segment == index ? Color.white : Color.clear)
                                .shadow(color: segment == index ? Color.black.opacity(0.08) : .clear,
                                        radius: 2, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.surfaceSubtle))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(DesignTokens.inkFaint.opacity(0.6))
            Text("All quiet here.")
                .font(.system(size: 13))
                .foregroundColor(DesignTokens.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowContextMenu(_ entry: BucketEntry) -> some View {
        Button("Reply") {
            model.setReading(entry.stableId)
            model.request(.reply)
        }
        Button("Set Aside") { try? model.setAside(stableId: entry.stableId) }
        if entry.flags.contains("\\Seen") {
            Button("Mark Unread") { model.markUnread(stableId: entry.stableId) }
        } else {
            Button("Mark as Read") { model.markRead(stableId: entry.stableId) }
        }
        Divider()
        Button("Copy Sender") { Clipboard.copy(entry.fromAddress ?? "") }
    }

    // MARK: 过滤与分组

    private var filtered: [BucketEntry] {
        switch segment {
        case 0: return model.entries.filter { !$0.flags.contains("\\Seen") }
        case 1: return model.entries.filter { $0.flags.contains("\\Seen") }
        default: return model.entries
        }
    }

    private var filteredGroups: [(label: String, entries: [BucketEntry])] {
        MailDateGrouping.group(entries: filtered)
    }
}

// MARK: - 日期分组与格式化（PERF-004 方向：formatter 静态缓存，行渲染零分配）

enum MailDateGrouping {
    /// RFC2822 解析器（静态缓存；行渲染路径复用同一实例）。
    static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 按日分组：TODAY / YESTERDAY / 更早显示日期；保持入参（日期倒序）顺序。
    static func group(entries: [BucketEntry]) -> [(label: String, entries: [BucketEntry])] {
        var out: [(String, [BucketEntry])] = []
        var buckets: [String: Int] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        for entry in entries {
            let label = dayLabel(entry.date, today: today)
            if let index = buckets[label] {
                out[index].1.append(entry)
            } else {
                buckets[label] = out.count
                out.append((label, [entry]))
            }
        }
        return out.map { (label: $0.0, entries: $0.1) }
    }

    static func dayLabel(_ raw: String?, today: Date) -> String {
        guard let raw, let date = rfc2822.date(from: raw) else { return "Undated" }
        let day = Calendar.current.startOfDay(for: date)
        let gap = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 99
        if gap == 0 { return "TODAY" }
        if gap == 1 { return "YESTERDAY" }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))
            .uppercased()
    }

    /// 行内时间标签：今天显示时刻，更早显示月日。
    static func timeLabel(_ raw: String?) -> String {
        guard let raw, let date = rfc2822.date(from: raw) else { return "" }
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.startOfDay(for: date)
        let gap = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 99
        if gap == 0 {
            return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))
        }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))
    }
}

/// 单行邮件（mockup 行视觉：bucket 头像/未读点/两行文本/选中蓝条）。
/// 选中底色由 List 的 listRowBackground 提供（全幅蓝 wash），行内只保留 3pt 蓝条。
struct MailRowView: View {
    let entry: BucketEntry
    let bucket: Bucket
    let selected: Bool

    private var isUnread: Bool { !entry.flags.contains("\\Seen") }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesignTokens.bucketColor(bucket).opacity(0.9))
                Text(String((entry.fromAddress ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.fromAddress ?? "unknown")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DesignTokens.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isUnread {
                        Circle().fill(DesignTokens.brandBlue).frame(width: 7, height: 7)
                    }
                    Spacer(minLength: 0)
                    Text(MailDateGrouping.timeLabel(entry.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignTokens.inkFaint)
                }
                Text(entry.subject ?? "(no subject)")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                Text(entry.snippet ?? "")
                    .font(.system(size: 11.5))
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
    }
}
