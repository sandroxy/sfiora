import Foundation
import XCTest

@testable import Sfiora

final class NdefVectorsTests: XCTestCase {
    func testSharedRecordVectorsMatchPublicModel() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.fixtureVersion, 1)
        XCTAssertGreaterThanOrEqual(fixture.records.count, 5)

        for vector in fixture.records {
            let record = try makeRecord(vector)
            XCTAssertEqual(
                Int(record.typeNameFormat.rawValue),
                vector.expected.typeNameFormat,
                vector.name
            )
            XCTAssertEqual(record.type, try Data(hex: vector.expected.typeHex), vector.name)
            XCTAssertEqual(
                record.identifier,
                try Data(hex: vector.identifierHex),
                vector.name
            )
            XCTAssertEqual(
                record.payload,
                try Data(hex: vector.expected.payloadHex),
                vector.name
            )

            let message = try NdefMessage(records: [record])
            XCTAssertEqual(
                message.serializedData,
                try Data(hex: vector.expected.messageHex),
                vector.name
            )
            assertDecodedValues(vector, record: record)
        }
    }

    func testSharedMultiRecordVectorsSetMessageBoundaryFlags() throws {
        let fixture = try loadFixture()
        let recordsByName = try Dictionary(
            uniqueKeysWithValues: fixture.records.map {
                ($0.name, try makeRecord($0))
            }
        )

        for vector in fixture.messages {
            let records = try vector.recordNames.map { name in
                try XCTUnwrap(recordsByName[name], name)
            }
            let message = try NdefMessage(records: records)
            XCTAssertEqual(
                message.serializedData,
                try Data(hex: vector.messageHex),
                vector.name
            )
        }
    }

    func testSharedBoundaryVectorsSelectShortAndLongPayloadLengths() throws {
        let fixture = try loadFixture()
        for vector in fixture.encodingBoundaries {
            let payloadByte = try XCTUnwrap(Data(hex: vector.payloadByteHex).first)
            let payload = Data(repeating: payloadByte, count: vector.payloadLength)
            let typeNameFormat = try XCTUnwrap(
                NdefTypeNameFormat(rawValue: UInt8(vector.typeNameFormat))
            )
            let record = try NdefRecord(
                typeNameFormat: typeNameFormat,
                type: Data(hex: vector.typeHex),
                payload: payload
            )
            let message = try NdefMessage(records: [record])
            let prefix = try Data(hex: vector.messagePrefixHex)
            XCTAssertEqual(message.byteCount, vector.messageByteCount, vector.name)
            XCTAssertEqual(message.serializedData.prefix(prefix.count), prefix, vector.name)
        }
    }

    private func assertDecodedValues(
        _ vector: RecordVector,
        record: NdefRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let expectedText = vector.expected.decodedText {
            XCTAssertEqual(record.decodedText?.text, expectedText, file: file, line: line)
            XCTAssertEqual(
                record.decodedText?.languageCode,
                vector.expected.decodedLanguageCode,
                file: file,
                line: line
            )
            XCTAssertEqual(
                record.decodedText?.encoding.rawValue,
                vector.expected.decodedTextEncoding,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(record.decodedText, file: file, line: line)
        }
        XCTAssertEqual(
            record.decodedUri,
            vector.expected.decodedUri,
            file: file,
            line: line
        )
        XCTAssertEqual(
            record.mediaType,
            vector.expected.mediaType,
            file: file,
            line: line
        )
        XCTAssertEqual(
            record.externalType,
            vector.expected.externalType,
            file: file,
            line: line
        )
    }

    private func makeRecord(_ vector: RecordVector) throws -> NdefRecord {
        let identifier = try Data(hex: vector.identifierHex)
        switch vector.kind {
        case "text":
            return try NdefRecord.text(
                try XCTUnwrap(vector.text),
                languageCode: try XCTUnwrap(vector.languageCode),
                encoding: vector.encoding == "UTF-16" ? .utf16 : .utf8,
                identifier: identifier
            )
        case "uri":
            return try NdefRecord.uri(
                try XCTUnwrap(vector.uri),
                identifier: identifier
            )
        case "mime":
            return try NdefRecord.mime(
                mediaType: try XCTUnwrap(vector.mediaType),
                payload: Data(hex: try XCTUnwrap(vector.payloadHex)),
                identifier: identifier
            )
        case "external":
            return try NdefRecord.external(
                domain: try XCTUnwrap(vector.domain),
                type: try XCTUnwrap(vector.externalTypeName),
                payload: Data(hex: try XCTUnwrap(vector.payloadHex)),
                identifier: identifier
            )
        default:
            XCTFail("Unknown fixture kind: \(vector.kind)")
            throw FixtureError.unknownRecordKind(vector.kind)
        }
    }

    private func loadFixture() throws -> Fixture {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "ndef-vectors",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: url)
        )
    }
}

private enum FixtureError: Error {
    case unknownRecordKind(String)
}

private struct Fixture: Decodable {
    let fixtureVersion: Int
    let records: [RecordVector]
    let messages: [MessageVector]
    let encodingBoundaries: [BoundaryVector]
}

private struct RecordVector: Decodable {
    let name: String
    let kind: String
    let text: String?
    let languageCode: String?
    let encoding: String?
    let uri: String?
    let mediaType: String?
    let domain: String?
    let externalTypeName: String?
    let payloadHex: String?
    let identifierHex: String
    let expected: ExpectedRecord
}

private struct ExpectedRecord: Decodable {
    let typeNameFormat: Int
    let typeHex: String
    let payloadHex: String
    let messageHex: String
    let decodedText: String?
    let decodedLanguageCode: String?
    let decodedTextEncoding: String?
    let decodedUri: String?
    let mediaType: String?
    let externalType: String?
}

private struct MessageVector: Decodable {
    let name: String
    let recordNames: [String]
    let messageHex: String
}

private struct BoundaryVector: Decodable {
    let name: String
    let typeNameFormat: Int
    let typeHex: String
    let payloadByteHex: String
    let payloadLength: Int
    let messagePrefixHex: String
    let messageByteCount: Int
}

extension Data {
    fileprivate init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else {
            throw HexError.invalidLength
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let byte = UInt8(hex[cursor..<next], radix: 16) else {
                throw HexError.invalidCharacter
            }
            bytes.append(byte)
            cursor = next
        }
        self.init(bytes)
    }
}

private enum HexError: Error {
    case invalidLength
    case invalidCharacter
}
