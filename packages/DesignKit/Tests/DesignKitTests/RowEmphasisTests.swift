import CoreKit
import MirrorKit
import SwiftUI
import Testing

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（JOURNEY-019 未读/已读字重编码）

@MainActor
struct RowEmphasisTests {

    @Test("JOURNEY-019 未读→粗体+绿点；已读→regular；发件人/主题同源映射")
    func journey_019_unread_bold_emphasis() {
        // 映射语义：未读状态唯一决定强调档位
        #expect(RowEmphasis(isUnread: true) == .unread)
        #expect(RowEmphasis(isUnread: false) == .read)

        // 档位差异：未读粗体、已读 regular（sender/subject 两档都区分）
        #expect(RowEmphasis.unread.senderWeight == .bold)
        #expect(RowEmphasis.read.senderWeight == .regular)
        #expect(RowEmphasis.unread.subjectWeight == .semibold)
        #expect(RowEmphasis.read.subjectWeight == .regular)

        // 未读点仅未读保留（视图接线在 MailRowView，此处锁语义源）
        #expect(RowEmphasis.unread.showsDot)
        #expect(!RowEmphasis.read.showsDot)

        // flags 驱动：含 \Seen → read
        let readEntry = BucketEntry(stableId: "r", bucket: "imbox", flags: "\\Seen")
        let unreadEntry = BucketEntry(stableId: "u", bucket: "imbox", flags: "")
        #expect(RowEmphasis(entry: readEntry) == .read)
        #expect(RowEmphasis(entry: unreadEntry) == .unread)
    }
}
