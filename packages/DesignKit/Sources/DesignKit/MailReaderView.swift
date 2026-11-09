import CoreKit
import MirrorKit
import SwiftUI

/// Slate Concept v2.1 阅读窗格：持久头部 + 居中正文 + 固定 WebKit 视口。
/// 内容就绪后才执行进入动画；过期加载由 ReaderLoadGate 拒绝（JOURNEY-014 / DESIGN-006）。
struct MailReaderView: View {
    @ObservedObject var model: MailoAppModel
    let stableId: String
    let viewportHeight: CGFloat?
    let viewportWidth: CGFloat?

    init(model: MailoAppModel, stableId: String, viewportHeight: CGFloat? = nil,
         viewportWidth: CGFloat? = nil) {
        self.model = model
        self.stableId = stableId
        self.viewportHeight = viewportHeight
        self.viewportWidth = viewportWidth
    }

    @State private var loadState: MailoAppModel.DetailLoadState?
    @AppStorage("allowRemoteImages") private var remoteImagesAllowed = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadGate = ReaderLoadGate()
    @State private var bodyOpacity = 1.0
    @State private var bodyOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            persistentHeader
            if model.selectedBucket == .screener {
                screenerDecisions
            }
            bodyContent
                .opacity(bodyOpacity)
                .offset(x: bodyOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ReaderSurface())
        .onAppear { startLoad() }
        .onChange(of: stableId) { _ in startLoad() }
        .onDisappear { loadTask?.cancel() }
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
            HStack(alignment: .center, spacing: 10) {
                if !hasAvatarGutter {
                    MailoAvatar(address: senderAddress,
                                color: DesignTokens.bucketColor(ownBucket),
                                size: DesignTokens.readerAvatarSize)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(senderAddress)
                        .font(DesignTokens.Typo.micro)
                        .tracking(1.1)
                        .foregroundColor(DesignTokens.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(ownBucket.title.uppercased())
                        .font(DesignTokens.Typo.micro)
                        .foregroundColor(DesignTokens.bucketColor(ownBucket))
                }
                Spacer(minLength: 8)
                Text(formattedDate)
                    .font(DesignTokens.Typo.meta)
                    .foregroundColor(DesignTokens.inkMuted)
                    .lineLimit(1)
                readerActions
            }
            .overlay(alignment: .leading) {
                if hasAvatarGutter {
                    MailoAvatar(address: senderAddress,
                                color: DesignTokens.bucketColor(ownBucket),
                                size: DesignTokens.readerAvatarSize)
                        .offset(x: -50)
                }
            }

            if !attachmentNames.isEmpty {
                MailoChipFlowLayout(spacing: 6, rowSpacing: 4) {
                    ForEach(attachmentNames, id: \.self) { name in
                        MailoAttachmentChip(name: name)
                    }
                }
                .padding(.top, 14)
            }

            Text(subject)
                .font(DesignTokens.Typo.title)
                .foregroundColor(DesignTokens.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
        }
        .frame(maxWidth: DesignTokens.readingMeasure, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var readerActions: some View {
        HStack(spacing: 2) {
            Button { model.request(.reply) } label: {
                Image(systemName: "arrow.turn.up.left")
            }
            .buttonStyle(MailoButtonStyle(variant: .ghost, isIcon: true))
            .help(L10n.t("reader.reply"))
            .accessibilityLabel(L10n.t("reader.reply"))

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

            correctionMenu
        }
    }

    private var correctionMenu: some View {
        Menu {
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
            Divider()
            Button(L10n.t("reader.menu.markUnread")) { model.markUnread(stableId: stableId) }
            Button(L10n.t("reader.menu.copySender")) { Clipboard.copy(senderAddress) }
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
            .padding(.horizontal, 24)
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
                            viewportHeight: viewportHeight, viewportWidth: viewportWidth)
                .equatable()
                .frame(width: viewportWidth.map { max(0, $0 - 52) },
                       height: max(160, (viewportHeight ?? 820) - 220))
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        } else if let text = detail.textBody {
            ScrollView {
                Text(text)
                    .font(DesignTokens.Typo.body)
                    .lineSpacing(7)
                    .foregroundColor(DesignTokens.inkBody)
                    .textSelection(.enabled)
                    .frame(maxWidth: DesignTokens.readingMeasure, alignment: .leading)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 40)
            }
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
            .frame(maxWidth: DesignTokens.readingMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(DesignTokens.brandBlue)
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

    // MARK: 数据兜底

    private var hasAvatarGutter: Bool {
        (viewportWidth ?? 1000) >= ReaderSurfaceSpec.headerMeasure + 44
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

    private var subject: String {
        currentDetail?.subject ?? summary?.subject ?? L10n.t("row.noSubject")
    }

    private var attachmentNames: [String] {
        currentDetail?.attachmentNames ?? []
    }

    private var formattedDate: String {
        guard let raw = currentDetail?.date ?? summary?.date,
              let date = MailDateGrouping.parse(raw) else { return "" }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }
}
