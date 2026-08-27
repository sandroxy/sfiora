import Foundation
import XCTest

@testable import Sfiora

final class NdefValidationTests: XCTestCase {
    func testModelEqualityIncludesAllRecordBytes() throws {
        let first = try NdefRecord.text("one", languageCode: "en")
        let same = try NdefRecord.text("one", languageCode: "en")
        let different = try NdefRecord.text("two", languageCode: "en")
        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(
            try NdefMessage(records: [first]),
            try NdefMessage(records: [same])
        )
    }

    func testInvalidRecordShapesAreRejected() {
        XCTAssertThrowsError(
            try NdefRecord(
                typeNameFormat: .empty,
                type: Data(),
                payload: Data([0x01])
            )
        )
        XCTAssertThrowsError(
            try NdefRecord(
                typeNameFormat: .wellKnown,
                type: Data(),
                payload: Data()
            )
        )
        XCTAssertThrowsError(
            try NdefRecord(
                typeNameFormat: .unknown,
                type: Data([0x58]),
                payload: Data()
            )
        )
        XCTAssertThrowsError(
            try NdefRecord(
                typeNameFormat: .wellKnown,
                type: Data(repeating: 0, count: 256),
                payload: Data()
            )
        )
        XCTAssertThrowsError(
            try NdefRecord(
                typeNameFormat: .wellKnown,
                type: Data([0x58]),
                identifier: Data(repeating: 0, count: 256),
                payload: Data()
            )
        )
    }

    func testInvalidMessagesAndFactoryInputsAreRejected() {
        XCTAssertThrowsError(try NdefMessage(records: []))
        for languageCode in ["", "-en", "en-", "en--US", "中文"] {
            XCTAssertThrowsError(
                try NdefRecord.text("text", languageCode: languageCode),
                languageCode
            )
        }
        XCTAssertThrowsError(try NdefRecord.uri(""))
        XCTAssertThrowsError(
            try NdefRecord.mime(mediaType: "invalid", payload: Data())
        )
        XCTAssertThrowsError(
            try NdefRecord.external(
                domain: "Example.org",
                type: "sample",
                payload: Data()
            )
        )
    }

    func testMalformedConveniencePayloadsDoNotProduceGuessedValues() throws {
        let reservedTextStatus = try NdefRecord(
            typeNameFormat: .wellKnown,
            type: Data([0x54]),
            payload: Data([0x40])
        )
        XCTAssertNil(reservedTextStatus.decodedText)

        let malformedUtf8Text = try NdefRecord(
            typeNameFormat: .wellKnown,
            type: Data([0x54]),
            payload: Data([0x02, 0x65, 0x6E, 0xC3, 0x28])
        )
        XCTAssertNil(malformedUtf8Text.decodedText)

        let unknownUriPrefix = try NdefRecord(
            typeNameFormat: .wellKnown,
            type: Data([0x55]),
            payload: Data([0xFF])
        )
        XCTAssertNil(unknownUriPrefix.decodedUri)

        let invalidMime = try NdefRecord(
            typeNameFormat: .mimeMedia,
            type: Data("not a/type".utf8),
            payload: Data()
        )
        XCTAssertNil(invalidMime.mediaType)
    }

    func testDecodersPreserveValidNonCanonicalWireValues() throws {
        let textWithoutLanguage = try NdefRecord(
            typeNameFormat: .wellKnown,
            type: Data([0x54]),
            payload: Data([0x00, 0x41])
        )
        XCTAssertEqual(textWithoutLanguage.decodedText?.languageCode, "")
        XCTAssertEqual(textWithoutLanguage.decodedText?.text, "A")

        let mixedCaseExternalType = try NdefRecord(
            typeNameFormat: .externalType,
            type: Data("Example.ORG:Member".utf8),
            payload: Data()
        )
        XCTAssertEqual(
            mixedCaseExternalType.externalType,
            "Example.ORG:Member"
        )
    }

    func testUtf16DecoderHonorsAnExplicitByteOrderMark() throws {
        let littleEndianText = try NdefRecord(
            typeNameFormat: .wellKnown,
            type: Data([0x54]),
            payload: Data([
                0x82,
                0x65,
                0x6E,
                0xFF,
                0xFE,
                0x41,
                0x00,
            ])
        )
        XCTAssertEqual(littleEndianText.decodedText?.text, "A")
        XCTAssertEqual(littleEndianText.decodedText?.encoding, .utf16)
    }

    func testExternalTypesFollowTheNfcForumAsciiShape() throws {
        let valid = try NdefRecord.external(
            domain: "example.org",
            type: "member_status+v1",
            payload: Data()
        )
        XCTAssertEqual(valid.externalType, "example.org:member_status+v1")

        for domain in [
            ".example.org",
            "example..org",
            "-example.org",
            "example-.org",
        ] {
            XCTAssertThrowsError(
                try NdefRecord.external(
                    domain: domain,
                    type: "member",
                    payload: Data()
                ),
                domain
            )
        }
        XCTAssertThrowsError(
            try NdefRecord.external(
                domain: "example.org",
                type: "member:type",
                payload: Data()
            )
        )
    }
}
