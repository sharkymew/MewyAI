import XCTest
@testable import MewyAI

final class InputBarLayoutStateTests: XCTestCase {
    func testUsesFallbackHeightBeforeMeasurement() {
        let state = InputBarLayoutState()

        XCTAssertEqual(state.effectiveHeight(fallback: 118), 118)
        XCTAssertEqual(state.bottomContentPadding(fallback: 118, gap: 10), 128)
        XCTAssertEqual(state.scrollButtonBottomPadding(fallback: 118), 130)
    }

    func testUsesMeasuredHeightAfterUpdate() {
        var state = InputBarLayoutState()

        XCTAssertTrue(state.updateMeasuredHeight(142))

        XCTAssertEqual(state.effectiveHeight(fallback: 118), 142)
        XCTAssertEqual(state.bottomContentPadding(fallback: 118, gap: 10), 152)
    }

    func testIgnoresTinyMeasurementChanges() {
        var state = InputBarLayoutState(measuredHeight: 142)

        XCTAssertFalse(state.updateMeasuredHeight(142.25))
        XCTAssertEqual(state.measuredHeight, 142)
    }

    func testAcceptsMeaningfulMeasurementChanges() {
        var state = InputBarLayoutState(measuredHeight: 142)

        XCTAssertTrue(state.updateMeasuredHeight(142.75))
        XCTAssertEqual(state.measuredHeight, 142.75)
    }
}
