import CoreKit
import Foundation
import MirrorKit
import Testing

@testable import DesignKit

@MainActor
struct SecondPolishTests {
    @Test("DESIGN-006 阅读区为平坦纸面且使用统一水平留白")
    func design_006_reader_surface_palette() {
        #expect(!ReaderSurfaceSpec.usesGradient)
        #expect(ReaderSurfaceSpec.leadingPadding == 20)
        #expect(ReaderSurfaceSpec.trailingPadding == 44)
        #expect(ReaderSurfaceSpec.trailingGutter == 0)
        #expect(ReaderSurfaceSpec.bottomGutter == 0)
        #expect(ReaderSurfaceSpec.headerMeasure == 600)
        #expect(DesignTokens.hex(.readerHeader, for: .dark) == 0x1B2A35)
        #expect(DesignTokens.hex(.readerBodyBottom, for: .dark) == 0x16242E)
        #expect(DesignTokens.hex(.readerChip, for: .dark) == 0x2B3E4B)
    }

    @Test("PERF-005 相同 HTML 零重载，内容变化只加载一次")
    func perf_005_webview_reload_guard() {
        var guardState = MailWebViewLoadGuard()
        #expect(guardState.shouldLoad("document-a"))
        #expect(!guardState.shouldLoad("document-a"))
        #expect(!guardState.shouldLoad("document-a"))
        #expect(guardState.shouldLoad("document-b"))
        #expect(!guardState.shouldLoad("document-b"))
        #expect(guardState.shouldLoad("document-a"))
    }

    @Test("PERF-004/005 flags-only 更新复用全部日期且零新解析")
    func perf_005_flags_only_reuses_date_index() {
        let entries = (0..<200).map { i in
            BucketEntry(stableId: "row-\(i)",
                        date: String(format: "2026-11-08T%02d:%02d:00Z", i / 60, i % 60), bucket: "imbox")
        }
        let initial = MailDateIndex(entries: entries)
        #expect(MailDateIndex.parseCount == 200)
        let flagged = entries.map { entry in
            var copy = entry
            copy.flags = "\\Seen"
            return copy
        }
        let reused = MailDateIndex(entries: flagged, reusing: initial)
        #expect(MailDateIndex.parseCount == 0)
        #expect(reused.dayLabel(for: "row-0") == initial.dayLabel(for: "row-0"))
        #expect(reused.timeLabel(for: "row-100") == initial.timeLabel(for: "row-100"))
    }

    @Test("PERF-005/JOURNEY-014 快速选择只允许最新任务提交")
    func perf_005_latest_selection_wins() {
        var gate = ReaderLoadGate()
        let first = gate.begin("a")
        let second = gate.begin("b")
        #expect(!gate.canCommit(first, for: "a"))
        #expect(gate.canCommit(second, for: "b"))
        #expect(!gate.canCommit(second, for: "c"))
    }

    @Test("PERF-005/JOURNEY-014 缓存正文 MIME 解析不占用主线程")
    func perf_005_detail_parse_off_main() async throws {
        let model = await MailoAppModel.bootstrapDemo()
        let id = try #require(model.entries.first?.stableId)
        MailoAppModel.detailParseIsMainThread = nil
        _ = await model.loadDetail(stableId: id)
        #expect(MailoAppModel.detailParseIsMainThread == false)
    }
}
