import Foundation

/// OAuth2 设备码流（RFC 8628）的响应解析（MAIL-020）。
/// 用途：Outlook 本地联调的免 UI 授权——命令行发起，浏览器输 user_code，轮询拿 token。
/// 生产 app 内授权走 AppAuth（等正式 client id），本类型同时服务于探针工具与回退路径。
public enum DeviceCodeFlow {
    public struct CodeRequest: Equatable, Sendable {
        public var deviceCode: String
        public var userCode: String
        public var verificationURI: String
        public var interval: Int
        public var expiresIn: Int

        public init(deviceCode: String, userCode: String, verificationURI: String,
                    interval: Int = 5, expiresIn: Int = 900) {
            self.deviceCode = deviceCode
            self.userCode = userCode
            self.verificationURI = verificationURI
            self.interval = interval
            self.expiresIn = expiresIn
        }
    }

    public enum TokenPollResult: Equatable, Sendable {
        case pending
        case granted(accessToken: String)
        case denied(error: String, description: String)
    }

    /// 设备码下发响应（`POST /devicecode` 的 JSON）。
    public static func parseDeviceCodeResponse(_ data: Data) throws -> CodeRequest {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.badJSON
        }
        guard let deviceCode = obj["device_code"] as? String,
              let userCode = obj["user_code"] as? String,
              let uri = obj["verification_uri"] as? String else {
            throw ParseError.missingField
        }
        return CodeRequest(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: uri,
            interval: obj["interval"] as? Int ?? 5,
            expiresIn: obj["expires_in"] as? Int ?? 900)
    }

    /// 令牌轮询响应（`POST /token` 的 JSON）：成功 / pending / 拒绝三分支。
    public static func parseTokenResponse(_ data: Data) -> TokenPollResult {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .denied(error: "bad_json", description: "unparseable token response")
        }
        if let token = obj["access_token"] as? String, !token.isEmpty {
            return .granted(accessToken: token)
        }
        if let error = obj["error"] as? String {
            if error == "authorization_pending" || error == "slow_down" {
                return .pending
            }
            let desc = obj["error_description"] as? String ?? ""
            return .denied(error: error, description: desc)
        }
        return .denied(error: "unknown", description: "no access_token and no error field")
    }

    public enum ParseError: Error, Equatable {
        case badJSON
        case missingField
    }

    /// Microsoft 个人账户（MSA）的设备码与令牌端点（consumers 租户，launch/03 Phase 1 受众）。
    public static let microsoftDeviceCodeURL = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
    public static let microsoftTokenURL = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
    /// IMAP XOAUTH2 + SMTP 发信 + 离线刷新（AuthKit 同源常量，探针独立持有避免跨包依赖方向反转）。
    public static let microsoftMailScope = "https://outlook.office365.com/IMAP.AccessAsUser.All https://outlook.office365.com/SMTP.Send offline_access"
}
