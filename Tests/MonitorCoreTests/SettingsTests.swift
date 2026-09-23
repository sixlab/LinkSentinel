import XCTest
@testable import MonitorCore

final class SettingsTests: XCTestCase {
    func testTrimsURLAndAcceptsHTTP() throws {
        let settings = try MonitorSettings.validated(url: "  http://localhost:8080/health  ", threshold: "1000", interval: "5")
        XCTAssertEqual(settings.url.absoluteString, "http://localhost:8080/health")
        XCTAssertEqual(settings.thresholdMilliseconds, 1000)
        XCTAssertEqual(settings.intervalSeconds, 5)
    }

    func testRejectsMalformedOrNonHTTPURLs() {
        for url in ["", "google.com", "file:///tmp/test", "https://", "https://exa mple.com", "https://user:secret@example.com"] {
            XCTAssertThrowsError(try MonitorSettings.validated(url: url, threshold: "1000", interval: "5"), url)
        }
    }

    func testRejectsZeroNegativeNonfiniteAndOverflowingTimes() {
        for threshold in ["0", "-1", "nan", "inf", "1.5", "3600001", "999999999999999999999"] {
            XCTAssertThrowsError(try MonitorSettings.validated(url: "https://example.com", threshold: threshold, interval: "5"), threshold)
        }
        for interval in ["0", "-1", "nan", "inf", "0.01", "86401"] {
            XCTAssertThrowsError(try MonitorSettings.validated(url: "https://example.com", threshold: "1000", interval: interval), interval)
        }
    }
}
