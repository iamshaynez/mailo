import CoreKit
import SwiftUI

/// 侧栏（mockup §4：212pt；账户行 / MAILBOXES 徽章 / DECIDE / 隐私徽章 + 设置入口）。
/// 隐私徽章用规范状态色（DESIGN-002：不再内联 RGB）。
struct SidebarView: View {
    @ObservedObject var model: MailoAppModel
    @ObservedObject var root: MailoRootModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            accountRow
            Divider().overlay(DesignTokens.borderDefault)

            navSection(key: "nav.section.mailboxes", buckets: [.imbox, .feed, .paperTrail])
            navSection(key: "nav.section.decide", buckets: [.screener, .setAside])

            Spacer(minLength: 0)

            privacyFooter
        }
        .background(DesignTokens.surfaceMain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .sheet(isPresented: $showSettings) { MailoSettingsView(root: root) }
        #endif
    }

    private var accountRow: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(DesignTokens.brandBlue)
                Text(String(accountInitial))
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
            Text(accountLabel)
                .font(DesignTokens.Typo.body)
                .foregroundColor(DesignTokens.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var accountLabel: String {
        if case .connected(let email) = model.phase { return email }
        if case .demo = model.phase { return "demo@local" }
        return L10n.t("account.notConnected")
    }

    private var accountInitial: String {
        String(accountLabel.prefix(1)).uppercased()
    }

    private func navSection(key: String, buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t(key))
                .font(DesignTokens.Typo.micro)
                .tracking(1.2)
                .foregroundColor(DesignTokens.inkFaint)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(buckets, id: \.self) { bucket in
                let count = model.bucketCounts[bucket.rawValue] ?? 0
                let isActive = model.selectedBucket == bucket
                Button {
                    try? model.load(bucket: bucket)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(DesignTokens.bucketColor(bucket))
                            .frame(width: 9, height: 9)
                        Text(bucket.title)
                            .font(isActive
                                  ? DesignTokens.Typo.navItem.weight(.semibold)
                                  : DesignTokens.Typo.navItem)
                            .foregroundColor(isActive ? .white : DesignTokens.inkSecondary)
                        Spacer(minLength: 0)
                        if count > 0 {
                            Text("\(count)")
                                .font(DesignTokens.Typo.meta.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(isActive
                                        ? Color.white.opacity(0.25)
                                        : DesignTokens.brandBlueWash))
                                .foregroundColor(isActive ? .white : DesignTokens.brandBlue)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusButton)
                            .fill(isActive ? DesignTokens.brandBlue : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .accessibilityLabel("\(bucket.title), \(count)")
            }
        }
    }

    /// 隐私徽章（规范状态色）+ 设置入口（macOS SettingsLink / iOS sheet，JOURNEY-016）。
    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if os(macOS)
            SettingsLink {
                privacyBadge
            }
            .buttonStyle(.plain)
            #else
            Button { showSettings = true } label: { privacyBadge }
                .buttonStyle(.plain)
            #endif
            Text(L10n.t("privacy.tagline"))
                .font(DesignTokens.Typo.meta.weight(.regular))
                .foregroundColor(DesignTokens.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.borderDefault) }
    }

    private var privacyBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(DesignTokens.statusSuccessFg).frame(width: 6, height: 6)
            Text(L10n.t("privacy.ondevice"))
                .font(DesignTokens.Typo.micro)
        }
        .foregroundColor(DesignTokens.statusSuccessFg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.statusSuccessBg))
        .help(L10n.t("settings.title"))
    }
}

extension Bucket {
    /// 导航可达桶（侧栏与 iPhone bucket 菜单共用，JOURNEY-008 紧凑态入口）。
    /// blocked（CLS-011）刻意不在导航——被拦截邮件仍留镜像可搜索，但不再打扰。
    static let navBuckets: [Bucket] = [.imbox, .feed, .paperTrail, .screener, .setAside]

    /// 手动纠正目标（JOURNEY-017「This isn't X →」菜单；Block 单列一项）。
    static let correctionTargets: [Bucket] = [.imbox, .feed, .paperTrail, .setAside]

    /// 本地化桶名（DESIGN-003；键与 rawValue 同名）。
    var title: String { L10n.t("bucket.\(rawValue)") }
}
