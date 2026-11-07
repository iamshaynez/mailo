import Testing
import Foundation
@testable import MailProtoKit

// MARK: - 用例库：docs/specs/MAIL-usecases.md（MAIL-020）

struct DeviceCodeFlowTests {

    @Test("MAIL-020 设备码流响应解析")
    func mail_020_device_code_flow_parsing() throws {
        // 下发码
        let codeJSON = """
        {"user_code":"AB12CD34","device_code":"FQAB...","verification_uri":"https://microsoft.com/devicelogin","interval":5,"expires_in":900}
        """.data(using: .utf8)!
        let req = try DeviceCodeFlow.parseDeviceCodeResponse(codeJSON)
        #expect(req.userCode == "AB12CD34")
        #expect(req.verificationURI == "https://microsoft.com/devicelogin")
        #expect(req.interval == 5)

        // pending
        let pending = DeviceCodeFlow.parseTokenResponse(
            """
            {"error":"authorization_pending"}
            """.data(using: .utf8)!)
        #expect(pending == .pending)

        // slow_down 同样按 pending
        #expect(DeviceCodeFlow.parseTokenResponse(
            #"{"error":"slow_down"}"#.data(using: .utf8)!) == .pending)

        // granted
        let granted = DeviceCodeFlow.parseTokenResponse(
            #"{"token_type":"Bearer","access_token":"EwAo..."}"#.data(using: .utf8)!)
        #expect(granted == .granted(accessToken: "EwAo..."))

        // denied
        let denied = DeviceCodeFlow.parseTokenResponse(
            #"{"error":"authorization_declined","error_description":"user said no"}"#.data(using: .utf8)!)
        #expect(denied == .denied(error: "authorization_declined", description: "user said no"))

        // 坏 JSON
        #expect(throws: DeviceCodeFlow.ParseError.self) {
            _ = try DeviceCodeFlow.parseDeviceCodeResponse(Data("not json".utf8))
        }
    }

    @Test("MAIL-021 双账户形态端点与 scope")
    func mail_021_dual_account_endpoints_and_scopes() {
        // 个人 MSA：consumers 租户 + outlook.office.com 主机（2026-11-07 实测：
        // office365.com 主机在 consumers 端点报 AADSTS70011）
        #expect(DeviceCodeFlow.deviceCodeURL(account: .personal).absoluteString
                == "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")
        #expect(DeviceCodeFlow.mailScope(account: .personal).contains("https://outlook.office.com/IMAP.AccessAsUser.All"))
        #expect(!DeviceCodeFlow.mailScope(account: .personal).contains("outlook.office365.com"))

        // 组织账户：organizations 租户 + outlook.office365.com 主机
        #expect(DeviceCodeFlow.deviceCodeURL(account: .organizational).absoluteString
                == "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode")
        #expect(DeviceCodeFlow.mailScope(account: .organizational).contains("https://outlook.office365.com/IMAP.AccessAsUser.All"))
    }
}
