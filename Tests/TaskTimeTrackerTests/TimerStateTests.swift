import XCTest
@testable import TaskTimeTracker

final class TimerStateTests: XCTestCase {
    @MainActor
    func testStartInCountdownResetsElapsedWhenAlreadyAtEnd() {
        let state = TimerState()
        state.mode = .countdown
        state.elapsedSeconds = state.countdownSeconds

        state.start()
        defer { state.pause() }

        XCTAssertEqual(state.elapsedSeconds, 0)
        XCTAssertTrue(state.isRunning)
    }

    @MainActor
    func testCountdownDisplayAndProgressReflectElapsedTime() {
        let state = TimerState()
        state.mode = .countdown
        state.countdownSeconds = 120
        state.elapsedSeconds = 30

        XCTAssertEqual(state.displaySeconds, 90)
        XCTAssertEqual(state.progress, 0.25, accuracy: 0.0001)
    }
}
