import Foundation
import XCTest

@testable import SfioraBridgeSupport

final class SfioraBridgeWriteRequestTests: XCTestCase {
    func testParsesSharedWriteFixtureWithoutChangingEncodedBytes() throws {
        let fixture = try bridgeWriteFixture()
        let request = try SfioraBridgeWriteRequest.parse(
            message: fixture["message"],
            options: fixture["options"]
        )
        let expected = try XCTUnwrap(
            fixture["expected"] as? [String: Any]
        )

        XCTAssertEqual(
            request.message.records.count,
            expected["recordCount"] as? Int
        )
        XCTAssertEqual(
            request.message.byteCount,
            expected["byteCount"] as? Int
        )
        XCTAssertEqual(
            request.message.serializedData.map {
                String(format: "%02X", $0)
            }.joined(),
            expected["messageHex"] as? String
        )
        XCTAssertEqual(
            request.message.serializedData.base64EncodedString(),
            expected["messageBase64"] as? String
        )
        XCTAssertEqual(
            request.writerConfiguration.timeoutMilliseconds,
            12_000
        )
    }

    func testAppliesFrozenDefaultsAndAllowsEmptyText() throws {
        let request = try SfioraBridgeWriteRequest.parse(
            message: [
                "records": [
                    [
                        "kind": "text",
                        "text": "",
                        "languageCode": "en",
                    ]
                ]
            ] as NSDictionary,
            options: nil
        )

        XCTAssertEqual(request.message.records.count, 1)
        XCTAssertEqual(
            request.writerConfiguration.timeoutMilliseconds,
            30_000
        )
    }

    func testParsesStrictExternalTypeInitializationMarker() throws {
        let marker = try SfioraBridgeWriteRequest.parseExternalTypeMarker(
            [
                "domain": "io.sfiora",
                "type": "credential",
            ] as NSDictionary)
        XCTAssertEqual(marker.value, "io.sfiora:credential")

        XCTAssertThrowsError(
            try SfioraBridgeWriteRequest.parseExternalTypeMarker(
                [
                    "domain": "Io.Sfiora",
                    "type": "credential",
                ] as NSDictionary)
        )
        XCTAssertThrowsError(
            try SfioraBridgeWriteRequest.parseExternalTypeMarker(
                [
                    "domain": "io.sfiora",
                    "type": "credential",
                    "extra": true,
                ] as NSDictionary)
        )
    }

    func testRejectsUnknownFieldsInvalidKindsAndInvalidTimeouts() {
        assertInvalid(message: [
            "records": [
                [
                    "kind": "uri",
                    "uri": "https://example.com",
                ]
            ],
            "unexpected": true,
        ])
        assertInvalid(message: [
            "records": [
                [
                    "kind": "uri",
                    "uri": "https://example.com",
                    "unexpected": true,
                ]
            ]
        ])
        assertInvalid(message: [
            "records": [["kind": "raw"]]
        ])
        assertInvalid(
            message: validUriMessage(),
            options: ["timeoutMilliseconds": true]
        )
        assertInvalid(
            message: validUriMessage(),
            options: ["timeoutMilliseconds": 999]
        )
        assertInvalid(
            message: validUriMessage(),
            options: ["unexpected": true]
        )
    }

    func testRejectsMissingPaddingAndNonCanonicalBase64() {
        assertInvalid(message: mimeMessage(payloadBase64: "AQI"))
        assertInvalid(message: mimeMessage(payloadBase64: "AB=="))
    }

    func testParsesOnlyCompletePresentationMessages() throws {
        var messages = writeMessages()
        let request = try SfioraBridgeWriteRequest.parse(
            message: validUriMessage(),
            options: ["messages": messages]
        )

        XCTAssertEqual(
            request.writerConfiguration.presentationMessages.writing,
            "writing"
        )

        messages.removeValue(forKey: "verifying")
        assertInvalid(message: validUriMessage(), options: ["messages": messages])
        messages["verifying"] = "verifying"
        messages["unexpected"] = "unexpected"
        assertInvalid(message: validUriMessage(), options: ["messages": messages])
        messages.removeValue(forKey: "unexpected")
        messages["verifying"] = " \n"
        assertInvalid(message: validUriMessage(), options: ["messages": messages])
    }

    private func bridgeWriteFixture() throws -> [String: Any] {
        var fixtureURL = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            fixtureURL.deleteLastPathComponent()
        }
        fixtureURL.appendPathComponent(
            "tests/fixtures/bridge-contract.json"
        )
        let data = try Data(contentsOf: fixtureURL)
        let document = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        return try XCTUnwrap(
            document["bridgeWriteRequest"] as? [String: Any]
        )
    }

    private func validUriMessage() -> NSDictionary {
        [
            "records": [
                [
                    "kind": "uri",
                    "uri": "https://example.com",
                ]
            ]
        ] as NSDictionary
    }

    private func mimeMessage(payloadBase64: String) -> NSDictionary {
        [
            "records": [
                [
                    "kind": "mime",
                    "mediaType": "application/octet-stream",
                    "payloadBase64": payloadBase64,
                ]
            ]
        ] as NSDictionary
    }

    private func assertInvalid(
        message: NSDictionary,
        options: NSDictionary? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SfioraBridgeWriteRequest.parse(
                message: message,
                options: options
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error is SfioraBridgeWriteRequestError,
                "Unexpected error: \(error)",
                file: file,
                line: line
            )
        }
    }

    private func writeMessages() -> [String: String] {
        Dictionary(
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
                "checking",
                "writing",
                "verifying",
                "tagLost",
                "tagReadOnly",
                "capacityExceeded",
                "unsupportedTag",
                "writeFailed",
                "verificationFailed",
            ].map { ($0, $0) }
        )
    }
}
