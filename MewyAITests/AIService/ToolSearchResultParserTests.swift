import XCTest
@testable import MewyAI

final class ToolSearchResultParserTests: XCTestCase {
    func testParsesNestedSearchResultsAndDeduplicatesURLs() {
        let content = """
        {
          "structuredContent": {
            "results": [
              { "title": "First", "url": "https://example.com/a" },
              { "title": "Duplicate", "url": "https://example.com/a" },
              { "title": "Second", "url": "https://example.com/b" }
            ]
          }
        }
        """

        let results = ToolSearchResultParser.results(from: content)

        XCTAssertEqual(results.map(\.title), ["First", "Second"])
        XCTAssertEqual(results.map(\.url.absoluteString), [
            "https://example.com/a",
            "https://example.com/b"
        ])
    }

    func testRejectsURLsWithCredentials() {
        let content = #"{ "results": [{ "title": "Bad", "url": "https://user:pass@example.com" }] }"#

        XCTAssertTrue(ToolSearchResultParser.results(from: content).isEmpty)
    }
}
