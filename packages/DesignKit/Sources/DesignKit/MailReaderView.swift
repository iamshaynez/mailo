import CoreKit
import MirrorKit
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 持久阅读头部的实际高度，供 HTML 使用剩余有限视口（JOURNEY-014）。
private struct HeaderHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 88
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Inbox Reference 阅读窗格：持久头部 + 平坦纸面 + 真实附件 + 快速回复。
/// 内容就绪后才执行进入动画；过期加载由 ReaderLoadGate 拒绝（JOURNEY-014/024 · DESIGN-006）。
struct MailReaderView: View {
    @ObservedObject var model: MailoAppModel
    let stableId: String
    let viewportHeight: CGFloat?
    let viewportWidth: CGFloat?
    let quickReplyStore: Binding<QuickReplyStore>?
    let replyFocusRequest: Int
    let onExpandReply: (() -> Void)?

    init(model: MailoAppModel, stableId: String, viewportHeight: CGFloat? = nil,
         viewportWidth: CGFloat? = nil, quickReplyStore: Binding<QuickReplyStore>? = nil,
         replyFocusRequest: Int = 0, onExpandReply: (() -> Void)? = nil) {
        self.model = model
        self.stableId = stableId
        self.viewportHeight = viewportHeight
        self.viewportWidth = viewportWidth
        self.quickReplyStore = quickReplyStore
        self.replyFocusRequest = replyFocusRequest
        self.onExpandReply = onExpandReply
    }

    @State private var loadState: MailoAppModel.DetailLoadState?
    @AppStorage("allowRemoteImages") private var remoteImagesAllowed = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGate = ReaderLoadGate()
    @State private var bodyOpacity = 1.0
    @State private var bodyOffset: CGFloat = 0
    @State private var headerHeight: CGFloat = 88
    @State private var replyHeight: CGFloat = DesignTokens.quickReplyHeight + 16
    /// 手动归组（JOURNEY-026）：新组名输入弹窗。
    @State private var showNewTag = false
    @State private var newTagName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            persistentHeader
            if model.selectedBucket == .screener {
                screenerDecisions
            }
            Group {
                bodyContent
                if !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments)
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, ReaderSurfaceSpec.leadingPadding)
                }
            }
            .opacity(bodyOpacity)
            .offset(y: bodyOffset)

            if let quickReplyStore {
                QuickReplyView(model: model, stableId: stableId,
                               recipientName: SenderPresentation(senderAddress).name,
                               store: quickReplyStore, replyFocusRequest: replyFocusRequest,
                               onExpand: onExpandReply ?? {})
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ReaderSurface())
        .onPreferenceChange(HeaderHeightPreference.self) { headerHeight = $0 }
        .onPreferenceChange(ReplyHeightPreference.self) { replyHeight = $0 }
        .onAppear { startLoad() }
        .onChange(of: stableId) { _ in startLoad() }
        .onDisappear { loadTask?.cancel() }
        .alert(L10n.t("tag.new"), isPresented: $showNewTag) {
            TextField(L10n.t("tag.namePlaceholder"), text: $newTagName)
            Button(L10n.t("tag.assign")) {
                let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try? model.assignTag(stableId: stableId, tag: MailTag(trimmed))
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("tag.assignHint"))
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch loadState {
        case .loaded(let detail):
            detailBody(detail)
        case .failed(let message):
            failureView(message)
        default:
            loadingView
        }
    }

    private func startLoad() {
        loadTask?.cancel()
        let target = stableId
        let token = loadGate.begin(target)
        loadState = .loading
        bodyOpacity = 1
        bodyOffset = 0

        loadTask = Task {
            var state = await model.loadDetail(stableId: target)
            guard !Task.isCancelled, loadGate.canCommit(token, for: target) else { return }
            if case .loaded(var detail) = state, detail.isUnread {
                model.markRead(stableId: target)
                detail.flags.append("\\Seen")
                state = .loaded(detail)
            }
            guard !Task.isCancelled, loadGate.canCommit(token, for: target) else { return }

            if reduceMotion {
                loadState = state
                bodyOpacity = 1
                bodyOffset = 0
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                bodyOpacity = 0
                bodyOffset = DesignTokens.Motion.readerOffset(reduceMotion: false)
                loadState = state
            }
            await Task.yield()
            guard !Task.isCancelled, loadGate.canCommit(token, for: target) else { return }
            withAnimation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.transition,
                                                        reduceMotion: false)) {
                bodyOpacity = 1
                bodyOffset = 0
            }
        }
    }

    // MARK: 持久头部

    private var persistentHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                MailoAvatar(address: SenderPresentation(senderAddress).address,
                            color: DesignTokens.accent,
                            size: DesignTokens.readerAvatarSize)
                Text(L10n.t("reader.addressLine", SenderPresentation(senderAddress).name, recipientAddress))
                    .font(DesignTokens.Typo.bodyStrong)
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            Text(formattedDate)
                .font(DesignTokens.Typo.micro)
                .foregroundColor(DesignTokens.inkMuted)
                .padding(.leading, DesignTokens.readerAvatarSize + 8)
                .padding(.top, 4)

            Text(subject)
                .font(DesignTokens.Typo.title)
                .foregroundColor(DesignTokens.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: contentWidth, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: HeaderHeightPreference.self, value: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, ReaderSurfaceSpec.leadingPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignTokens.borderHairline).frame(height: 0.5)
        }
    }

    private var readerActions: some View {
        HStack(spacing: 2) {
            Button { model.request(.reply) } label: {
                Image(systemName: "arrow.turn.up.left")
            }
            .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
            .help(L10n.t("reader.reply"))
            .accessibilityLabel(L10n.t("reader.reply"))

            if contentWidth >= 430 {
                Button { model.request(.forward) } label: {
                    Image(systemName: "arrow.turn.up.right")
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                .help(L10n.t("reader.forward"))
                .accessibilityLabel(L10n.t("reader.forward"))

                Button { try? model.setAside(stableId: stableId) } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
                .help(L10n.t("reader.setAside"))
                .accessibilityLabel(L10n.t("reader.setAside"))
            }

            correctionMenu
        }
    }

    private var correctionMenu: some View {
        Menu {
            if contentWidth < 430 {
                Button(L10n.t("reader.forward")) { model.request(.forward) }
                Button(L10n.t("reader.setAside")) { try? model.setAside(stableId: stableId) }
                Divider()
            }
            Section(L10n.t("reader.menu.notBucket", ownBucket.title)) {
                ForEach(Bucket.correctionTargets.filter { $0 != ownBucket }, id: \.self) { bucket in
                    Button(L10n.t("reader.menu.moveTo", bucket.title)) {
                        try? model.reclassify(stableId: stableId, to: bucket)
                    }
                }
                Button(L10n.t("reader.menu.blockSender")) {
                    try? model.reclassify(stableId: stableId, to: .blocked)
                }
            }
            tagSection
            Divider()
            Button(L10n.t("reader.menu.markUnread")) { model.markUnread(stableId: stableId) }
            Button(L10n.t("reader.menu.copySender")) { Clipboard.copy(SenderPresentation(senderAddress).address) }
            Divider()
            Button(L10n.t("reader.menu.delete"), role: .destructive) { model.request(.delete) }
        } label: {
            Image(systemName: "ellipsis")
                .font(DesignTokens.Typo.iconCompact)
                .foregroundColor(DesignTokens.inkSecondary)
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusButton))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.t("reader.menu.notBucket", ownBucket.title))
    }

    /// 归入分组（JOURNEY-026）：与本桶既有组 + 新建组名；发件人级显式规则（CLS-012）。
    @ViewBuilder
    private var tagSection: some View {
        if ownBucket.isTagNavigable {
            Divider()
            Section(L10n.t("tag.assign")) {
                let groups = model.tagCounts[ownBucket.rawValue] ?? []
                ForEach(groups, id: \.tag) { group in
                    Button(group.tag.name) { try? model.assignTag(stableId: stableId, tag: group.tag) }
                }
                Button(L10n.t("tag.new")) {
                    newTagName = ""
                    showNewTag = true
                }
            }
        }
    }

    private var screenerDecisions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(L10n.t("reader.screenerPrompt"))
                    .font(DesignTokens.Typo.caption)
                    .foregroundColor(DesignTokens.bucketColor(.screener))
                decision(L10n.t("reader.screenerTo", Bucket.imbox.title), bucket: .imbox)
                decision(L10n.t("reader.screenerTo", Bucket.feed.title), bucket: .feed)
                decision(L10n.t("reader.screenerTo", Bucket.paperTrail.title), bucket: .paperTrail)
                decision(L10n.t("reader.screenerBlock"), bucket: .blocked)
            }
            .padding(.horizontal, ReaderSurfaceSpec.horizontalPadding)
            .padding(.vertical, 8)
        }
    }

    private func decision(_ label: String, bucket: Bucket) -> some View {
        Button {
            try? model.decideScreener(stableId: stableId, to: bucket)
        } label: {
            Text(label)
        }
        .buttonStyle(MailoButtonStyle(variant: .secondary, accent: DesignTokens.bucketColor(bucket)))
    }

    // MARK: 正文

    @ViewBuilder
    private func detailBody(_ detail: MailoAppModel.MailDetail) -> some View {
        if let html = detail.htmlBody {
            HtmlMailWebView(html: html, allowRemoteImages: remoteImagesAllowed,
                            viewportHeight: bodyHeight, viewportWidth: contentWidth)
                .equatable()
                .frame(width: contentWidth, height: bodyHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ReaderSurfaceSpec.leadingPadding)
        } else if let text = detail.textBody {
            ScrollView {
                Text(text)
                    .font(DesignTokens.Typo.body)
                    .lineSpacing(6)
                    .foregroundColor(DesignTokens.inkBody)
                    .textSelection(.enabled)
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, ReaderSurfaceSpec.leadingPadding)
                Spacer(minLength: 24)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("reader.noBody"))
                    .font(DesignTokens.Typo.body)
                    .foregroundColor(DesignTokens.inkMuted)
                Text(L10n.t("reader.noBody.hint"))
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkFaint)
            }
            .frame(width: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(DesignTokens.accent)
            Text(L10n.t("reader.loading"))
                .font(DesignTokens.Typo.meta)
                .foregroundColor(DesignTokens.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(DesignTokens.Typo.iconMedium)
                .foregroundColor(DesignTokens.inkFaint)
            Text(message)
                .font(DesignTokens.Typo.caption.weight(.regular))
                .foregroundColor(DesignTokens.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(L10n.t("reader.retry")) { startLoad() }
                .buttonStyle(MailoButtonStyle(variant: .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 数据兜底与几何

    private var contentWidth: CGFloat {
        ReferenceLayout.contentWidth(containerWidth: viewportWidth ?? DesignTokens.readingMeasure + 48)
    }

    private var bodyHeight: CGFloat {
        let attachmentHeight: CGFloat = attachments.isEmpty ? 0 : 116
        return ReferenceLayout.bodyHeight(viewportHeight: viewportHeight ?? 820,
                                          headerHeight: headerHeight + attachmentHeight,
                                          replyHeight: quickReplyStore == nil ? 0 : replyHeight)
    }

    private var currentDetail: MailoAppModel.MailDetail? {
        if case .loaded(let detail) = loadState { return detail }
        return nil
    }

    private var summary: BucketEntry? {
        if let entry = model.entries.first(where: { $0.stableId == stableId })
            ?? model.asideEntries.first(where: { $0.stableId == stableId }) {
            return entry
        }
        return model.searchResults.first(where: { $0.stableId == stableId }).map { row in
            BucketEntry(stableId: row.stableId, subject: row.subject, fromAddress: row.fromAddress,
                        snippet: row.snippet, date: row.date, bucket: "search", flags: row.flags)
        }
    }

    private var ownBucket: Bucket {
        currentDetail?.bucket
            ?? summary.flatMap { Bucket(rawValue: $0.bucket) }
            ?? model.selectedBucket
    }

    private var senderAddress: String {
        currentDetail?.fromAddress ?? summary?.fromAddress ?? L10n.t("row.unknown")
    }

    private var recipientAddress: String {
        switch model.phase {
        case .connected(let email): return email
        case .demo: return "you@demo.local"
        default: return L10n.t("reader.me")
        }
    }

    private var subject: String {
        currentDetail?.subject ?? summary?.subject ?? L10n.t("row.noSubject")
    }

    private var attachments: [MailAttachmentPreview] {
        currentDetail?.attachments.map(MailAttachmentPreview.init) ?? []
    }

    private var formattedDate: String {
        guard let raw = currentDetail?.date ?? summary?.date,
              let date = MailDateGrouping.parse(raw) else { return "" }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }
}

/// 真实附件的被动缩略图条（DESIGN-006）；首屏最多三张，其余仅显示数量。
private struct AttachmentStrip: View {
    let attachments: [MailAttachmentPreview]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(attachments.prefix(3).enumerated()), id: \.offset) { _, attachment in
                    AttachmentTile(attachment: attachment)
                }
                if attachments.count > 3 {
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMedia)
                        .fill(DesignTokens.accentWash)
                        .frame(width: 72, height: DesignTokens.attachmentTileHeight)
                        .overlay {
                            Text("+\(attachments.count - 3)")
                                .font(DesignTokens.Typo.title)
                                .foregroundColor(DesignTokens.accentDeep)
                        }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .frame(height: 116)
        .accessibilityLabel(L10n.t("reader.attachments", attachments.count))
    }
}

private struct AttachmentTile: View {
    let attachment: MailAttachmentPreview

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.radiusMedia)
                .fill(DesignTokens.readerChip)
            if let image = platformImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 7) {
                    Image(systemName: attachment.symbolName)
                        .font(DesignTokens.Typo.iconMedium)
                        .foregroundColor(DesignTokens.accentDeep)
                    Text(attachment.filename)
                        .font(DesignTokens.Typo.micro)
                        .foregroundColor(DesignTokens.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: DesignTokens.attachmentTileWidth, height: DesignTokens.attachmentTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMedia))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.radiusMedia)
                .strokeBorder(DesignTokens.borderHairline, lineWidth: 0.5)
        }
        .accessibilityLabel(attachment.filename)
    }

    private var platformImage: Image? {
        guard attachment.isImage, !attachment.data.isEmpty else { return nil }
        #if canImport(AppKit)
        return NSImage(data: Data(attachment.data)).map(Image.init(nsImage:))
        #elseif canImport(UIKit)
        return UIImage(data: Data(attachment.data)).map(Image.init(uiImage:))
        #else
        return nil
        #endif
    }
}
