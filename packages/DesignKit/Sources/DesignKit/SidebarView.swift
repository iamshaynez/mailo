import CoreKit
import SwiftUI

/// Inbox Reference Exact 侧栏（JOURNEY-008/010/016 · DESIGN-001/004/005/007）。
/// 固定近黑导航面；真实邮件能力保留，未开放模块仅呈现不可执行槽位。
struct SidebarView: View {
    @ObservedObject var model: MailoAppModel
    @ObservedObject var root: MailoRootModel
    @Binding var segment: Int
    @State private var showSettings = false
    @State private var moreHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MailoBrandMark()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 20)
                .padding(.bottom, 16)

            SidebarItem(
                title: L10n.t("nav.mail"), icon: "envelope",
                selected: model.selectedBucket == .imbox,
                trailingIcon: "chevron.right",
                action: { try? model.load(bucket: .imbox) }
            )
            SidebarItem(title: L10n.t("nav.chat"), icon: "message")
            SidebarItem(title: L10n.t("nav.spaces"), icon: "person.2.fill")
            SidebarItem(title: L10n.t("nav.call"), icon: "phone.fill")
            SidebarItem(title: L10n.t("nav.compose"), icon: "pencil", action: { model.request(.compose) })
                .disabled(!model.canCompose)

            SidebarItem(
                title: L10n.t("nav.inbox"), icon: Bucket.imbox.sidebarIcon,
                count: model.bucketCounts[Bucket.imbox.rawValue] ?? 0,
                action: { try? model.load(bucket: .imbox) }
            )
            SidebarItem(title: L10n.t("nav.starred"), icon: "star")
            SidebarItem(title: L10n.t("nav.snoozed"), icon: "clock")
            SidebarItem(title: L10n.t("nav.sent"), icon: "paperplane.fill")
            SidebarItem(title: L10n.t("nav.draft"), icon: "doc.fill")
            moreMenu
            labelsSlot

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.surfaceSidebar)
        #if os(iOS)
        .sheet(isPresented: $showSettings) { MailoSettingsView(root: root) }
        #endif
    }

    private var moreMenu: some View {
        Menu {
            filterButton(title: L10n.t("segment.all"), value: -1)
            filterButton(title: L10n.t("segment.new"), value: 0)
            filterButton(title: L10n.t("segment.seen"), value: 1)
            filterButton(title: L10n.t("segment.aside"), value: 2)

            Divider()
            ForEach([Bucket.feed, .paperTrail, .screener, .setAside], id: \.self) { bucket in
                Button {
                    try? model.load(bucket: bucket)
                } label: {
                    Label(bucket.title, systemImage: bucket.sidebarIcon)
                }
            }

            Divider()
            Button(L10n.t("menu.syncNow")) { model.syncNow() }
                .disabled(!model.isSyncCapable)

            Divider()
            #if os(macOS)
            SettingsLink {
                Label(L10n.t("nav.settings"), systemImage: "gearshape")
            }
            #else
            Button {
                showSettings = true
            } label: {
                Label(L10n.t("nav.settings"), systemImage: "gearshape")
            }
            #endif

            if root.demo != nil {
                Divider()
                Button(L10n.t("demo.exit")) { root.exitDemo() }
            }
        } label: {
            SidebarRow(title: L10n.t("nav.more"), icon: "chevron.down", hovered: moreHovered)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { moreHovered = $0 }
        .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                 reduceMotion: reduceMotion), value: moreHovered)
        .accessibilityLabel(Text(L10n.t("nav.more")))
    }

    private func filterButton(title: String, value: Int) -> some View {
        Button {
            segment = value
        } label: {
            Label(title, systemImage: segment == value ? "checkmark" : "circle")
        }
    }

    private var labelsSlot: some View {
        HStack(spacing: 10) {
            Text(L10n.t("nav.labels"))
                .font(DesignTokens.Typo.micro)
                .tracking(1.1)
            Spacer(minLength: 4)
            Image(systemName: "plus")
                .font(DesignTokens.Typo.iconSmall)
                .frame(width: 16)
        }
        .foregroundColor(DesignTokens.sidebarMuted)
        .padding(.horizontal, DesignTokens.spacingPanel)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.t("nav.labels")))
        .accessibilityHint(Text(L10n.t("common.notAvailable")))
    }
}

/// 可执行导航项或无动作槽位；两种形态共用完全相同的参考稿行样式。
private struct SidebarItem: View {
    let title: String
    let icon: String
    var count = 0
    var selected = false
    var trailingIcon: String?
    var action: (() -> Void)?

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .onHover { hovered = $0 }
            .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                     reduceMotion: reduceMotion), value: hovered)
            .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                     reduceMotion: reduceMotion), value: selected)
    }

    @ViewBuilder
    private var content: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityTitle))
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityTitle))
                .accessibilityHint(Text(L10n.t("common.notAvailable")))
        }
    }

    private var row: some View {
        SidebarRow(title: title, icon: icon, count: count, selected: selected,
                   trailingIcon: trailingIcon, hovered: hovered)
    }

    private var accessibilityTitle: String {
        count > 0 ? "\(title), \(count)" : title
    }
}

/// 34pt 全宽导航行；选中态是矩形表面与左缘 3pt accent，不使用胶囊选框。
private struct SidebarRow: View {
    let title: String
    let icon: String
    var count = 0
    var selected = false
    var trailingIcon: String?
    var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(DesignTokens.Typo.iconSmall)
                .frame(width: 16)
            Text(title)
                .font(DesignTokens.Typo.navItem)
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
        .foregroundColor(selected ? DesignTokens.sidebarInk : DesignTokens.sidebarMuted)
        .padding(.horizontal, DesignTokens.spacingPanel)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
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
}

extension Bucket {
    /// 导航可达桶（侧栏与 iPhone bucket 菜单共用，JOURNEY-008）。
    static let navBuckets: [Bucket] = [.imbox, .feed, .paperTrail, .screener, .setAside]
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
