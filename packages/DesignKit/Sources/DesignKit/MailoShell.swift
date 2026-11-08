import CoreKit
import SwiftUI

/// 三栏主壳（mockup Blue Box Classic 全量还原）：
/// 品牌蓝标题栏（搜索/Compose）→ Screener 顶条 → 侧栏 212 / 列表 392 / 阅读 flex。
/// macOS 用 hiddenTitleBar 让内容顶到窗口顶（App 壳配置）；窄屏（iPhone）自动退化为单栏+覆盖式阅读。
public struct MailoShell: View {
    @ObservedObject var model: MailoAppModel
    @State private var selection: String?

    public init(model: MailoAppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .demo, .connected:
                GeometryReader { proxy in
                    if proxy.size.width < 700 {
                        compactLayout
                    } else {
                        wideLayout
                    }
                }
            case .empty, .connecting, .failed:
                AccountSetupView(model: model)
            }
        }
        .preferredColorScheme(.light) // 设计规范 §7：v1 锁浅色（深色模式下未显式色文本会白底白字）
    }

    // MARK: 宽屏三栏

    private var wideLayout: some View {
        VStack(spacing: 0) {
            brandBar
            screenerBanner
            HStack(spacing: 0) {
                SidebarView(model: model)
                Divider().overlay(DesignTokens.borderDefault)
                MailListView(model: model, selection: $selection)
                Divider().overlay(DesignTokens.borderDefault)
                readerPane
            }
            diagnosticBar
        }
        .background(DesignTokens.surfaceMain)
    }

    @ViewBuilder
    private var readerPane: some View {
        if let selection {
            MailReaderView(model: model, stableId: selection)
        } else {
            VStack {
                Spacer()
                Image(systemName: "envelope.open")
                    .font(.system(size: 40))
                    .foregroundColor(DesignTokens.inkFaint.opacity(0.6))
                Text("Imbox is calm.")
                    .foregroundColor(DesignTokens.inkMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.99, green: 1.0, blue: 1.0))
        }
    }

    // MARK: 品牌标题栏（mockup §4：52pt 运通蓝）

    private var brandBar: some View {
        HStack(spacing: 14) {
            #if os(macOS)
            Color.clear.frame(width: 60, height: 10) // 系统红绿灯让位
            #endif
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .overlay(Text("M").font(.system(size: 12, weight: .heavy)).foregroundColor(DesignTokens.brandBlue))
                Text("Mailo")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                Text("搜索全部邮件…")
                    .font(.system(size: 12.5))
                Spacer(minLength: 4)
                Text("⌘K")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)))
            }
            .foregroundColor(Color.white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(maxWidth: 420)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.28), lineWidth: 1))

            Spacer()

            Button {} label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                    Text("Compose")
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: DesignTokens.titleBarHeight)
        .background(DesignTokens.brandBlue.ignoresSafeArea(edges: .top))
    }

    // MARK: Screener 顶条（mockup §5）

    @ViewBuilder
    private var screenerBanner: some View {
        let count = model.bucketCounts[Bucket.screener.rawValue] ?? 0
        if count > 0 {
            HStack(spacing: 8) {
                Circle().fill(DesignTokens.bucketColor(.screener)).frame(width: 7, height: 7)
                Text("\(count) 位新发件人正在 Screener 等待 — 批准一次，永久归类。")
                    .font(.system(size: 12.5))
                Spacer()
                Button {
                    selection = nil
                    try? model.load(bucket: .screener)
                } label: {
                    Text("Review →")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(DesignTokens.brandBlue)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(DesignTokens.brandBlueDeep)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(DesignTokens.brandBlueWash)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(red: 0.81, green: 0.89, blue: 0.96)).frame(height: 1)
            }
        }
    }

    // MARK: 诊断条（排查真实数据的第一现场）

    @ViewBuilder
    private var diagnosticBar: some View {
        HStack(spacing: 12) {
            Text(model.lastSyncSummary.isEmpty ? model.store.schemaDiagnostics() : model.lastSyncSummary)
            Spacer()
            Text(model.store.schemaDiagnostics())
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundColor(DesignTokens.inkMuted)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(DesignTokens.brandBlueWash)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.borderDefault) }
    }

    // MARK: 窄屏（iPhone）：单栏 + 覆盖式阅读

    private var compactLayout: some View {
        VStack(spacing: 0) {
            brandBar
            screenerBanner
            ZStack {
                MailListView(model: model, selection: .constant(nil))
                    .frame(maxWidth: .infinity)
                if let selection {
                    MailReaderView(model: model, stableId: selection)
                        .background(DesignTokens.surfaceMain)
                        .overlay(alignment: .topLeading) {
                            Button {
                                self.selection = nil
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignTokens.brandBlue)
                                    .padding(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.move(edge: .trailing))
                }
            }
            diagnosticBar
        }
        .background(DesignTokens.surfaceMain)
    }
}
