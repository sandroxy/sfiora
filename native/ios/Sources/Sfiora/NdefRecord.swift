import Foundation

/// One immutable, complete NDEF record.
///
/// The factory methods implement common NFC Forum record types without
/// interpreting or transforming application payloads.
public struct NdefRecord: Equatable, Hashable, Sendable {
    private static let textType = Data([0x54])
    private static let uriType = Data([0x55])

    public let typeNameFormat: NdefTypeNameFormat
    public let type: Data
    public let identifier: Data
    public let payload: Data

    public init(
        typeNameFormat: NdefTypeNameFormat,
        type: Data,
        identifier: Data = Data(),
        payload: Data
    ) throws {
        guard type.count <= Int(UInt8.max) else {
            throw NdefError.typeTooLong(byteCount: type.count)
        }
        guard identifier.count <= Int(UInt8.max) else {
            throw NdefError.identifierTooLong(byteCount: identifier.count)
        }
        guard UInt64(payload.count) <= UInt64(UInt32.max) else {
            throw NdefError.payloadTooLong(byteCount: payload.count)
        }

        switch typeNameFormat {
        case .empty:
            guard type.isEmpty, identifier.isEmpty, payload.isEmpty else {
                throw NdefError.emptyRecordMustNotContainData
            }
        case .wellKnown, .mimeMedia, .absoluteUri, .externalType:
            guard !type.isEmpty else {
                throw NdefError.missingType(typeNameFormat: typeNameFormat)
            }
        case .unknown:
            guard type.isEmpty else {
                throw NdefError.typeNotAllowed(typeNameFormat: typeNameFormat)
            }
        }

        self.typeNameFormat = typeNameFormat
        self.type = Data(type)
        self.identifier = Data(identifier)
        self.payload = Data(payload)
    }

    public static func text(
        _ text: String,
        languageCode: String,
        encoding: NdefTextEncoding = .utf8,
        identifier: Data = Data()
    ) throws -> NdefRecord {
        let languageBytes = Data(languageCode.utf8)
        guard isValidLanguageCode(languageBytes) else {
            throw NdefError.invalidLanguageCode
        }

        let textData: Data?
        switch encoding {
        case .utf8:
            textData = text.data(using: .utf8)
        case .utf16:
            textData = text.data(using: .utf16BigEndian)
        }
        guard let textData else {
            throw NdefError.textEncodingFailed
        }

        let encodingFlag: UInt8 = encoding == .utf16 ? 0x80 : 0x00
        var encodedPayload = Data([
            encodingFlag | UInt8(languageBytes.count)
        ])
        encodedPayload.append(languageBytes)
        encodedPayload.append(textData)
        return try NdefRecord(
            typeNameFormat: .wellKnown,
            type: textType,
            identifier: identifier,
            payload: encodedPayload
        )
    }

    public static func uri(
        _ uri: String,
        identifier: Data = Data()
    ) throws -> NdefRecord {
        guard !uri.isEmpty else {
            throw NdefError.emptyUri
        }
        return try NdefRecord(
            typeNameFormat: .wellKnown,
            type: uriType,
            identifier: identifier,
            payload: NdefUriCodec.encode(uri)
        )
    }

    public static func mime(
        mediaType: String,
        payload: Data,
        identifier: Data = Data()
    ) throws -> NdefRecord {
        guard isValidMimeType(mediaType) else {
            throw NdefError.invalidMimeType
        }
        return try NdefRecord(
            typeNameFormat: .mimeMedia,
            type: Data(mediaType.utf8),
            identifier: identifier,
            payload: payload
        )
    }

    public static func external(
        domain: String,
        type: String,
        payload: Data,
        identifier: Data = Data()
    ) throws -> NdefRecord {
        let externalType = "\(domain):\(type)"
        guard
            externalType == externalType.lowercased(),
            isValidExternalType(externalType)
        else {
            throw NdefError.invalidExternalType
        }
        return try NdefRecord(
            typeNameFormat: .externalType,
            type: Data(externalType.utf8),
            identifier: identifier,
            payload: payload
        )
    }

    /// The decoded value when this is a well-formed NFC Forum Text record.
    public var decodedText: NdefText? {
        guard typeNameFormat == .wellKnown, type == Self.textType else {
            return nil
        }
        return NdefPayloadDecoder.decodeText(payload)
    }

    /// The decoded URI when this is a well-known URI or absolute-URI record.
    public var decodedUri: String? {
        if typeNameFormat == .wellKnown, type == Self.uriType {
            return NdefUriCodec.decode(payload)
        }
        if typeNameFormat == .absoluteUri {
            return String(data: type, encoding: .utf8)
        }
        return nil
    }

    /// A validated MIME media type when this is a MIME record.
    public var mediaType: String? {
        guard
            typeNameFormat == .mimeMedia,
            let value = NdefPayloadDecoder.decodeAscii(type),
            Self.isValidMimeType(value)
        else {
            return nil
        }
        return value
    }

    /// A validated NFC Forum external type when this is an external record.
    public var externalType: String? {
        guard
            typeNameFormat == .externalType,
            let value = NdefPayloadDecoder.decodeAscii(type),
            Self.isValidExternalType(value)
        else {
            return nil
        }
        return value
    }

    var recordValue: NdefRecordValue {
        NdefRecordValue(
            typeNameFormat: typeNameFormat.rawValue,
            type: type,
            identifier: identifier,
            payload: payload
        )
    }

    static func isValidLanguageCode(
        _ bytes: Data,
        allowEmpty: Bool = false
    ) -> Bool {
        guard (allowEmpty ? 0...63 : 1...63) ~= bytes.count else {
            return false
        }
        var previousWasHyphen = false
        for (index, byte) in bytes.enumerated() {
            let isHyphen = byte == 0x2D
            let isAlphanumeric: Bool
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                isAlphanumeric = true
            default:
                isAlphanumeric = false
            }
            if !isAlphanumeric && !isHyphen
                || isHyphen && (index == 0 || index == bytes.count - 1)
                || isHyphen && previousWasHyphen
            {
                return false
            }
            previousWasHyphen = isHyphen
        }
        return true
    }

    static func isValidMimeType(_ mediaType: String) -> Bool {
        let parts = mediaType.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else {
            return false
        }
        return parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy(isMimeTokenByte)
        }
    }

    static func isValidExternalType(_ externalType: String) -> Bool {
        let parts = externalType.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else {
            return false
        }
        return isValidDomain(parts[0])
            && isValidExternalTypeName(parts[1])
    }

    private static func isValidDomain(_ domain: Substring) -> Bool {
        guard !domain.isEmpty else {
            return false
        }
        return domain.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).allSatisfy { label in
            guard
                1...63 ~= label.utf8.count,
                let first = label.utf8.first,
                let last = label.utf8.last,
                isAsciiAlphanumeric(first),
                isAsciiAlphanumeric(last)
            else {
                return false
            }
            return label.utf8.allSatisfy {
                isAsciiAlphanumeric($0) || $0 == 0x2D
            }
        }
    }

    private static func isValidExternalTypeName(
        _ typeName: Substring
    ) -> Bool {
        guard !typeName.isEmpty else {
            return false
        }
        return typeName.utf8.allSatisfy { byte in
            isAsciiAlphanumeric(byte)
                || externalTypePunctuation.contains(byte)
        }
    }

    private static let externalTypePunctuation = Data(
        "$'()*+,-.;=@_".utf8
    )

    private static func isAsciiAlphanumeric(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    private static func isMimeTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        case 0x21, 0x23...0x27, 0x2A...0x2B, 0x2D...0x2E,
            0x5E...0x60, 0x7C, 0x7E:
            return true
        default:
            return false
        }
    }
}
