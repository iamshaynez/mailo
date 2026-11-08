import CoreKit
import MirrorKit
import SwiftUI

/// 邮件列表（mockup：标题/分段控件/日期分组/行视觉）。
struct MailListView: View {
    @ObservedObject var model: MailoAppModel
    @Binding var selection: String?
    @State private var segment = 0 // 0 New / 1 Seen / 2 All

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.borderDefault)
            segmented
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider().overlay(DesignTokens.borderDefault)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(grouped.keys.sorted().reversed(), id: \.self) { day in
                        Section {
                            ForEach(grouped[day] ?? [], id: \.stableId) { entry in
                                MailRowView(entry: entry,
                                            bucket: model.selectedBucket,
                                            selected: entry.stableId == selection)
                                    .onTapGesture { selection = entry.stableId }
                                    .padding(.horizontal, 8)
                            }
                        } header: {
                            Text(day)
                                .font(.system(size: 10.5, weight: .bold))
                                .tracking(1)
                                .foregroundColor(DesignTokens.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(DesignTokens.surfaceMain.opacity(0.96))
                        }
                    }
                    if filtered.isEmpty {
                        Text("这里很安静。")
                            .font(.system(size: 13))
                            .foregroundColor(DesignTokens.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
            }
        }
        .frame(width: DesignTokens.listWidth)
        .background(DesignTokens.surfaceMain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.selectedBucket.title)
                .font(.system(size: 19, weight: .heavy))
                .foregroundColor(DesignTokens.inkPrimary)
            Text("\(model.entries.count) 封")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.inkFaint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(Array(["New", "Seen", "All"].enumerated()), id: \.offset) { index, label in
                Button {
                    segment = index
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(segment == index ? DesignTokens.brandBlue : DesignTokens.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(segment == index ? DesignTokens.surfaceMain : Color.clear)
                                .shadow(color: Color.black.opacity(segment == index ? 0.08 : 0), radius: 1, y: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.surfaceSubtle))
    }

    private var filtered: [BucketEntry] {
        switch segment {
        case 0: return model.entries.filter { !$0.flags.contains("\\Seen") }
        case 1: return model.entries.filter { $0.flags.contains("\\Seen") }
        default: return model.entries
        }
    }

    /// 按日期分组：TODAY / YESTERDAY / 更早显示日期（按 date 头的 yyyy-MM-dd 归一）。
    private var grouped: [String: [BucketEntry]] {
        var out: [String: [BucketEntry]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        for entry in filtered {
            let date = entry.date.flatMap { formatter.date(from: $0) }
            let label: String
            if let date {
                let day = Calendar.current.startOfDay(for: date)
                let gap = Calendar.current.dateComponents([.day], from: day, to: today).day ?? 99
                if gap == 0 { label = "TODAY" }
                else if gap == 1 { label = "YESTERDAY" }
                else {
                    let show = DateFormatter()
                    show.dateFormat = "MMM d"
                    label = show.string(from: date).uppercased()
                }
            } else {
                label = "未知日期"
            }
            out[label, default: []].append(entry)
        }
        return out
    }
}

/// 单行邮件（mockup 行视觉：bucket 头像/未读点/两行文本/选中蓝条）。
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
                    Text(timeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignTokens.inkFaint)
                }
                Text(entry.subject ?? "（无主题）")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                Text(entry.snippet ?? "")
                    .font(.system(size: 11.5))
                    .foregroundColor(DesignTokens.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? DesignTokens.brandBlueWash : Color.clear))
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(DesignTokens.brandBlue)
                    .frame(width: 3, height: 40)
                    .padding(.leading, 0)
            }
        }
        .contentShape(Rectangle())
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = entry.date.flatMap({ formatter.date(from: $0) }) else { return "" }
        let show = DateFormatter()
        show.dateFormat = "HH:mm"
        return show.string(from: date)
    }
}
