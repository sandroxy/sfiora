import Foundation
import SfioraBridgeSupport
import XCTest

final class SfioraBridgeHostCapabilitiesTests: XCTestCase {
    func testReportsSystemOwnedPresentationAndUnavailableForegroundDispatch() {
        let foreground = SfioraBridgeHostCapabilities.response(method: "getForegroundDispatchState")
        XCTAssertEqual(foreground["ok"] as? Bool, true)
        XCTAssertEqual((foreground["data"] as? NSDictionary)?["state"] as? String, "unavailable")
        let presentation = SfioraBridgeHostCapabilities.response(method: "getPresentationState")
        let data = presentation["data"] as? NSDictionary
        XCTAssertEqual(data?["supported"] as? Bool, false)
        XCTAssertEqual(data?["activePresentationIds"] as? [String], [])
    }

    func testValidOperationsRejectUnsupportedAndInvalidInputsRejectInvalidOptions() {
        for method in ["acquireForegroundDispatch", "releaseForegroundDispatch"] {
            XCTAssertEqual(code(method, "screen:owner-1"), "NFC_UNSUPPORTED")
            XCTAssertEqual(code(method, String(repeating: "x", count: 128)), "NFC_UNSUPPORTED")
            for owner in [
                "", "a\n", "a\r", "a\u{2028}", "中文", "/a", String(repeating: "x", count: 129),
            ] {
                XCTAssertEqual(code(method, owner), "INVALID_OPTIONS", owner)
            }
            XCTAssertEqual(code(method, 1), "INVALID_OPTIONS")
            XCTAssertEqual(code(method, nil), "INVALID_OPTIONS")
        }
        XCTAssertEqual(code("waitForPresentationEnd", [:]), "NFC_UNSUPPORTED")
        for timeout in [1, 5000, 60000] {
            XCTAssertEqual(
                code("waitForPresentationEnd", ["timeoutMilliseconds": timeout]), "NFC_UNSUPPORTED")
        }
        for raw: Any in [true, NSNull(), "100", 0, -1, 1.5, 60001, Double.nan] {
            XCTAssertEqual(
                code("waitForPresentationEnd", ["timeoutMilliseconds": raw]), "INVALID_OPTIONS")
        }
        XCTAssertEqual(code("waitForPresentationEnd", ["other": 1]), "INVALID_OPTIONS")
        XCTAssertEqual(code("waitForPresentationEnd", nil), "INVALID_OPTIONS")
    }

    private func code(_ method: String, _ value: Any?) -> String? {
        (SfioraBridgeHostCapabilities.response(method: method, argument: value)["error"]
            as? NSDictionary)?["code"] as? String
    }
}
