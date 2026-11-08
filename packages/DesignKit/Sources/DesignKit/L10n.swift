import Foundation

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（DESIGN-003 多语言）

/// 本地化取词（DESIGN-003）：开发语言 en，zh-Hans 第一翻译；其他语言回落 en。
/// 键位集中在 Resources/{en,zh-Hans}.lproj/Localizable.strings。
public enum L10n {
    /// 取词（跟随系统语言）。
    public static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    /// 带格式化参数取词。
    public static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, bundle: .module, comment: ""), locale: Locale.current, arguments: args)
    }

    /// 测试/预览：指定语言取词（读对应 lproj 子包）。
    /// lproj 目录名在不同工具链下可能被规范为小写（CI 实测 zh-Hans → zh-hans），两级尝试。
    public static func t(_ key: String, languageCode: String) -> String {
        for code in [languageCode, languageCode.lowercased()] {
            if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return NSLocalizedString(key, bundle: bundle, comment: "")
            }
        }
        return NSLocalizedString(key, bundle: .module, comment: "") // 回落开发语言
    }

    /// 可用翻译语言（en 恒在）。
    public static var availableLanguages: [String] {
        Bundle.module.localizations.sorted()
    }
}
