import Testing

@testable import MirrorKit

// MARK: - 用例库：docs/specs/STORE-usecases.md（STORE-010 本地 flags 更新）

struct Store010Tests {

    @Test("STORE-010 setFlags：并集幂等、可移除、不动分类行")
    func store_010_set_flags() throws {
        let store = try MirrorStore()
        try store.upsert(MailRow(stableId: "m1", account: "primary", folder: "INBOX", uid: 1,
                                 flags: ["\\Flagged"], subject: "s"))
        try store.freeze(ClassificationRow(stableId: "m1", bucket: .imbox, reason: "t"))

        try store.setFlags(stableId: "m1", merge: ["\\Seen"])
        #expect(try store.mail(stableId: "m1")?.flagList.sorted() == ["\\Flagged", "\\Seen"])

        // 幂等：重复 merge 不重复追加
        try store.setFlags(stableId: "m1", merge: ["\\Seen"])
        #expect(try store.mail(stableId: "m1")?.flagList.filter { $0 == "\\Seen" }.count == 1)

        // 移除（mark unread 路径）
        try store.setFlags(stableId: "m1", remove: ["\\Seen"])
        #expect(try store.mail(stableId: "m1")?.flagList == ["\\Flagged"])

        // 分类行不受影响
        #expect(try store.entries(bucket: .imbox).count == 1)

        // 不存在的 stableId 静默无操作（防崩溃）
        try store.setFlags(stableId: "ghost", merge: ["\\Seen"])
    }
}
