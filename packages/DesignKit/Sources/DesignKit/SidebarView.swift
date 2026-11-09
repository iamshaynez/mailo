import CoreKit
import SwiftUI

/// Slate Concept 侧栏（JOURNEY-008/016 · DESIGN-002/004/005）。
/// 品牌标识、Compose 主行动、低干扰导航与常驻本机隐私徽章。
struct SidebarView: View {
    @ObservedObject var model: MailoAppModel
    @ObservedObject var root: MailoRootModel
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMark
            navSection(key: "nav.section.mailboxes", buckets: [.imbox, .feed, .paperTrail])
            navSection(key: "nav.section.decide", buckets: [.screener, .setAside])

            Button {
                model.request(.compose)
            } label: {
                Label(L10n.t("menu.newMessage"), systemImage: "paperplane.fill")
            }
            .buttonStyle(MailoButtonStyle(variant: .primary))
            .modifier(DesignTokens.primaryShadow())
            .disabled(!model.canCompose)
            .padding(.leading, DesignTokens.spacingColumn)
            .padding(.top, 22)
            .accessibilityLabel(L10n.t("menu.newMessage"))

            Spacer(minLength: 16)
            privacyFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.surfaceSidebar)
        #if os(iOS)
        .sheet(isPresented: $showSettings) { MailoSettingsView(root: root) }
        #endif
    }

    private var brandMark: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("m")
                .font(DesignTokens.Typo.iconMedium.weight(.bold))
                .foregroundColor(DesignTokens.inkPrimary)
            Circle()
                .fill(DesignTokens.brandBlue)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, DesignTokens.spacingColumn)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .accessibilityLabel("Mailo")
    }

    private func navSection(key: String, buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t(key))
                .font(DesignTokens.Typo.micro)
                .tracking(1.1)
                .foregroundColor(DesignTokens.inkFaint)
                .padding(.horizontal, DesignTokens.spacingColumn)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(buckets, id: \.self) { bucket in
                let count = model.bucketCounts[bucket.rawValue] ?? 0
                let isActive = model.selectedBucket == bucket
                Button {
                    try? model.load(bucket: bucket)
                } label: {
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(DesignTokens.bucketColor(bucket))
                            .frame(width: 5, height: 5)
                        Text(bucket.title)
                            .font(isActive
                                  ? DesignTokens.Typo.navItem.weight(.semibold)
                                  : DesignTokens.Typo.navItem)
                            .foregroundColor(isActive ? DesignTokens.inkPrimary : DesignTokens.inkSecondary)
                        Spacer(minLength: 4)
                        if count > 0 {
                            Text("\(count)")
                                .font(DesignTokens.Typo.meta.weight(.semibold))
                                .foregroundColor(isActive ? DesignTokens.brandBlue : DesignTokens.inkMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(DesignTokens.brandBlueWash.opacity(isActive ? 1 : 0.55)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if isActive {
                            RoundedRectangle(cornerRadius: DesignTokens.selectionBarWidth / 2)
                                .fill(DesignTokens.inkPrimary)
                                .frame(width: DesignTokens.selectionBarWidth, height: 16)
                                .offset(x: -DesignTokens.spacingColumn)
                        }
                    }
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost))
                .padding(.horizontal, 8)
                .accessibilityLabel("\(bucket.title), \(count)")
            }
        }
    }

    /// 隐私徽章 + 设置入口；深色下仍保持可读的成功色。
    private var privacyFooter: some View {
        VStack(alignment: .center, spacing: 7) {
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
                .font(DesignTokens.Typo.meta)
                .foregroundColor(DesignTokens.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(DesignTokens.spacingColumn)
    }

    private var privacyBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.shield")
                .font(DesignTokens.Typo.iconTiny)
                .foregroundColor(DesignTokens.statusSuccessFg)
            Text(L10n.t("privacy.ondevice"))
                .font(DesignTokens.Typo.micro)
        }
        .foregroundColor(DesignTokens.inkFaint)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(L10n.t("account.menu"))
    }
}

extension Bucket {
    /// 导航可达桶（侧栏与 iPhone bucket 菜单共用，JOURNEY-008）。
    static let navBuckets: [Bucket] = [.imbox, .feed, .paperTrail, .screener, .setAside]
    /// 手动纠正目标（JOURNEY-017）。
    static let correctionTargets: [Bucket] = [.imbox, .feed, .paperTrail, .setAside]
    /// 本地化桶名（DESIGN-003）。
    var title: String { L10n.t("bucket.\(rawValue)") }
}
