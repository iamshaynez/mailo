import CoreKit
import SwiftUI

/// 侧栏（mockup §4：212pt；账户行 / MAILBOXES 徽章 / DECIDE / 隐私徽章）。
struct SidebarView: View {
    @ObservedObject var model: MailoAppModel

    var body: some View {
        VStack(spacing: 0) {
            accountRow
            Divider().overlay(DesignTokens.borderDefault)

            navSection(title: "MAILBOXES", buckets: [.imbox, .feed, .paperTrail])
            navSection(title: "DECIDE", buckets: [.screener, .setAside])

            Spacer(minLength: 0)

            privacyFooter
        }
        .background(DesignTokens.surfaceMain)
        .frame(width: DesignTokens.sidebarWidth)
    }

    private var accountRow: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(DesignTokens.brandBlue)
                Text(String(accountInitial))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 24, height: 24)
            Text(accountLabel)
                .font(.system(size: 13))
                .foregroundColor(DesignTokens.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var accountLabel: String {
        if case .connected(let email) = model.phase { return email }
        if case .demo = model.phase { return "demo@local" }
        return "未连接"
    }

    private var accountInitial: String {
        String(accountLabel.prefix(1)).uppercased()
    }

    private func navSection(title: String, buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
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
                            .font(.system(size: 13.5, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? .white : DesignTokens.inkSecondary)
                        Spacer(minLength: 0)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 11.5, weight: .bold))
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
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isActive ? DesignTokens.brandBlue : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.18, green: 0.42, blue: 0.20)).frame(width: 6, height: 6)
                Text("100% on-device")
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundColor(Color(red: 0.25, green: 0.42, blue: 0.20))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.94, green: 0.96, blue: 0.93)))
            Text("No cloud. No tracking. Ever.")
                .font(.system(size: 11))
                .foregroundColor(DesignTokens.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.borderDefault) }
    }
}

extension Bucket {
    var title: String {
        switch self {
        case .imbox: return "Imbox"
        case .feed: return "Feed"
        case .paperTrail: return "Paper Trail"
        case .screener: return "Screener"
        case .setAside: return "Set Aside"
        }
    }
}
