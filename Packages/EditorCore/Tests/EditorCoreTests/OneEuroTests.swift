// What: Tests One Euro filter convergence, step response, and NaN safety.
// Inputs/Outputs: Value/timestamp streams in; smoothed values asserted out.
// Threading: XCTest, single thread.
import XCTest
@testable import EditorCore

final class OneEuroTests: XCTestCase {

    func testFirstValuePassesThrough() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.0, derivativeCutoff: 1.0)
        XCTAssertEqual(filter.filter(value: 5, timestamp: 0), 5, accuracy: 0.0001)
    }

    func testConvergesToConstant() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.0, derivativeCutoff: 1.0)
        var last: Float = 0
        for i in 0..<200 {
            last = filter.filter(value: 1, timestamp: Float(i) / 60)
        }
        XCTAssertEqual(last, 1, accuracy: 0.01)
    }

    func testNoNaNOnNoisyInput() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.1, derivativeCutoff: 1.0)
        var timestamp: Float = 0
        for i in 0..<500 {
            timestamp += 1.0 / 60
            let value: Float = (i % 2 == 0) ? 10 : -10
            let out = filter.filter(value: value, timestamp: timestamp)
            XCTAssertFalse(out.isNaN, "NaN at step \(i)")
            XCTAssertFalse(out.isInfinite, "Infinite at step \(i)")
        }
    }

    func testSameTimestampDoesNotJump() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.0, derivativeCutoff: 1.0)
        let first = filter.filter(value: 1, timestamp: 1)
        let second = filter.filter(value: 100, timestamp: 1)
        XCTAssertEqual(second, first, accuracy: 0.0001)
    }

    func testResetRestarts() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.0, derivativeCutoff: 1.0)
        _ = filter.filter(value: 1, timestamp: 0)
        _ = filter.filter(value: 2, timestamp: 1.0 / 60)
        filter.reset()
        XCTAssertEqual(filter.filter(value: 9, timestamp: 2), 9, accuracy: 0.0001)
    }

    func testSmoothingReducesNoise() {
        var filter = OneEuroFilter(rate: 60, minCutoff: 1.0, beta: 0.0, derivativeCutoff: 1.0)
        var maxDeviation: Float = 0
        for i in 0..<120 {
            let value: Float = 1 + ((i % 2 == 0) ? 0.5 : -0.5)
            let out = filter.filter(value: value, timestamp: Float(i) / 60)
            // The first sample passes through unfiltered by design, so
            // measure the steady state only.
            if i > 0 {
                maxDeviation = max(maxDeviation, abs(out - 1))
            }
        }
        XCTAssertLessThan(maxDeviation, 0.5)
    }
}
