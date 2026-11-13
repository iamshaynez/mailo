import CoreKit
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif

@testable import DesignKit

// MARK: - 用例库：docs/specs/JOURNEY-usecases.md（DESIGN-008 参考宽度侧栏可读性）

@MainActor
struct SidebarLayoutTests {
    #if os(macOS)
    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    #endif

    @Test("DESIGN-008 139pt 侧栏完整容纳标准标题、多位计数与展开箭头")
    func design_008_sidebar_reference_rows_fit() {
        #if os(macOS)
        let navFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let microFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let rows = [
            (title: "Screener", count: "626", hasTrailingIcon: false),
            (title: "Imbox", count: "0", hasTrailingIcon: true),
            (title: "Feed", count: "14", hasTrailingIcon: true),
            (title: "Paper Trail", count: "29", hasTrailingIcon: true),
            (title: "Set Aside", count: "1", hasTrailingIcon: false),
        ]

        for row in rows {
            let countWidth = row.count == "0" ? 0 : textWidth(row.count, font: microFont)
            let required = SidebarRowLayout.requiredWidth(
                titleWidth: textWidth(row.title, font: navFont),
                countWidth: countWidth,
                hasIcon: true,
                hasTrailingIcon: row.hasTrailingIcon,
                indent: false
            )
            #expect(required <= 139, "\(row.title) 需要 \(required)pt，超过参考侧栏 139pt")
        }

        let untagged = SidebarRowLayout.requiredWidth(
            titleWidth: textWidth("Untagged", font: microFont),
            countWidth: textWidth("14", font: microFont),
            hasIcon: false,
            hasTrailingIcon: false,
            indent: true
        )
        #expect(untagged <= 139, "Untagged 组行需要 \(untagged)pt，超过参考侧栏 139pt")
        #expect(SidebarRowLayout.regularHeight == 34)
        #expect(SidebarRowLayout.compactHeight == 28)
        #endif
    }

    @Test("DESIGN-008 多位计数与展开组行在 139pt 离屏渲染不换行")
    func design_008_sidebar_accessories_never_wrap() throws {
        #if os(macOS)
        let content = VStack(alignment: .leading, spacing: 0) {
            SidebarRow(title: "Screener", icon: "person.crop.circle.badge.questionmark.fill", count: 626)
            SidebarRow(title: "Feed", icon: "newspaper.fill", count: 14, trailingIcon: "chevron.down")
            SidebarRow(title: "Untagged", icon: nil, count: 14, indent: true, compact: true)
            SidebarRow(title: "Paper Trail", icon: "doc.text.fill", count: 29, trailingIcon: "chevron.down")
        }
        .frame(width: 139)
        .background(DesignTokens.surfaceSidebar)

        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 139, height: 164)
        host.layoutSubtreeIfNeeded()
        let image = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        #expect(image.size == NSSize(width: 139, height: 164))
        if ProcessInfo.processInfo.environment["MAILO_CAPTURE"] != nil {
            try image.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: "/tmp/mailo-sidebar-139.png"))
        }
        #endif
    }
}
