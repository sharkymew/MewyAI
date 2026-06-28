import XCTest
@testable import MewyAI

final class CustomHeaderSecurityTests: XCTestCase {
    func testEncodedHeadersReplacesSensitiveValuesOnly() {
        let encoded = CustomHeaderSecurity.encodedHeaders("""
        Authorization: Bearer secret
        X-Trace: keep
        X-API-Key: key-value
        """)

        XCTAssertTrue(encoded.contains("Authorization: \(CustomHeaderSecurity.keychainPlaceholder)"))
        XCTAssertTrue(encoded.contains("X-Trace: keep"))
        XCTAssertTrue(encoded.contains("X-API-Key: \(CustomHeaderSecurity.keychainPlaceholder)"))
    }

    func testRequestHeadersFiltersForbiddenAndPlaceholderValues() {
        let headers = CustomHeaderSecurity.requestHeaders(from: """
        Host: example.com
        Authorization: \(CustomHeaderSecurity.keychainPlaceholder)
        X-Trace: ok
        X Bad: invalid
        """)

        XCTAssertEqual(headers.map(\.name), ["X-Trace"])
        XCTAssertEqual(headers.map(\.value), ["ok"])
    }

    func testSensitiveHeaderDiscoveryIgnoresStoredPlaceholders() {
        let headers = """
        Authorization: \(CustomHeaderSecurity.keychainPlaceholder)
        X-API-Key: live-secret
        X-Trace: ok
        """

        XCTAssertTrue(CustomHeaderSecurity.containsPersistableSensitiveHeader(headers))
        XCTAssertEqual(CustomHeaderSecurity.sensitiveHeaderValues(from: headers), ["live-secret"])
    }
}
