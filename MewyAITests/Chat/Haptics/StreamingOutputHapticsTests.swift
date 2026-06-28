import XCTest
@testable import MewyAI

final class StreamingOutputHapticsTests: XCTestCase {
    func testContinuationImpactCountStartsAfterLongTextThreshold() {
        XCTAssertEqual(StreamingOutputHaptics.continuationImpactCount(forUTF16Length: 900), 0)
        XCTAssertEqual(StreamingOutputHaptics.continuationImpactCount(forUTF16Length: 901), 1)
    }

    func testContinuationImpactCountIsCapped() {
        XCTAssertEqual(StreamingOutputHaptics.continuationImpactCount(forUTF16Length: 7_200), 8)
        XCTAssertEqual(StreamingOutputHaptics.continuationImpactCount(forUTF16Length: 72_000), 8)
    }
}
