import CoreKit
import Foundation
import GRDB

/// 邮件镜像行（stableID 为全局主键，UID 仅是可刷新的缓存属性，STORE-005）。
public struct MailRow: Codable, Equatable, FetchableRecord, PersistableRecord {
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
public struct ClassificationRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "classification"

    public var stableId: String
    public var bucket: String
    public var reason: String

    public init(stableId: String, bucket: Bucket, reason: String) {
        self.stableId = stableId
        self.bucket = bucket.rawValue
        self.reason = reason
    }
}

/// bucket 视图行：邮件 + 归类（UI 列表消费的形态）。
public struct BucketEntry: Codable, Equatable, FetchableRecord {
    public var stableId: String
    public var subject: String?
    public var fromAddress: String?
    public var snippet: String?
    public var date: String?
    public var bucket: String
    public var flags: String
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

    static func migrate(_ db: DatabaseQueue) throws {
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
            try db.create(virtualTable: "mail_fts", using: .fts5(
                ["subject", "fromAddress", "snippet"],
                tokenize: .trigram
            )) { t in
                t.synchronize(withTable: "mail")
            }
        }
        try migrator.migrate(db)
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

    /// FTS5 trigram 子串搜索（STORE-003）。
    public func search(_ query: String, limit: Int = 50) throws -> [MailRow] {
        try dbQueue.read { db in
            let pattern = "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
            return try MailRow.fetchAll(
                db,
                sql: "SELECT * FROM mail WHERE stableId IN (SELECT rowid FROM mail_fts WHERE mail_fts MATCH ?) LIMIT ?",
                arguments: [pattern, limit])
        }
    }

    public func mail(stableId: String) throws -> MailRow? {
        try dbQueue.read { db in
            try MailRow.fetchOne(db, key: stableId)
        }
    }
}
