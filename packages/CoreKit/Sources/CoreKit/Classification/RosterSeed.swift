import Foundation

/// 预置名单库种子（CLS-009，基线 §5 ②）。
/// 收录原则：**高置信、无歧义**——只收纯通知/订阅/收据域；银行、政务、医疗等
/// 高价值歧义域名不收（宁缺勿滥，交 Screener 由用户裁决）。
/// 随 app 版本更新；CDN 热更覆盖表优先于内置种子。
public enum RosterSeed {
    /// 内置 v1 种子（域名 → 桶，键统一小写）。
    public static let builtIn: [String: Bucket] = {
        var seed: [String: Bucket] = [:]
        // Feed：订阅与内容通知
        for domain in [
            "netflix.com", "spotify.com", "youtube.com", "disneyplus.com",
            "substack.com", "medium.com", "buzzfeed.com",
            "linkedin.com", "x.com", "twitter.com", "instagram.com", "facebook.com",
            "discord.com", "reddit.com", "github.com", "gitlab.com",
            "stackoverflow.com", "producthunt.com", "goodreads.com",
            "coursera.org", "duolingo.com", "strava.com",
        ] {
            seed[domain] = .feed
        }
        // Paper Trail：收据、账单、物流
        for domain in [
            "amazon.com", "stripe.com", "paypal.com",
            "apple.com", "uber.com", "lyft.com", "ubereats.com", "doordash.com",
            "airbnb.com", "booking.com", "delta.com", "united.com", "southwest.com",
            "usps.com", "ups.com", "fedex.com", "dhl.com",
            "shopify.com", "etsy.com", "ebay.com",
        ] {
            seed[domain] = .paperTrail
        }
        return seed
    }()

    /// 组装 Roster：内置种子 + 覆盖表（CDN 热更或用户自定义，覆盖优先）。
    public static func roster(overrides: [String: Bucket] = [:]) -> Roster {
        var merged = builtIn
        for (domain, bucket) in overrides where !domain.isEmpty {
            merged[domain.normalized] = bucket
        }
        return Roster(domainBuckets: merged)
    }

    /// 从 JSON（CDN 热更格式 `{"domain":"bucket"}`）加载覆盖表；坏行跳过、未知桶忽略。
    public static func parseOverrides(_ json: Data) -> [String: Bucket] {
        guard let raw = try? JSONSerialization.jsonObject(with: json) as? [String: String] else {
            return [:]
        }
        var out: [String: Bucket] = [:]
        for (domain, bucketRaw) in raw {
            if let bucket = Bucket(rawValue: bucketRaw.trimmingCharacters(in: .whitespaces).lowercased()) {
                out[domain.normalized] = bucket
            }
        }
        return out
    }
}
