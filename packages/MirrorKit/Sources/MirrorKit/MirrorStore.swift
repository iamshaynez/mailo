import CoreKit
import Foundation
import GRDB

/// 邮件镜像行（stableID 为全局主键，UID 仅是可刷新的缓存属性，STORE-005）。
public struct MailRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "mail"

    public var stableId: String
    public var account: String
    public var folder: String
    public var uid: Int
    public var flags: String
    public var subject: String?
    public var fromAddress: String?
    public var snippet: String?
    public var date: String?
    public var raw: Data?

    public init(stableId: String, account: String, folder: String, uid: Int,
                flags: [String] = [], subject: String? = nil, fromAddress: String? = nil,
                snippet: String? = nil, date: String? = nil, raw: Data? = nil) {
        self.stableId = stableId
        self.account = account
        self.folder = folder
        self.uid = uid
        self.flags = flags.joined(separator: " ")
        self.subject = subject
        self.fromAddress = fromAddress
        self.snippet = snippet
        self.date = date
        self.raw = raw
    }

    public var flagList: [String] {
        flags.split(separator: " ").map(String.init)
    }
}

/// 分类冻结行（基线 D8：结果冻结幂等的持久化形态）。
/// tag 为桶内子分组（CLS-012/013，v4-tags 列）：冻结只锁桶，tag 可随后续归组改写。
public struct ClassificationRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "classification"

    public var stableId: String
    public var bucket: String
    public var reason: String
    public var tag: String?

    public init(stableId: String, bucket: Bucket, reason: String, tag: MailTag? = nil) {
        self.stableId = stableId
        self.bucket = bucket.rawValue
        self.reason = reason
        self.tag = tag?.name
    }
}

/// 组过滤（STORE-013）：all 整桶 / tagged(T) 只看组 / untagged 只看未分组。
public enum TagFilter: Hashable, Sendable {
    case all
    case tagged(MailTag)
    case untagged
}

/// 组计数行（STORE-013）：侧栏组列表的数据源。
public struct TagCount: Equatable, Sendable {
    public var tag: MailTag
    public var count: Int

    public init(tag: MailTag, count: Int) {
        self.tag = tag
        self.count = count
    }
}

/// bucket 视图行：邮件 + 归类（UI 列表消费的形态）。
public struct BucketEntry: Codable, Equatable, Hashable, Sendable, FetchableRecord {
    public var stableId: String
    public var subject: String?
    public var fromAddress: String?
    public var snippet: String?
    public var date: String?
    public var bucket: String
    public var flags: String

    public init(stableId: String, subject: String? = nil, fromAddress: String? = nil,
                snippet: String? = nil, date: String? = nil, bucket: String, flags: String = "") {
        self.stableId = stableId
        self.subject = subject
        self.fromAddress = fromAddress
        self.snippet = snippet
        self.date = date
        self.bucket = bucket
        self.flags = flags
    }

}

/// 本地镜像存储（GRDB/SQLite + FTS5 trigram）。
/// v1 用内存数据库跑测试；生产以文件路径初始化同一 schema。
public final class MirrorStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String? = nil) throws {
        if let path {
            self.dbQueue = try DatabaseQueue(path: path)
        } else {
            self.dbQueue = try DatabaseQueue() // 内存库（测试）
        }
        try Self.migrate(dbQueue)
    }

    /// 项目标准（STORE-009 / MIGRATIONS.md）：每版本一个迁移、自动执行、
    /// **已合入的迁移永不修改，只允许新增**；本清单与登记表必须同步维护。
    static let releasedMigrations = ["v1", "v2-sync-state", "v3-meta", "v4-tags"]

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "mail") { t in
                t.primaryKey(["stableId"], onConflict: .replace)
                t.column("stableId", .text).notNull()
                t.column("account", .text).notNull()
                t.column("folder", .text).notNull()
                t.column("uid", .integer).notNull()
                t.column("flags", .text).notNull().defaults(to: "")
                t.column("subject", .text)
                t.column("fromAddress", .text)
                t.column("snippet", .text)
                t.column("date", .text)
                t.column("raw", .blob)
            }
            try db.create(table: "classification") { t in
                t.primaryKey(["stableId"], onConflict: .replace)
                t.column("stableId", .text).notNull()
                t.column("bucket", .text).notNull()
                t.column("reason", .text).notNull()
            }
            // FTS5 外部内容表 + trigram（SQLite 3.34+，中文子串可搜，STORE-003）。
            // 用原始 SQL + 手写触发器，避免对 GRDB FTS5 DSL 的版本耦合。
            try db.create(table: "sync_state") { t in
                t.primaryKey(["folder"], onConflict: .replace)
                t.column("folder", .text).notNull()
                t.column("uidValidity", .integer).notNull()
                t.column("highestUid", .integer).notNull()
            }
            try db.execute(sql: """
            CREATE VIRTUAL TABLE mail_fts USING fts5(
                subject, fromAddress, snippet,
                tokenize='trigram',
                content='mail', content_rowid='rowid'
            )
            """)
            try db.execute(sql: """
            CREATE TRIGGER mail_ai AFTER INSERT ON mail BEGIN
                INSERT INTO mail_fts(rowid, subject, fromAddress, snippet)
                VALUES (new.rowid, new.subject, new.fromAddress, new.snippet);
            END;
            CREATE TRIGGER mail_ad AFTER DELETE ON mail BEGIN
                INSERT INTO mail_fts(mail_fts, rowid, subject, fromAddress, snippet)
                VALUES ('delete', old.rowid, old.subject, old.fromAddress, old.snippet);
            END;
            CREATE TRIGGER mail_au AFTER UPDATE ON mail BEGIN
                INSERT INTO mail_fts(mail_fts, rowid, subject, fromAddress, snippet)
                VALUES ('delete', old.rowid, old.subject, old.fromAddress, old.snippet);
                INSERT INTO mail_fts(rowid, subject, fromAddress, snippet)
                VALUES (new.rowid, new.subject, new.fromAddress, new.snippet);
            END;
            """)
        }
        // v2 为存量库补 sync_state（曾误改入 v1 的修正，STORE-008 教训）
        migrator.registerMigration("v2-sync-state") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS sync_state(
                folder TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE,
                uidValidity INTEGER NOT NULL,
                highestUid INTEGER NOT NULL
            )
            """)
        }
        // v3：版本绑定元数据（STORE-009）
        migrator.registerMigration("v3-meta") { db in
            try db.create(table: "meta") { t in
                t.primaryKey(["key"], onConflict: .replace)
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
            }
        }
        // v4：桶内子分组（STORE-013）——classification 加可空 tag 列，只加不改。
        migrator.registerMigration("v4-tags") { db in
            try db.execute(sql: "ALTER TABLE classification ADD COLUMN tag TEXT")
        }
        return migrator
    }

    static func migrate(_ db: DatabaseQueue) throws {
        try makeMigrator().migrate(db)
    }

    /// 已应用迁移清单（与 MIGRATIONS.md 登记表对齐，STORE-009）。
    public var appliedMigrations: [String] {
        (try? dbQueue.read { db in
            try Self.makeMigrator().appliedMigrations(db)
        }) ?? []
    }

    public var schemaVersion: Int { appliedMigrations.count }

    /// 记录当前 app 版本到 meta（打开库时由调用方执行；诊断与排障用）。
    public func recordAppVersion(_ version: String) {
        let schema = schemaVersion // 先取（read）再写——write 块内不可嵌套访问（GRDB 非重入）
        try? dbQueue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO meta(key, value) VALUES ('appVersion', ?)",
                           arguments: [version])
            try db.execute(sql: "INSERT OR REPLACE INTO meta(key, value) VALUES ('schemaVersion', ?)",
                           arguments: ["\(schema)"])
            try db.execute(sql: "INSERT OR REPLACE INTO meta(key, value) VALUES ('migratedAt', ?)",
                           arguments: [ISO8601DateFormatter().string(from: Date())])
        }
    }

    /// 诊断串（如 "db schema v3 · app 0.1.0"）。
    public func schemaDiagnostics() -> String {
        let app = (try? dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'appVersion'")
        }) ?? "?"
        return "db schema v\(schemaVersion) · app \(app)"
    }

    // MARK: - 写

    /// 邮件事件入库（幂等，STORE-001/005）。
    public func upsert(_ row: MailRow) throws {
        try dbQueue.write { db in
            try row.save(db)
        }
    }

    /// 分类冻结写入（STORE-004）。
    public func freeze(_ row: ClassificationRow) throws {
        try dbQueue.write { db in
            try row.save(db)
        }
    }

    /// 本地 flags 并集/差集更新（STORE-010）：markSeen/markUnread 的本地优先路径。
    /// 幂等：merge 不重复追加；stableId 不存在时静默无操作。不动服务器、不动分类行。
    public func setFlags(stableId: String, merge: [String] = [], remove: [String] = []) throws {
        try dbQueue.write { db in
            guard var row = try MailRow.fetchOne(db, key: stableId) else { return }
            var flags = row.flagList
            for flag in merge where !flags.contains(flag) { flags.append(flag) }
            if !remove.isEmpty { flags.removeAll { remove.contains($0) } }
            row.flags = flags.joined(separator: " ")
            try row.update(db)
        }
    }

    /// 回填水位查询（STORE-012）：文件夹内最早已知 uid（min(uid)，按需回填从此向下推进）。
    /// 空库/空文件夹返回 nil；无 schema 迁移。
    public func oldestUid(folder: String) throws -> Int? {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT MIN(uid) FROM mail WHERE folder = ?", arguments: [folder])
        }
    }

    /// 本地删行（STORE-011）：mail 行与 classification 行同一事务删除。
    /// FTS 由既有 AFTER DELETE 触发器自动一致；幂等（不存在静默无操作）。无 schema 迁移。
    public func deleteMail(stableId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM classification WHERE stableId = ?", arguments: [stableId])
            try db.execute(sql: "DELETE FROM mail WHERE stableId = ?", arguments: [stableId])
        }
    }

    /// 无正文邮件清单（诊断探针：raw 未回填的邮件）。
    public func mailsWithoutBody() throws -> [(stableId: String, uid: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT stableId, uid FROM mail WHERE raw IS NULL ORDER BY uid LIMIT 1")
            return rows.map { (stableId: $0["stableId"] ?? "", uid: $0["uid"] ?? 0) }
        }
    }

    /// 无日期邮件清单（JOURNEY-020 存量回填：date 断链时期入库的邮件按 ENVELOPE 补）。
    public func mailsWithoutDate() throws -> [(stableId: String, uid: Int)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT stableId, uid FROM mail WHERE date IS NULL OR date = '' ORDER BY uid
                """)
            return rows.map { (stableId: $0["stableId"] ?? "", uid: $0["uid"] ?? 0) }
        }
    }

    /// 仅补信封字段（date 覆盖；subject/from 仅当当前为空时补），不动 flags/raw/snippet
    /// （JOURNEY-020：存量回填安全路径——不冲掉已回填正文与本地旗标）。
    public func updateEnvelope(stableId: String, date: String?, subject: String?, fromAddress: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE mail SET
                    date = ?,
                    subject = COALESCE(NULLIF(subject, ''), ?),
                    fromAddress = COALESCE(NULLIF(fromAddress, ''), ?)
                WHERE stableId = ?
                """, arguments: [date, subject, fromAddress, stableId])
        }
    }

    // MARK: - 读

    /// bucket 视图：该桶邮件按日期倒序（STORE-002）。date 为字符串（RFC2822 原文），
    /// v1 排序按字符串逆序（ISO 类格式下近似时间序），M1 解析为 epoch 后优化。
    public func entries(bucket: Bucket, limit: Int = 200) throws -> [BucketEntry] {
        try dbQueue.read { db in
            let sql = """
            SELECT m.stableId, m.subject, m.fromAddress, m.snippet, m.date, m.flags, c.bucket
            FROM mail m JOIN classification c ON c.stableId = m.stableId
            WHERE c.bucket = ?
            ORDER BY m.date DESC LIMIT ?
            """
            return try BucketEntry.fetchAll(db, sql: sql, arguments: [bucket.rawValue, limit])
        }
    }

    /// 组过滤视图（STORE-013）：TagFilter 语义——all 整桶 / tagged 只看组 / untagged 只看未分组。
    /// 排序与 limit 语义同 entries(bucket:)。
    public func entries(bucket: Bucket, tag: TagFilter, limit: Int = 200) throws -> [BucketEntry] {
        try dbQueue.read { db in
            let condition: String
            let arguments: [DatabaseValueConvertible]
            switch tag {
            case .all:
                condition = ""
                arguments = [bucket.rawValue, limit]
            case .tagged(let mailTag):
                condition = " AND c.tag = ?"
                arguments = [bucket.rawValue, mailTag.name, limit]
            case .untagged:
                condition = " AND (c.tag IS NULL OR c.tag = '')"
                arguments = [bucket.rawValue, limit]
            }
            let sql = """
            SELECT m.stableId, m.subject, m.fromAddress, m.snippet, m.date, m.flags, c.bucket
            FROM mail m JOIN classification c ON c.stableId = m.stableId
            WHERE c.bucket = ?\(condition)
            ORDER BY m.date DESC LIMIT ?
            """
            return try BucketEntry.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// 组计数（STORE-013）：组名+计数，按计数倒序；未分组不计入；空组不出现。
    public func tagCounts(bucket: Bucket) throws -> [TagCount] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tag, COUNT(*) AS n FROM classification
                WHERE bucket = ? AND tag IS NOT NULL AND tag != ''
                GROUP BY tag ORDER BY n DESC, tag ASC
                """, arguments: [bucket.rawValue])
            return rows.compactMap { row in
                guard let name: String = row["tag"] else { return nil }
                return TagCount(tag: MailTag(name), count: row["n"] ?? 0)
            }
        }
    }

    /// 单封改组（STORE-013）：幂等；tag=nil 清组；不影响 bucket/reason/冻结。
    public func setTag(stableId: String, tag: MailTag?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE classification SET tag = ? WHERE stableId = ?",
                           arguments: [tag?.name, stableId])
        }
    }

    /// 发件人批量改组（STORE-013 / CLS-012）：该发件人在该桶内全部邮件一次归组。
    public func setTag(senderAddress: String, bucket: Bucket, tag: MailTag?) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE classification SET tag = ?
                WHERE stableId IN (
                    SELECT m.stableId FROM mail m JOIN classification c ON c.stableId = m.stableId
                    WHERE c.bucket = ? AND m.fromAddress = ?
                )
                """, arguments: [tag?.name, bucket.rawValue, senderAddress.normalized])
        }
    }

    /// 子串搜索（STORE-003）：≥3 字符走 FTS5 trigram；更短的查询 trigram 无法成组，LIKE 兜底。
    public func search(_ query: String, limit: Int = 50) throws -> [MailRow] {
        try dbQueue.read { db in
            if query.count >= 3 {
                let pattern = "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
                return try MailRow.fetchAll(
                    db,
                    sql: "SELECT * FROM mail WHERE rowid IN (SELECT rowid FROM mail_fts WHERE mail_fts MATCH ?) LIMIT ?",
                    arguments: [pattern, limit])
            }
            let like = "%\(query)%"
            return try MailRow.fetchAll(
                db,
                sql: "SELECT * FROM mail WHERE subject LIKE ? OR fromAddress LIKE ? OR snippet LIKE ? LIMIT ?",
                arguments: [like, like, like, limit])
        }
    }

    /// 邮件当前归类桶（阅读页 bucket 徽标取邮件自身而非当前列表，JOURNEY-003）。
    public func classificationBucket(stableId: String) throws -> Bucket? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT bucket FROM classification WHERE stableId = ?",
                                arguments: [stableId]).flatMap(Bucket.init(rawValue:))
        }
    }

    /// 邮件当前组（阅读窗格归组入口回显，STORE-013）。
    public func classificationTag(stableId: String) throws -> MailTag? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT tag FROM classification WHERE stableId = ? AND tag IS NOT NULL AND tag != ''",
                arguments: [stableId]
            ).map { MailTag($0) }
        }
    }

    public func mail(stableId: String) throws -> MailRow? {
        try dbQueue.read { db in
            try MailRow.fetchOne(db, key: stableId)
        }
    }

    /// 各桶邮件数（侧栏徽章数据源，STORE-006）。
        /// 同步快照持久化（SYNC-015）：folder → (uidValidity, highestUid)。
    public func saveSnapshot(folder: String, uidValidity: Int, highestUid: Int) throws {
        try dbQueue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO sync_state(folder, uidValidity, highestUid) VALUES (?,?,?)",
                           arguments: [folder, uidValidity, highestUid])
        }
    }

    public func loadSnapshot(folder: String) -> (uidValidity: Int, highestUid: Int)? {
        let row = try? dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT uidValidity, highestUid FROM sync_state WHERE folder = ?", arguments: [folder])
        }
        return row.map { ($0["uidValidity"] ?? 0, $0["highestUid"] ?? 0) }
    }

    /// 批量入库（STORE-007：单事务，事务开销摊平）。
    public func upsertBatch(_ rows: [MailRow]) throws {
        try dbQueue.write { db in
            for row in rows { try row.save(db) }
        }
    }

    public func freezeBatch(_ rows: [ClassificationRow]) throws {
        try dbQueue.write { db in
            for row in rows { try row.save(db) }
        }
    }
    public func bucketCounts() throws -> [String: Int] {
        try dbQueue.read { db in
            var out: [String: Int] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT bucket, COUNT(*) AS n FROM classification GROUP BY bucket
                """)
            for row in rows {
                out[row["bucket"] ?? ""] = row["n"] ?? 0
            }
            return out
        }
    }
}
