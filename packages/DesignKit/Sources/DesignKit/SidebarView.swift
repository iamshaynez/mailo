import CoreKit
import MirrorKit
import SwiftUI

/// 侧栏 v2（JOURNEY-025/026）：构成由 SidebarIA 纯模型提供，本视图零分叉渲染。
/// Screener 置顶（门卫）→ Imbox/Feed/Paper Trail（可展开桶内组）→ Set Aside；
/// 底部动作组。零假项——不再有任何无动作槽位。
struct SidebarView: View {
    @ObservedObject var model: MailoAppModel
    @ObservedObject var root: MailoRootModel
    @Binding var segment: Int
    @State private var showSettings = false
    @State private var expandedBuckets: Set<Bucket> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 侧栏构成（JOURNEY-025）：唯一权威是 SidebarIA.items。
    private var entries: [SidebarIA.Entry] {
        SidebarIA.items(
            bucketCounts: model.bucketCounts,
            isDemo: root.demo != nil,
            canCompose: model.canCompose,
            isSyncCapable: model.isSyncCapable,
            showsSettings: Self.showsSettings
        )
    }

    #if os(iOS)
    static let showsSettings = true
    #else
    static let showsSettings = false // macOS 走系统菜单 ⌘,（JOURNEY-016）
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MailoBrandMark()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                row(for: entry)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.surfaceSidebar)
        #if os(iOS)
        .sheet(isPresented: $showSettings) { MailoSettingsView(root: root) }
        #endif
    }

    // MARK: - 条目渲染（每项都是真实动作，JOURNEY-025）

    @ViewBuilder
    private func row(for entry: SidebarIA.Entry) -> some View {
        switch entry {
        case .bucket(let bucket, let count, let expandable):
            bucketRow(bucket, count: count, expandable: expandable)
            if expandable && expandedBuckets.contains(bucket) {
                tagRows(for: bucket)
            }
        case .separator:
            sidebarSeparator
        case .compose(let enabled):
            SidebarButton(title: L10n.t("nav.compose"), icon: "pencil",
                          enabled: enabled) { model.request(.compose) }
        case .settings:
            SidebarButton(title: L10n.t("nav.settings"), icon: "gearshape") { showSettings = true }
        case .syncNow(let enabled):
            SidebarButton(title: L10n.t("menu.syncNow"), icon: "arrow.triangle.2.circlepath",
                          enabled: enabled) { model.syncNow() }
        case .exitDemo:
            SidebarButton(title: L10n.t("demo.exit"), icon: "arrow.backward.square") { root.exitDemo() }
        }
    }

    /// 桶行：点击回整桶（清除组过滤，JOURNEY-026）；可展开桶带组列表 disclosure。
    private func bucketRow(_ bucket: Bucket, count: Int, expandable: Bool) -> some View {
        let selected = model.selectedBucket == bucket && !isTagFilterActive(in: bucket)
        return Button {
            expandedBuckets.insert(bucket) // 选中桶自动展开组列表
            try? model.load(bucket: bucket)
        } label: {
            SidebarRow(title: bucket.title, icon: bucket.sidebarIcon, count: count,
                       selected: selected,
                       trailingIcon: expandable
                           ? (expandedBuckets.contains(bucket) ? "chevron.down" : "chevron.right")
                           : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(count > 0 ? "\(bucket.title), \(count)" : bucket.title))
    }

    /// 组行（JOURNEY-026）：组名+计数（计数倒序，来自 store）；「未分组」恒显示（n>0）。
    @ViewBuilder
    private func tagRows(for bucket: Bucket) -> some View {
        let groups = model.tagCounts[bucket.rawValue] ?? []
        let taggedTotal = groups.reduce(0) { $0 + $1.count }
        let untagged = max(0, (model.bucketCounts[bucket.rawValue] ?? 0) - taggedTotal)
        ForEach(groups, id: \.tag) { group in
            tagRow(bucket: bucket, title: group.tag.name,
                   count: group.count, filter: .tagged(group.tag))
        }
        if untagged > 0 {
            tagRow(bucket: bucket, title: L10n.t("sidebar.untagged"),
                   count: untagged, filter: .untagged)
        }
    }

    private func tagRow(bucket: Bucket, title: String, count: Int, filter: TagFilter) -> some View {
        let selected = model.selectedBucket == bucket && model.tagFilter == filter
        return Button {
            try? model.load(bucket: bucket, tag: filter)
        } label: {
            SidebarRow(title: title, icon: nil, count: count, selected: selected,
                       indent: true, compact: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(bucket.title) · \(title), \(count)"))
    }

    private var sidebarSeparator: some View {
        Rectangle()
            .fill(DesignTokens.sidebarMuted.opacity(0.25))
            .frame(height: 0.5)
            .padding(.horizontal, DesignTokens.spacingPanel)
            .padding(.vertical, 7)
    }

    private func isTagFilterActive(in bucket: Bucket) -> Bool {
        guard model.selectedBucket == bucket else { return false }
        if case .all = model.tagFilter { return false }
        return true
    }
}

/// 侧栏动作按钮（JOURNEY-025）：全部可执行——禁用态只来自真实能力（canCompose/isSyncCapable）。
private struct SidebarButton: View {
    let title: String
    let icon: String
    var enabled = true
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SidebarRow(title: title, icon: icon, selected: false,
                       trailingIcon: nil, hovered: hovered && enabled, dimmed: !enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: hovered)
        .accessibilityLabel(Text(title))
    }
}

/// 34pt 全宽导航行；选中态是矩形表面与左缘 3pt accent，不使用胶囊选框。
/// 组行（indent+compact）：缩进一级、micro 字号、无图标（JOURNEY-026）。
private struct SidebarRow: View {
    let title: String
    let icon: String?
    var count = 0
    var selected = false
    var trailingIcon: String?
    var hovered = false
    var dimmed = false
    var indent = false
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(DesignTokens.Typo.iconSmall)
                    .frame(width: 16)
            } else if indent {
                Color.clear.frame(width: 16) // 组行缩进占位（对齐桶行图标位）
            }
            Text(title)
                .font(compact ? DesignTokens.Typo.micro : DesignTokens.Typo.navItem)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(DesignTokens.Typo.micro)
                    .foregroundColor(DesignTokens.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(DesignTokens.accent.opacity(0.12)))
            }
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(DesignTokens.Typo.iconTiny)
                    .frame(width: 12)
            }
        }
        .foregroundColor(foreground)
        .padding(.leading, indent ? DesignTokens.spacingPanel + 26 : DesignTokens.spacingPanel)
        .padding(.trailing, DesignTokens.spacingPanel)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        .background {
            if selected {
                Rectangle().fill(DesignTokens.sidebarActive)
            } else if hovered {
                Rectangle().fill(DesignTokens.sidebarActive.opacity(0.55))
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.accent)
                .frame(width: DesignTokens.selectionBarWidth)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    private var rowHeight: CGFloat { compact ? 28 : 34 }

    private var foreground: Color {
        if selected { return DesignTokens.sidebarInk }
        if dimmed { return DesignTokens.sidebarMuted.opacity(0.45) }
        return DesignTokens.sidebarMuted
    }
}

extension Bucket {
    /// 导航可达桶（iPhone bucket 菜单；顺序 = 侧栏 IA v2，Screener 置顶，JOURNEY-008/025）。
    static let navBuckets: [Bucket] = [.screener, .imbox, .feed, .paperTrail, .setAside]
    /// 手动纠正目标（JOURNEY-017）。
    static let correctionTargets: [Bucket] = [.imbox, .feed, .paperTrail, .setAside]
    /// 本地化桶名（DESIGN-003）。
    var title: String { L10n.t("bucket.\(rawValue)") }
    var sidebarIcon: String {
        switch self {
        case .imbox: return "tray.fill"
        case .feed: return "newspaper.fill"
        case .paperTrail: return "doc.text.fill"
        case .screener: return "person.crop.circle.badge.questionmark.fill"
        case .setAside: return "bookmark.fill"
        case .blocked: return "hand.raised.fill"
        }
    }
}
