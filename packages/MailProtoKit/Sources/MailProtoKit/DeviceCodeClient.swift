import Foundation

/// 设备码授权客户端（MAIL-020 解析 + JOURNEY-002 装配）。
/// 从探针工具库化：App 与探针共用同一授权路径。
public final class DeviceCodeClient: @unchecked Sendable {
    public enum ClientError: Error, Equatable {
        case deviceCodeFailed(String) // 附服务器原始响应
        case denied(String, String)
        case timedOut
    }

    public struct Prompt: Equatable, Sendable {
        public var userCode: String
        public var verificationURI: String
        public var expiresInSeconds: Int
    }

    private let session: URLSession

    public init() {
        self.session = .shared
    }

    /// 发起设备码并开始轮询。`onPrompt` 在主线程回调（UI 显示 user_code）。
    /// 返回 access token（只存在调用方内存；持久化是调用方经 CredentialVault 的职责）。
    @discardableResult
    public func authorize(
        clientId: String,
        account: DeviceCodeFlow.MicrosoftAccount,
        onPrompt: @escaping @Sendable (Prompt) -> Void
    ) async throws -> String {
        let codeData = try await post(DeviceCodeFlow.deviceCodeURL(account: account), form: [
            "client_id": clientId,
            "scope": DeviceCodeFlow.mailScope(account: account),
        ])
        guard let req = try? DeviceCodeFlow.parseDeviceCodeResponse(codeData) else {
            throw ClientError.deviceCodeFailed(String(data: codeData, encoding: .utf8) ?? "<binary>")
        }
        let prompt = Prompt(userCode: req.userCode, verificationURI: req.verificationURI,
                            expiresInSeconds: req.expiresIn)
        await MainActor.run { onPrompt(prompt) }

        let deadline = Date().addingTimeInterval(TimeInterval(req.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(max(1, req.interval)) * 1_000_000_000)
            let tokenData = try await post(DeviceCodeFlow.tokenURL(account: account), form: [
                "client_id": clientId,
                "device_code": req.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch DeviceCodeFlow.parseTokenResponse(tokenData) {
            case .granted(let token):
                return token
            case .pending:
                continue
            case .denied(let error, let description):
                throw ClientError.denied(error, description)
            }
        }
        throw ClientError.timedOut
    }

    /// 用 refresh token 换新 access token（offline_access 授权后免重登）。
    /// 返回 (accessToken, 新 refreshToken)。
    public func refresh(
        clientId: String,
        account: DeviceCodeFlow.MicrosoftAccount,
        refreshToken: String
    ) async throws -> (accessToken: String, refreshToken: String) {
        let data = try await post(DeviceCodeFlow.tokenURL(account: account), form: [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
        switch DeviceCodeFlow.parseTokenResponse(data) {
        case .granted(let access, let refresh):
            return (access, refresh ?? refreshToken) // 某些实现不轮换 refresh token
        case .denied(let error, let description):
            throw ClientError.denied(error, description)
        case .pending:
            throw ClientError.deviceCodeFailed("unexpected pending on refresh")
        }
    }

    private func post(_ url: URL, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $1)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        return data
    }
}
