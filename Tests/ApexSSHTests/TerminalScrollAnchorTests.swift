import XCTest
import AppKit
@testable import ApexTerminal

/// Tab/pane switches rebuild the terminal NSView (SwiftUI `.id`); the user's scroll
/// position (top / middle / bottom) must survive the rebuild via the ring buffer anchor.
final class TerminalScrollAnchorTests: XCTestCase {
    private let lineCount = 200

    @MainActor
    private func makeMountedTerminal() -> (NativeTerminalScrollView, NativeTerminalView, TerminalRingBuffer) {
        let scroll = NativeTerminalScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let buffer = TerminalRingBuffer()
        scroll.terminalView.ringBuffer = buffer
        buffer.appendStream((0..<lineCount).map { "line-\($0)" }.joined(separator: "\r\n") + "\r\n")
        scroll.layoutSubtreeIfNeeded()
        scroll.terminalView.refresh()
        scroll.layoutSubtreeIfNeeded()
        return (scroll, scroll.terminalView, buffer)
    }

    /// Mimics TerminalRepresentable.makeNSView on a rebuild: same buffer, new views.
    @MainActor
    private func rebuild(likeMakeNSView buffer: TerminalRingBuffer) -> (NativeTerminalScrollView, NativeTerminalView) {
        let scroll = NativeTerminalScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let terminal = scroll.terminalView
        terminal.ringBuffer = buffer
        // Mirror makeNSView: pin state restored before rehydration.
        terminal.isPinnedToBottom = buffer.scrollAnchor.isPinnedToBottom
        terminal.refresh()
        scroll.layoutSubtreeIfNeeded()
        terminal.restoreScrollAnchorOnRebuild()
        return (scroll, terminal)
    }

    @MainActor
    private func settle(_ file: StaticString = #filePath, _ line: UInt = #line) {
        // Let the deferred restore (async + layout) run.
        for _ in 0..<20 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor
    func testRebuildRestoresBottomPosition() {
        let (_, terminal, buffer) = makeMountedTerminal()
        terminal.scrollToBottom(forceLayout: true)
        settle()
        let clip = terminal.enclosingScrollView!.contentView
        let maxY = terminal.frame.height - clip.bounds.height
        XCTAssertGreaterThan(maxY, 50, "content must overflow the viewport")
        XCTAssertEqual(clip.bounds.origin.y, maxY, accuracy: 1.0)
        XCTAssertTrue(buffer.scrollAnchor.isPinnedToBottom)

        let (scroll2, terminal2) = rebuild(likeMakeNSView: buffer)
        settle()
        let clip2 = scroll2.contentView
        XCTAssertTrue(terminal2.isPinnedToBottom, "bottom anchor must stay pinned")
        let maxY2 = terminal2.frame.height - clip2.bounds.height
        XCTAssertEqual(clip2.bounds.origin.y, maxY2, accuracy: 1.0)
    }

    @MainActor
    func testRebuildRestoresMiddlePosition() {
        let (scroll, terminal, buffer) = makeMountedTerminal()
        terminal.scrollToBottom(forceLayout: true)
        settle()
        let clip = scroll.contentView
        let middle = (terminal.frame.height - clip.bounds.height) / 2
        clip.scroll(to: NSPoint(x: 0, y: middle))
        settle()
        XCTAssertFalse(buffer.scrollAnchor.isPinnedToBottom)
        XCTAssertEqual(buffer.scrollAnchor.offset, middle, accuracy: 1.0)

        let (scroll2, terminal2) = rebuild(likeMakeNSView: buffer)
        settle()
        XCTAssertFalse(terminal2.isPinnedToBottom, "middle anchor must stay unpinned")
        XCTAssertEqual(scroll2.contentView.bounds.origin.y, middle, accuracy: 1.0)
    }

    @MainActor
    func testRebuildRestoresTopPosition() {
        let (scroll, terminal, buffer) = makeMountedTerminal()
        terminal.scrollToBottom(forceLayout: true)
        settle()
        scroll.contentView.scroll(to: .zero)
        settle()
        XCTAssertEqual(buffer.scrollAnchor.offset, 0, accuracy: 0.5)
        XCTAssertFalse(buffer.scrollAnchor.isPinnedToBottom)

        let (scroll2, terminal2) = rebuild(likeMakeNSView: buffer)
        settle()
        XCTAssertEqual(scroll2.contentView.bounds.origin.y, 0, accuracy: 0.5)
        XCTAssertFalse(terminal2.isPinnedToBottom, "top anchor must stay unpinned")
    }

    @MainActor
    func testNewBufferDefaultsToPinnedBottom() {
        let buffer = TerminalRingBuffer()
        XCTAssertTrue(buffer.scrollAnchor.isPinnedToBottom)
        XCTAssertEqual(buffer.scrollAnchor.offset, 0)
    }
}
