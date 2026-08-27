import Foundation

struct NdefRecordValue: Equatable, Sendable {
    let typeNameFormat: UInt8
    let type: Data
    let identifier: Data
    let payload: Data
}

enum NdefMessageEncodingError: Error, Equatable {
    case invalidTypeNameFormat(UInt8)
    case typeTooLong(Int)
    case identifierTooLong(Int)
    case payloadTooLong(Int)
}

enum NdefMessageEncoder {
    static func encode(_ records: [NdefRecordValue]) throws -> Data {
        var message = Data()

        for (index, record) in records.enumerated() {
            guard record.typeNameFormat <= 0x07 else {
                throw NdefMessageEncodingError.invalidTypeNameFormat(
                    record.typeNameFormat
                )
            }
            guard record.type.count <= Int(UInt8.max) else {
                throw NdefMessageEncodingError.typeTooLong(record.type.count)
            }
            guard record.identifier.count <= Int(UInt8.max) else {
                throw NdefMessageEncodingError.identifierTooLong(
                    record.identifier.count
                )
            }
            guard UInt64(record.payload.count) <= UInt64(UInt32.max) else {
                throw NdefMessageEncodingError.payloadTooLong(
                    record.payload.count
                )
            }

            let isShortRecord = record.payload.count <= Int(UInt8.max)
            let hasIdentifier = !record.identifier.isEmpty
            var header = record.typeNameFormat & 0x07
            if index == records.startIndex {
                header |= 0x80
            }
            if index == records.index(before: records.endIndex) {
                header |= 0x40
            }
            if isShortRecord {
                header |= 0x10
            }
            if hasIdentifier {
                header |= 0x08
            }

            message.append(header)
            message.append(UInt8(record.type.count))
            if isShortRecord {
                message.append(UInt8(record.payload.count))
            } else {
                let length = UInt32(record.payload.count)
                message.append(UInt8((length >> 24) & 0xFF))
                message.append(UInt8((length >> 16) & 0xFF))
                message.append(UInt8((length >> 8) & 0xFF))
                message.append(UInt8(length & 0xFF))
            }
            if hasIdentifier {
                message.append(UInt8(record.identifier.count))
            }
            message.append(record.type)
            if hasIdentifier {
                message.append(record.identifier)
            }
            message.append(record.payload)
        }

        return message
    }
}

enum NdefPayloadDecoder {
    static func decodeText(_ payload: Data) -> NdefText? {
        guard let status = payload.first, status & 0x40 == 0 else {
            return nil
        }
        let languageLength = Int(status & 0x3F)
        guard payload.count >= 1 + languageLength else {
            return nil
        }

        let languageData = payload.subdata(in: 1..<(1 + languageLength))
        guard
            NdefRecord.isValidLanguageCode(
                languageData,
                allowEmpty: true
            ),
            let languageCode = decodeAscii(languageData)
        else {
            return nil
        }

        let textData = payload.subdata(
            in: (1 + languageLength)..<payload.count
        )
        let usesUtf16 = status & 0x80 != 0
        let text: String?
        if usesUtf16 {
            let hasByteOrderMark =
                textData.starts(with: [0xFE, 0xFF])
                || textData.starts(with: [0xFF, 0xFE])
            text = String(
                data: textData,
                encoding: hasByteOrderMark ? .utf16 : .utf16BigEndian
            )
        } else {
            text = String(data: textData, encoding: .utf8)
        }
        guard let text else {
            return nil
        }
        return NdefText(
            text: text,
            languageCode: languageCode,
            encoding: usesUtf16 ? .utf16 : .utf8
        )
    }

    static func decodeAscii(_ data: Data) -> String? {
        guard data.allSatisfy({ $0 < 0x80 }) else {
            return nil
        }
        return String(data: data, encoding: .ascii)
    }
}

enum NdefUriCodec {
    static let prefixes = [
        "",
        "http://www.",
        "https://www.",
        "http://",
        "https://",
        "tel:",
        "mailto:",
        "ftp://anonymous:anonymous@",
        "ftp://ftp.",
        "ftps://",
        "sftp://",
        "smb://",
        "nfs://",
        "ftp://",
        "dav://",
        "news:",
        "telnet://",
        "imap:",
        "rtsp://",
        "urn:",
        "pop:",
        "sip:",
        "sips:",
        "tftp:",
        "btspp://",
        "btl2cap://",
        "btgoep://",
        "tcpobex://",
        "irdaobex://",
        "file://",
        "urn:epc:id:",
        "urn:epc:tag:",
        "urn:epc:pat:",
        "urn:epc:raw:",
        "urn:epc:",
        "urn:nfc:",
    ]

    static func encode(_ uri: String) -> Data {
        let match = prefixes.enumerated()
            .dropFirst()
            .filter { uri.hasPrefix($0.element) }
            .max { lhs, rhs in
                lhs.element.count < rhs.element.count
            }

        let prefixIndex = match?.offset ?? 0
        let suffix =
            match.map {
                String(uri.dropFirst($0.element.count))
            } ?? uri
        var payload = Data([UInt8(prefixIndex)])
        payload.append(Data(suffix.utf8))
        return payload
    }

    static func decode(_ payload: Data) -> String? {
        guard let prefixCode = payload.first else {
            return nil
        }
        let prefixIndex = Int(prefixCode)
        guard prefixes.indices.contains(prefixIndex) else {
            return nil
        }
        guard
            let suffix = String(
                data: payload.dropFirst(),
                encoding: .utf8
            )
        else {
            return nil
        }
        return prefixes[prefixIndex] + suffix
    }
}
