import CoreKit
import SwiftUI

/// 三栏主壳（设计规范 §4：212 / 392 / flex；Blue Box Classic）。
/// macOS 常驻三栏；iOS 由 NavigationSplitView 自动降级推拉（规范 §8）。
public struct MailoShell: View {
    @ObservedObject var model: MailoAppModel
    @State private var entry: BucketEntry?

    public init(model: MailoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(DesignTokens.sidebarWidth)
        } content: {
            mailList
                .navigationSplitViewColumnWidth(DesignTokens.listWidth)
        } detail: {
            reader
        }
        .background(DesignTokens.surfaceMain)
    }

    private var sidebar: some View {
        List {
            Section("FOR YOU") {
                ForEach([Bucket.imbox, .feed, .paperTrail], id: \.self) { bucket in
                    Button {
                        try? model.load(bucket: bucket)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(DesignTokens.bucketColor(bucket))
                                .frame(width: 9, height: 9)
                            Text(bucket.title).foregroundColor(DesignTokens.inkSecondary)
                            Spacer()
                        }
                    }
                    .listRowBackground(
                        model.selectedBucket == bucket
                            ? DesignTokens.brandBlueWash
                            : Color.clear
                    )
                }
            }
            Section("DECIDE") {
                Label {
                    Text("Screener").foregroundColor(DesignTokens.inkSecondary)
                } icon: {
                    Circle().fill(DesignTokens.bucketColor(.screener)).frame(width: 9, height: 9)
                }
                .badge(model.screenerCount)
            }
        }
        .listStyle(.sidebar)
    }

    private var mailList: some View {
        List(model.entries, id: \.stableId, selection: $entry) { item in
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fromAddress ?? "unknown")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(DesignTokens.inkPrimary)
                Text(item.subject ?? "（无主题）")
                    .font(.system(size: 13.5))
                    .foregroundColor(DesignTokens.inkPrimary)
                    .lineLimit(1)
                Text(item.snippet ?? "")
                    .font(.system(size: 11.5))
                    .foregroundColor(DesignTokens.inkMuted)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if model.entries.isEmpty {
                Text("Imbox is calm.")
                    .foregroundColor(DesignTokens.inkMuted)
            }
        }
    }

    private var reader: some View {
        ScrollView {
            if let entry {
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.subject ?? "")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(DesignTokens.inkPrimary)
                    Text("\(entry.fromAddress ?? "") · \(entry.date ?? "")")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.inkMuted)
                    Divider()
                    Text(entry.snippet ?? "")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.inkSecondary)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(30)
            } else {
                Text("Select a message")
                    .foregroundColor(DesignTokens.inkMuted)
            }
        }
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
