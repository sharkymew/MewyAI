import UIKit
import XCTest
@testable import MewyAI

final class MarkdownInlineFormatterTests: XCTestCase {
    func testFormatsBoldCodeAndSafeLinkWithoutLeavingMarkdownDelimiters() {
        let attributed = MarkdownInlineFormatter.attributedString(
            from: "Hello **bold** `code` [site](https://example.com)",
            font: .systemFont(ofSize: 17),
            textColor: .label,
            textAlignment: .left
        )

        XCTAssertEqual(attributed.string, "Hello bold code site")
        XCTAssertNotNil(attributed.attribute(.link, at: attributed.range(of: "site").location, effectiveRange: nil))
        XCTAssertNotNil(attributed.attribute(.backgroundColor, at: attributed.range(of: "code").location, effectiveRange: nil))
    }

    func testUnsafeLinkDoesNotReceiveLinkAttribute() {
        let attributed = MarkdownInlineFormatter.attributedString(
            from: "[bad](https://user:pass@example.com)",
            font: .systemFont(ofSize: 17),
            textColor: .label,
            textAlignment: .left
        )

        XCTAssertEqual(attributed.string, "bad")
        XCTAssertNil(attributed.attribute(.link, at: 0, effectiveRange: nil))
    }
}

private extension NSAttributedString {
    func range(of text: String) -> NSRange {
        (string as NSString).range(of: text)
    }
}
