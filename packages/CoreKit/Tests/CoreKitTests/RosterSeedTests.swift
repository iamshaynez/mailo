import Testing
import Foundation
@testable import CoreKit

// MARK: - 用例库：docs/specs/CLS-usecases.md（CLS-009）

struct RosterSeedTests {

    @Test("CLS-009 预置名单库种子与热更覆盖")
    func cls_009_roster_seed_and_overrides() throws {
        let roster = RosterSeed.roster()

        // 种子命中正确桶
        func domainBucket(_ from: String) -> Bucket? {
            let parts = from.split(separator: "@")
            let signal = MailSignal(
                messageID: StableMessageID(messageId: "<x@y>", accountFingerprint: "t"),
                senderLocalPart: String(parts[0]), senderDomain: String(parts[1]), subject: "s")
            guard case .classified(let bucket, .roster) = ClassificationPipeline(roster: roster).decide(signal) else {
                return nil
            }
            return bucket
        }
        #expect(domainBucket("noreply@netflix.com") == .feed)
        #expect(domainBucket("no-reply@GITHUB.com") == .feed)   // 大小写规范化
        #expect(domainBucket("receipt@stripe.com") == .paperTrail)
        #expect(domainBucket("shipment@fedex.com") == .paperTrail)

        // 歧义高价值域不在种子（银行交 Screener）
        #expect(RosterSeed.builtIn["chase.com"] == nil)
        #expect(RosterSeed.builtIn["icbc.com.cn"] == nil)

        // 覆盖表优先于种子 + JSON 热更解析
        let overrides = RosterSeed.parseOverrides(try #require("""
        {"netflix.com": "paperTrail", "newservice.io": "feed", "bad.example": "notABucket"}
        """.data(using: .utf8)))
        let merged = RosterSeed.roster(overrides: overrides)
        #expect(merged.domainBuckets["netflix.com"] == .paperTrail) // 覆盖赢
        #expect(merged.domainBuckets["newservice.io"] == .feed)     // 新增生效
        #expect(merged.domainBuckets["bad.example"] == nil)         // 坏桶忽略
        #expect(merged.domainBuckets["github.com"] == .feed)        // 未覆盖的种子保留
    }
}
