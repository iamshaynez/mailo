import Testing
import CoreKit

@testable import MirrorKit

// MARK: - 用例库：docs/specs/STORE-usecases.md（STORE-012 回填水位查询）

struct Store012Tests {

    @Test("STORE-012 oldestUid：最早已知 uid、folder 隔离、空库 nil")
    func store_012_oldest_uid() throws {
        let store = try MirrorStore()
        #expect(try store.oldestUid(folder: "INBOX") == nil, "空库返回 nil")

        // uid 含空洞（3/7/9）：水位取 min 而非连续假设
        for uid in [9, 3, 7] {
            try store.upsert(MailRow(stableId: "m\(uid)", account: "primary", folder: "INBOX",
                                     uid: uid, flags: [], subject: "s\(uid)"))
        }
        #expect(try store.oldestUid(folder: "INBOX") == 3)

        // folder 隔离：Trash 里的行不抬升 INBOX 水位
        try store.upsert(MailRow(stableId: "t1", account: "primary", folder: "Trash",
                                 uid: 1, flags: [], subject: "t"))
        #expect(try store.oldestUid(folder: "INBOX") == 3)
        #expect(try store.oldestUid(folder: "Trash") == 1)
    }
}
