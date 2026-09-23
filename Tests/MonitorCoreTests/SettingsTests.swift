import XCTest
@testable import MonitorCore

final class SettingsTests: XCTestCase {
    func testOldSettingsKeepCustomValuesAndGainDefaultAnomalyLimit() throws {
        let oldData = Data(#"{"url":"https://example.com/custom","thresholdMilliseconds":2500,"intervalSeconds":12}"#.utf8)
        let decoded = try JSONDecoder().decode(MonitorSettings.self, from: oldData)
        XCTAssertEqual(decoded.url.absoluteString, "https://example.com/custom")
        XCTAssertEqual(decoded.thresholdMilliseconds, 2500)
        XCTAssertEqual(decoded.intervalSeconds, 12)
        let encoded = try JSONEncoder().encode(decoded)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(values["consecutiveAnomalyLimit"] as? Int, 3)
    }

    func testSavedAnomalyLimitSurvivesSettingsRoundTrip() throws {
        let data = Data(#"{"url":"https://example.com","thresholdMilliseconds":800,"intervalSeconds":2,"consecutiveAnomalyLimit":7}"#.utf8)
        let decoded = try JSONDecoder().decode(MonitorSettings.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(values["consecutiveAnomalyLimit"] as? Int, 7)
    }

    func testAnomalyLimitRequiresPositiveInteger() throws {
        for count in ["", "0", "-1", "1.5", "nan", "inf", "999999999999999999999"] {
            XCTAssertThrowsError(try MonitorSettings.validated(url: "https://example.com", threshold: "1000", interval: "5", consecutiveAnomalies: count), count)
        }
        let settings = try MonitorSettings.validated(url: "https://example.com", threshold: "1000", interval: "5", consecutiveAnomalies: " 2 ")
        XCTAssertEqual(settings.consecutiveAnomalyLimit, 2)
    }

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
