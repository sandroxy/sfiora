import XCTest

@testable import SfioraBridgeSupport

final class SfioraBridgeOptionsTests: XCTestCase {
    func testDefaultsMatchFrozenContract() throws {
        let options = try SfioraBridgeOptions.parse(nil)

        XCTAssertEqual(options.readerConfiguration.mode, .automatic)
        XCTAssertEqual(options.readerConfiguration.timeoutMilliseconds, 30_000)
        XCTAssertEqual(
            options.readerConfiguration.pollingTechnologies,
            [.iso14443, .iso15693]
        )
    }

    func testParsesPlatformSpecificOptions() throws {
        let options = try SfioraBridgeOptions.parse(
            [
                "mode": "discover",
                "timeoutMilliseconds": 12_000,
                "android": [
                    "presentation": "none",
                    "deepReadEnabled": true,
                    "presenceCheckDelayMilliseconds": 400,
                ],
                "ios": [
                    "pollingTechnologies": ["iso14443", "iso18092"]
                ],
            ] as NSDictionary)

        XCTAssertEqual(options.readerConfiguration.mode, .discover)
        XCTAssertEqual(options.readerConfiguration.timeoutMilliseconds, 12_000)
        XCTAssertEqual(
            options.readerConfiguration.pollingTechnologies,
            [.iso14443, .iso18092]
        )
    }

    func testParsesOnlyCompletePresentationMessages() throws {
        var messages = scanMessages()
        let options = try SfioraBridgeOptions.parse(
            [
                "messages": messages
            ] as NSDictionary)

        XCTAssertEqual(
            options.readerConfiguration.presentationMessages.instruction,
            "scan instruction"
        )

        messages.removeValue(forKey: "done")
        assertInvalid(["messages": messages])
        messages["done"] = "done"
        messages["unexpected"] = "unexpected"
        assertInvalid(["messages": messages])
        messages.removeValue(forKey: "unexpected")
        messages["done"] = " \n"
        assertInvalid(["messages": messages])
    }

    func testRejectsUnknownFieldsOnEitherPlatform() {
        assertInvalid(["unexpected": true])
        assertInvalid(["android": ["unexpected": true]])
        assertInvalid(["ios": ["unexpected": true]])
    }

    func testRejectsInvalidScalarTypesAndRanges() {
        assertInvalid(["timeoutMilliseconds": true])
        assertInvalid(["timeoutMilliseconds": 1_500.5])
        assertInvalid(["timeoutMilliseconds": 999])
        assertInvalid([
            "android": ["presenceCheckDelayMilliseconds": 49]
        ])
    }

    func testRejectsInvalidPollingTechnologyCollections() {
        assertInvalid(["ios": ["pollingTechnologies": []]])
        assertInvalid([
            "ios": ["pollingTechnologies": ["iso14443", "iso14443"]]
        ])
        assertInvalid([
            "ios": ["pollingTechnologies": ["unsupported"]]
        ])
    }

    private func assertInvalid(
        _ options: NSDictionary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SfioraBridgeOptions.parse(options),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error is SfioraBridgeOptionsError,
                "Unexpected error: \(error)",
                file: file,
                line: line
            )
        }
    }

    private func scanMessages() -> [String: String] {
        var messages = Dictionary(
            uniqueKeysWithValues: [
                "title",
                "instruction",
                "cancel",
                "done",
                "success",
                "failureTitle",
                "timeout",
                "nfcDisabled",
                "nfcUnsupported",
                "multipleTags",
                "reading",
                "tagLost",
                "unsupportedTag",
                "readFailed",
            ].map { ($0, $0) }
        )
        messages["instruction"] = "scan instruction"
        return messages
    }
}
