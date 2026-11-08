import CoreKit
import SwiftUI

/// 阅读窗格（JOURNEY-011/012/013/017 · CLS-010/011）：
/// 操作条动作全部接通（Reply/Forward/Set Aside/⋯ 纠正菜单），Screener 决策四键，
/// 打开即标已读，bucket 徽标用邮件自身归类（而非当前列表桶）。
struct MailReaderView: View {
    @ObservedObject var model: MailoAppModel
    let stableId: String

    @State private var loadState: MailoAppModel.DetailLoadState?
    @State private var retryNonce = 0

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider().overlay(DesignTokens.borderDefault)
            switch loadState {
            case .loaded(let detail):
                detailContent(detail)
            case .failed(let message):
                failureView(message)
            default:
                loadingView
            }
        }
        .background(DesignTokens.surfaceWash)
        .task(id: "\(stableId)#\(retryNonce)") {
            loadState = .loading
            var state = await model.loadDetail(stableId: stableId)
            // 打开即标已读（JOURNEY-013）：正文到手后生效
            if case .loaded(var d) = state, d.isUnread {
                model.markRead(stableId: stableId)
                d.flags.append("\\Seen")
                state = .loaded(d)
            }
            loadState = state
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading message…")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(DesignTokens.inkFaint.opacity(0.7))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(DesignTokens.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                retryNonce += 1 // .task(id:) 重跑（JOURNEY-014 重试）
            } label: {
                Text("Retry")
                    .font(.system(size: 12.5, weight: .bold))
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(DesignTokens.brandBlue).opacity(0.12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailContent(_ detail: MailoAppModel.MailDetail) -> some View {
        VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            metaRow
                            subjectBlock
                            Divider().overlay(DesignTokens.borderDefault).padding(.vertical, 16)
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.top, 24)
                    }
                    .frame(height: detail.htmlBody == nil ? 0 : nil, alignment: .top)
                    .frame(maxHeight: detail.htmlBody == nil ? 0 : .infinity, alignment: .top)

                    // 正文：HTML 走 WKWebView 沙箱（自滚动）；纯文本走原生 Text
                    if let html = detail.htmlBody {
                        HtmlMailWebView(html: html)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 12)
                    } else {
                        ScrollView {
                            bodyText
                            if !detail.attachmentNames.isEmpty { attachments }
                            Spacer(minLength: 40)
                        }
                    }
                }
        }
    }

    // MARK: 操作条（动作全部接通，JOURNEY-011/012）

    private var actionBar: some View {
        HStack(spacing: 8) {
            if model.selectedBucket == .screener {
                screenerDecisions
            } else {
                Button {
                    model.request(.reply)
                } label: {
                    Label("Reply", systemImage: "arrow.turn.up.left")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(DesignTokens.brandBlue)
                            .shadow(color: DesignTokens.brandBlue.opacity(0.35), radius: 6, y: 3))
                }
                .buttonStyle(.plain)
                Button {
                    model.request(.forward)
                } label: {
                    ghostLabel("Forward")
                }
                Button {
                    try? model.setAside(stableId: stableId)
                } label: {
                    ghostLabel("Set Aside")
                }
                Spacer()
                correctionMenu
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func ghostLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(DesignTokens.inkSecondary)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().strokeBorder(DesignTokens.borderStrong, lineWidth: 1))
    }

    /// ⋯ 菜单（JOURNEY-017 手动纠正常驻入口 + 标未读 + 拷贝）。
    private var correctionMenu: some View {
        Menu {
            Section("This isn't \(model.selectedBucket.title) →") {
                ForEach(Bucket.correctionTargets, id: \.self) { bucket in
                    Button("Move to \(bucket.title)") {
                        try? model.reclassify(stableId: stableId, to: bucket)
                    }
                }
                Button("Block Sender") {
                    try? model.reclassify(stableId: stableId, to: .blocked)
                }
            }
            Divider()
            Button("Mark Unread") { model.markUnread(stableId: stableId) }
            Button("Copy Sender") { Clipboard.copy(currentDetail?.fromAddress ?? "") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignTokens.inkSecondary)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().strokeBorder(DesignTokens.borderStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Screener 决策条（CLS-010/011）：批准即规则，Block → blocked 桶。
    private var screenerDecisions: some View {
        HStack(spacing: 8) {
            Text("Where should this sender go?")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(DesignTokens.bucketColor(.screener))
            decision("→ Imbox", bucket: .imbox, color: DesignTokens.bucketColor(.imbox))
            decision("→ Feed", bucket: .feed, color: DesignTokens.bucketColor(.feed))
            decision("→ Paper", bucket: .paperTrail, color: DesignTokens.bucketColor(.paperTrail))
            decision("Block", bucket: .blocked, color: DesignTokens.bucketColor(.blocked))
            Spacer()
        }
    }

    private func decision(_ label: String, bucket: Bucket, color: Color) -> some View {
        Button {
            try? model.decideScreener(stableId: stableId, to: bucket)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    // MARK: 元信息（bucket 徽标用邮件自身归类，JOURNEY-003 正确性）

    private var ownBucket: Bucket { currentDetail?.bucket ?? model.selectedBucket }

    private var currentDetail: MailoAppModel.MailDetail? {
        if case .loaded(let d) = loadState { return d }
        return nil
    }

    /// 内容构建器沿用可选 detail 名（loading 期不渲染内容）。
    private var detail: MailoAppModel.MailDetail? { currentDetail }

    private var metaRow: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignTokens.bucketColor(ownBucket))
                Text(String((detail?.fromAddress ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.fromAddress ?? "")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DesignTokens.inkPrimary)
                Text(formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.inkFaint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ownBucket.title.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(DesignTokens.bucketColor(ownBucket))
                if ownBucket == .imbox {
                    Text("Real person ✓")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DesignTokens.inkSecondary)
                }
            }
        }
    }

    private var formattedDate: String {
        guard let raw = currentDetail?.date else { return "" }
        return MailDateGrouping.rfc2822.date(from: raw)?
            .formatted(.dateTime.year().month(.abbreviated).day().hour().minute()) ?? raw
    }

    private var subjectBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail?.subject ?? "(no subject)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(DesignTokens.inkPrimary)
        }
        .padding(.top, 18)
    }

    private var bodyText: some View {
        Text(detail?.textBody ?? "(no body preview)")
            .font(.system(size: 14))
            .lineSpacing(7)
            .foregroundColor(DesignTokens.inkBody)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(detail?.attachmentNames ?? [], id: \.self) { name in
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignTokens.brandBlueWash)
                        .frame(width: 30, height: 30)
                        .overlay(Text("📎").font(.system(size: 13)))
                    Text(name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DesignTokens.inkSecondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(DesignTokens.borderDefault, lineWidth: 1))
            }
        }
        .padding(.top, 20)
    }
}
