import CoreKit
import SwiftUI

/// 阅读窗格（mockup：操作条/元信息/桶徽标/正文全文/附件/Screener 决策条）。
struct MailReaderView: View {
    @ObservedObject var model: MailoAppModel
    let stableId: String

    @State private var detail: MailoAppModel.MailDetail?

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider().overlay(DesignTokens.borderDefault)
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        metaRow
                        subjectBlock
                        Divider().overlay(DesignTokens.borderDefault).padding(.vertical, 16)
                        bodyText
                        if !detail.attachmentNames.isEmpty {
                            attachments
                        }
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 24)
                }
            } else {
                Text("选择一封邮件")
                    .foregroundColor(DesignTokens.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 0.99, green: 1.0, blue: 1.0))
        .onAppear(perform: reload)
        .onChange(of: stableId) { _ in reload() }
    }

    private func reload() {
        detail = model.mailDetail(stableId: stableId)
    }

    // MARK: 操作条

    private var actionBar: some View {
        HStack(spacing: 8) {
            if model.selectedBucket == .screener {
                screenerDecisions
            } else {
                Button {} label: {
                    Label("Reply", systemImage: "arrow.turn.up.left")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(DesignTokens.brandBlue)
                            .shadow(color: DesignTokens.brandBlue.opacity(0.35), radius: 6, y: 3))
                }
                .buttonStyle(.plain)
                ghostButton("Forward")
                ghostButton("Set Aside")
                Spacer()
                ghostButton("⋯")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    /// Screener 决策条（CLS-010：批准即规则）。
    private var screenerDecisions: some View {
        HStack(spacing: 8) {
            Text("这位发件人该去哪？")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(DesignTokens.bucketColor(.screener))
            decision("→ Imbox", bucket: .imbox, color: DesignTokens.bucketColor(.imbox))
            decision("→ Feed", bucket: .feed, color: DesignTokens.bucketColor(.feed))
            decision("→ Paper", bucket: .paperTrail, color: DesignTokens.bucketColor(.paperTrail))
            decision("Block", bucket: .screener, color: DesignTokens.bucketColor(.screener))
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

    private func ghostButton(_ label: String) -> some View {
        Button {} label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(DesignTokens.inkSecondary)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().strokeBorder(DesignTokens.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 元信息

    private var metaRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(DesignTokens.bucketColor(model.selectedBucket))
                Text(String((detail?.fromAddress ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.fromAddress ?? "")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DesignTokens.inkPrimary)
                Text(detail?.date ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.inkFaint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.selectedBucket.title.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(DesignTokens.bucketColor(model.selectedBucket))
                if model.selectedBucket == .imbox {
                    Text("Real person ✓")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(DesignTokens.inkSecondary)
                }
            }
        }
    }

    private var subjectBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail?.subject ?? "（无主题）")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(DesignTokens.inkPrimary)
        }
        .padding(.top, 18)
    }

    private var bodyText: some View {
        Text(detail?.textBody ?? "（无正文预览）")
            .font(.system(size: 14))
            .lineSpacing(7)
            .foregroundColor(Color(red: 0.16, green: 0.20, blue: 0.27))
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
