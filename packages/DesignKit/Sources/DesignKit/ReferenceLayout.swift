import CoreGraphics
import CoreKit
import Foundation

struct ReferenceColumns {
    let sidebar: CGFloat
    let list: CGFloat
    let reader: CGFloat
}

/// DESIGN-007：阅读正文视口与居中阅读列的纯几何计算。
enum ReferenceLayout {
    /// DESIGN-007：按 139:345:414 的参考栏宽等比换算，阅读区取剩余像素。
    static func columns(totalWidth: CGFloat) -> ReferenceColumns {
        let sidebar = (totalWidth * 139 / 898).rounded()
        let list = (totalWidth * 345 / 898).rounded()
        return ReferenceColumns(sidebar: sidebar, list: list, reader: totalWidth - sidebar - list)
    }
    /// DESIGN-007/JOURNEY-014：扣除头部与回复区，并保留最小正文高度。
    static func bodyHeight(viewportHeight: CGFloat, headerHeight: CGFloat, replyHeight: CGFloat) -> CGFloat {
        max(160, viewportHeight - headerHeight - replyHeight)
    }

    /// DESIGN-007：阅读区左 20、右 44，阅读宽度不超过 token 上限。
    static func contentWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, min(DesignTokens.readingMeasure, containerWidth - 64))
    }
}

/// DESIGN-007：将发件人原始值拆为清理后的显示名与地址；空值返回两个空字符串。
struct SenderPresentation {
    let name: String
    let address: String

    init(_ raw: String?) {
        let value = Self.clean(raw ?? "")
        if let opening = value.lastIndex(of: "<"), value.last == ">" {
            let closing = value.index(before: value.endIndex)
            let parsedName = Self.clean(String(value[..<opening]))
            let parsedAddress = Self.clean(String(value[value.index(after: opening)..<closing]))
            name = parsedName.isEmpty ? parsedAddress : parsedName
            address = parsedAddress
        } else {
            name = value
            address = value
        }
    }

    private static func clean(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.count >= 2, let first = result.first, let last = result.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

/// DESIGN-006：保留 MIME 附件的真实内容与类型，并选择对应的展示符号。
struct MailAttachmentPreview {
    let filename: String
    let contentType: String
    let data: [UInt8]
    let isImage: Bool
    let symbolName: String

    init(part: MimePart) {
        let mediaType = part.contentType.components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let image = mediaType.hasPrefix("image/")

        filename = part.filename ?? "Attachment"
        contentType = part.contentType
        data = part.body
        isImage = image
        if image {
            symbolName = "photo"
        } else if mediaType == "application/pdf" {
            symbolName = "doc.text.fill"
        } else {
            symbolName = "doc.fill"
        }
    }
}
