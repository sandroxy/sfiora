import Foundation

/// Type Name Format values valid for a complete, non-chunked NDEF record.
public enum NdefTypeNameFormat: UInt8, Sendable {
    case empty = 0x00
    case wellKnown = 0x01
    case mimeMedia = 0x02
    case absoluteUri = 0x03
    case externalType = 0x04
    case unknown = 0x05
}

/// Text encodings defined by the NFC Forum Text Record Type Definition.
public enum NdefTextEncoding: String, Sendable {
    case utf8 = "UTF-8"
    case utf16 = "UTF-16"
}

public enum NdefError: Error, Equatable, LocalizedError, Sendable {
    case emptyMessage
    case emptyRecordMustNotContainData
    case missingType(typeNameFormat: NdefTypeNameFormat)
    case typeNotAllowed(typeNameFormat: NdefTypeNameFormat)
    case typeTooLong(byteCount: Int)
    case identifierTooLong(byteCount: Int)
    case payloadTooLong(byteCount: Int)
    case messageEncodingFailed
    case invalidLanguageCode
    case textEncodingFailed
    case emptyUri
    case invalidMimeType
    case invalidExternalType

    public var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "An NDEF message must contain at least one record"
        case .emptyRecordMustNotContainData:
            return "An empty NDEF record cannot contain type, identifier, or payload"
        case .missingType(let typeNameFormat):
            return "NDEF record type is required for \(typeNameFormat)"
        case .typeNotAllowed(let typeNameFormat):
            return "NDEF record type is not allowed for \(typeNameFormat)"
        case .typeTooLong(let byteCount):
            return "NDEF record type is \(byteCount) bytes; the maximum is 255"
        case .identifierTooLong(let byteCount):
            return "NDEF record identifier is \(byteCount) bytes; the maximum is 255"
        case .payloadTooLong(let byteCount):
            return "NDEF record payload is \(byteCount) bytes; the maximum is 4294967295"
        case .messageEncodingFailed:
            return "The validated NDEF message could not be encoded"
        case .invalidLanguageCode:
            return "NDEF Text language code must be a 1 to 63 byte ASCII language tag"
        case .textEncodingFailed:
            return "The NDEF Text value could not be encoded"
        case .emptyUri:
            return "NDEF URI value cannot be empty"
        case .invalidMimeType:
            return "NDEF MIME type must be a valid ASCII type/subtype value"
        case .invalidExternalType:
            return "NDEF external type must be a lowercase domain:type value"
        }
    }
}

/// A successfully decoded NFC Forum Text record payload.
public struct NdefText: Equatable, Hashable, Sendable {
    public let text: String
    public let languageCode: String
    public let encoding: NdefTextEncoding
}
