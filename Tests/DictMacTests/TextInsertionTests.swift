import AppKit
import XCTest

@testable import DictLocalAI

@MainActor
final class TextInsertionTests: XCTestCase {
  func testSyntheticPasteIncludesPhysicalCommandModifierEvents() throws {
    let events = try XCTUnwrap(TextInsertion.pasteKeyEvents())
    XCTAssertEqual(events.count, 4)
    XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [55, 9, 9, 55])
    XCTAssertEqual(events[0].flags, .maskCommand)
    XCTAssertEqual(events[1].flags, .maskCommand)
    XCTAssertEqual(events[2].flags, .maskCommand)
    XCTAssertFalse(events[3].flags.contains(.maskCommand))
  }

  func testMissingCapturedTargetNeverChangesClipboard() {
    let previousChange = NSPasteboard.general.changeCount
    XCTAssertEqual(TextInsertion.insert("test recognized text", target: nil), .unavailable)
    XCTAssertEqual(NSPasteboard.general.changeCount, previousChange)
  }
}

private final class SlowProvider: NSObject, NSPasteboardItemDataProvider {
  let delay: TimeInterval
  init(delay: TimeInterval) { self.delay = delay }

  func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    Thread.sleep(forTimeInterval: delay)
    item.setData(Data([1]), forType: type)
  }
}

private final class CountingProvider: NSObject, NSPasteboardItemDataProvider {
  private(set) var reads = 0

  func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    reads += 1
    item.setData(Data([1]), forType: type)
  }
}

@MainActor
final class ClipboardPreservationTests: XCTestCase {
  private var boards: [NSPasteboard] = []

  override func tearDown() {
    for board in boards { board.releaseGlobally() }
    boards = []
    super.tearDown()
  }

  private func makeBoard() -> NSPasteboard {
    let board = NSPasteboard(name: .init("test-\(UUID())"))
    boards.append(board)
    return board
  }

  private func dictate(_ text: String, on board: NSPasteboard, restorer: ClipboardPreserver) {
    let capture = restorer.prepare()
    board.clearContents()
    board.setString(text, forType: .string)
    restorer.restoreAfterPaste(capture, pasteChangeCount: board.changeCount)
  }

  private func waitForRestore() async throws {
    try await Task.sleep(for: .milliseconds(200))
  }

  // Measure the cost of materializing lazy clipboard data on the main thread.
  func testSnapshotMaterializesEveryLazyType() throws {
    let board = makeBoard()
    let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .pdf, .rtf]
    let item = NSPasteboardItem()
    let provider = SlowProvider(delay: 0.1)
    XCTAssertTrue(item.setDataProvider(provider, forTypes: types))
    board.clearContents()
    board.writeObjects([item])

    let started = ContinuousClock.now
    let capture = ClipboardContentsReader.capture(board)
    let elapsed = ContinuousClock.now - started

    guard case .snapshot(let snapshot) = capture else { return XCTFail("expected a snapshot") }
    XCTAssertEqual(snapshot.items.first?.count, types.count)
    print("clipboard capture with \(types.count) lazy types of 100 ms: \(elapsed)")
    XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(400))
  }

  func testSnapshotRoundTripsEveryClipboardItemAndType() async throws {
    let board = makeBoard()
    let first = NSPasteboardItem()
    first.setString("hello", forType: .string)
    first.setData(Data([1, 2, 3]), forType: .png)
    let second = NSPasteboardItem()
    second.setString("file:///tmp/a.txt", forType: .fileURL)
    board.clearContents()
    board.writeObjects([first, second])
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(50))

    dictate("dictated", on: board, restorer: restorer)
    XCTAssertEqual(board.string(forType: .string), "dictated")
    try await waitForRestore()

    XCTAssertEqual(board.pasteboardItems?.count, 2)
    XCTAssertEqual(board.pasteboardItems?[0].string(forType: .string), "hello")
    XCTAssertEqual(board.pasteboardItems?[0].data(forType: .png), Data([1, 2, 3]))
    XCTAssertEqual(board.pasteboardItems?[1].string(forType: .fileURL), "file:///tmp/a.txt")
  }

  func testBlankClipboardRemainsBlankAfterRestore() async throws {
    let board = makeBoard()
    board.clearContents()
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(50))

    dictate("dictated", on: board, restorer: restorer)
    try await waitForRestore()

    XCTAssertTrue(board.pasteboardItems?.isEmpty ?? true)
  }

  func testRestorePreservesClipboardChangesMadeByUser() async throws {
    let board = makeBoard()
    board.clearContents()
    board.setString("old", forType: .string)
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(100))

    dictate("dictated", on: board, restorer: restorer)
    board.clearContents()
    board.setString("user copied", forType: .string)
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(board.string(forType: .string), "user copied")
  }

  func testOverlappingDictationsPreservePreexistingClipboard() async throws {
    let board = makeBoard()
    board.clearContents()
    board.setString("original", forType: .string)
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(100))

    dictate("first", on: board, restorer: restorer)
    dictate("second", on: board, restorer: restorer)
    XCTAssertEqual(board.string(forType: .string), "second")
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(board.string(forType: .string), "original")
  }

  func testRestoreOmitsConcealedClipboardItems() async throws {
    let board = makeBoard()
    let secret = NSPasteboardItem()
    secret.setString("secret", forType: .string)
    secret.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    board.clearContents()
    board.writeObjects([secret])
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(50))

    dictate("dictated", on: board, restorer: restorer)
    try await waitForRestore()

    XCTAssertEqual(board.string(forType: .string), "dictated")
  }

  func testDisabledRestoreNeverReadsTheClipboardAndPreservesDictationText() async throws {
    let board = makeBoard()
    let item = NSPasteboardItem()
    let provider = CountingProvider()
    XCTAssertTrue(item.setDataProvider(provider, forTypes: [.png]))
    board.clearContents()
    board.writeObjects([item])
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(50))

    let capture = restorer.prepare(enabled: false)
    guard case .skipped(let reason) = capture else { return XCTFail("expected no snapshot") }
    XCTAssertEqual(reason, "disabled")
    board.clearContents()
    board.setString("dictated", forType: .string)
    restorer.restoreAfterPaste(capture, pasteChangeCount: board.changeCount)
    try await waitForRestore()

    XCTAssertEqual(provider.reads, 0)
    XCTAssertEqual(board.string(forType: .string), "dictated")
  }

  func testWithoutScheduleDictationTextRemainsOnClipboard() async throws {
    let board = makeBoard()
    board.clearContents()
    board.setString("old", forType: .string)
    let restorer = ClipboardPreserver(board: board, delay: .milliseconds(50))

    _ = restorer.prepare()
    board.clearContents()
    board.setString("dictated", forType: .string)
    try await waitForRestore()

    XCTAssertEqual(board.string(forType: .string), "dictated")
  }
}

final class ConsecutiveSkippedWindowsTests: XCTestCase {
  func testExclusivelyTheFirstWindowOfASeriesIsReportedAndTheEndGivesTheTotal() {
    var run = ConsecutiveSkippedWindows()
    XCTAssertNil(run.end())
    XCTAssertTrue(run.skip())
    XCTAssertFalse(run.skip())
    XCTAssertFalse(run.skip())
    XCTAssertEqual(run.end(), 3)
    XCTAssertNil(run.end())
    XCTAssertTrue(run.skip())
  }
}
