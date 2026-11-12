// What: Tests undo/redo, empty stacks, and the 200-entry cap.
// Inputs/Outputs: Recorded states in; undone/redone states or nil out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class HistoryTests: XCTestCase {

    func testUndoRedoRoundTrip() {
        var history = History<Int>()
        history.record(1)
        history.record(2)
        XCTAssertEqual(history.undo(current: 3), 2)
        XCTAssertEqual(history.redo(current: 2), 3)
    }

    func testUndoOnEmptyReturnsNil() {
        var history = History<Int>()
        XCTAssertNil(history.undo(current: 1))
    }

    func testRedoOnEmptyReturnsNil() {
        var history = History<Int>()
        XCTAssertNil(history.redo(current: 1))
    }

    func testRecordClearsRedoStack() {
        var history = History<Int>()
        history.record(1)
        history.record(2)
        XCTAssertEqual(history.undo(current: 3), 2)
        history.record(99)
        XCTAssertNil(history.redo(current: 99))
    }

    func testUndoThenRedoRestoresState() {
        var history = History<String>()
        history.record("a")
        history.record("b")
        let undone = history.undo(current: "c")
        XCTAssertEqual(undone, "b")
        if let undone {
            XCTAssertEqual(history.redo(current: undone), "c")
        } else {
            XCTFail("undo should have returned a state")
        }
    }

    func testCapIsTwoHundred() {
        var history = History<Int>()
        for i in 0..<250 {
            history.record(i)
        }
        var undoneCount = 0
        var current = 250
        while let previous = history.undo(current: current) {
            undoneCount += 1
            current = previous
        }
        XCTAssertEqual(undoneCount, 200)
        XCTAssertNil(history.undo(current: current))
    }

    func testHistoryWithRetouchState() {
        var history = History<RetouchState>()
        let first = RetouchState()
        var second = RetouchState()
        second.skin.smoothing = 50
        history.record(first)
        XCTAssertEqual(history.undo(current: second), first)
    }
}
