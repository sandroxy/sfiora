import CoreFoundation
import Foundation

#if canImport(Sfiora)
    import Sfiora
#endif

enum SfioraBridgeWriteRequestError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

struct SfioraBridgeWriteRequest {
    private static let messageKeys: Set<String> = ["records"]
    private static let markerKeys: Set<String> = ["domain", "type"]
    private static let writeOptionKeys: Set<String> = [
        "timeoutMilliseconds",
        "messages",
    ]
    private static let textRecordKeys: Set<String> = [
        "kind",
        "text",
        "languageCode",
        "encoding",
        "identifierBase64",
    ]
    private static let uriRecordKeys: Set<String> = [
        "kind",
        "uri",
        "identifierBase64",
    ]
    private static let mimeRecordKeys: Set<String> = [
        "kind",
        "mediaType",
        "payloadBase64",
        "identifierBase64",
    ]
    private static let externalRecordKeys: Set<String> = [
        "kind",
        "domain",
        "type",
        "payloadBase64",
        "identifierBase64",
    ]
    private static let standardBase64Pattern =
        #"^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"#

    let message: NdefMessage
    let writerConfiguration: NfcWriteConfiguration

    static func parse(
        message rawMessage: Any?,
        options rawOptions: Any?
    ) throws -> SfioraBridgeWriteRequest {
        do {
            return SfioraBridgeWriteRequest(
                message: try parseMessage(rawMessage),
                writerConfiguration: try parseWriterConfiguration(rawOptions)
            )
        } catch let error as SfioraBridgeWriteRequestError {
            throw error
        } catch {
            throw SfioraBridgeWriteRequestError.invalid(
                error.localizedDescription
            )
        }
    }

    static func parseExternalTypeMarker(
        _ rawMarker: Any?
    ) throws -> NdefExternalType {
        do {
            let marker = try dictionary(rawMarker, name: "marker")
            try validateKeys(
                marker,
                allowed: markerKeys,
                name: "marker"
            )
            return try NdefExternalType(
                domain: requiredString(
                    marker,
                    key: "domain",
                    name: "marker.domain"
                ),
                type: requiredString(
                    marker,
                    key: "type",
                    name: "marker.type"
                )
            )
        } catch let error as SfioraBridgeWriteRequestError {
            throw error
        } catch {
            throw SfioraBridgeWriteRequestError.invalid(
                error.localizedDescription
            )
        }
    }

    private static func parseMessage(
        _ rawMessage: Any?
    ) throws -> NdefMessage {
        let message = try dictionary(rawMessage, name: "message")
        try validateKeys(message, allowed: messageKeys, name: "message")
        guard let rawRecords = message["records"] else {
            throw invalid("message.records is required")
        }
        guard let records = rawRecords as? [Any] else {
            throw invalid("message.records must be an array")
        }
        guard !records.isEmpty else {
            throw invalid("message.records must not be empty")
        }

        let parsedRecords = try records.enumerated().map { index, record in
            try parseRecord(
                record,
                name: "message.records[\(index)]"
            )
        }
        return try NdefMessage(records: parsedRecords)
    }

    private static func parseRecord(
        _ rawRecord: Any,
        name: String
    ) throws -> NdefRecord {
        let record = try dictionary(rawRecord, name: name)
        let kind = try requiredString(
            record,
            key: "kind",
            name: "\(name).kind"
        )

        switch kind {
        case "text":
            try validateKeys(record, allowed: textRecordKeys, name: name)
            let encoding: NdefTextEncoding
            if let rawEncoding = record["encoding"] {
                let value = try string(
                    rawEncoding,
                    name: "\(name).encoding"
                )
                guard
                    let parsedEncoding = NdefTextEncoding(
                        rawValue: value
                    )
                else {
                    throw invalid(
                        "\(name).encoding must be UTF-8 or UTF-16"
                    )
                }
                encoding = parsedEncoding
            } else {
                encoding = .utf8
            }
            return try NdefRecord.text(
                try requiredString(
                    record,
                    key: "text",
                    name: "\(name).text",
                    allowEmpty: true
                ),
                languageCode: try requiredString(
                    record,
                    key: "languageCode",
                    name: "\(name).languageCode"
                ),
                encoding: encoding,
                identifier: try optionalBase64(
                    record,
                    key: "identifierBase64",
                    name: "\(name).identifierBase64"
                )
            )
        case "uri":
            try validateKeys(record, allowed: uriRecordKeys, name: name)
            return try NdefRecord.uri(
                try requiredString(
                    record,
                    key: "uri",
                    name: "\(name).uri"
                ),
                identifier: try optionalBase64(
                    record,
                    key: "identifierBase64",
                    name: "\(name).identifierBase64"
                )
            )
        case "mime":
            try validateKeys(record, allowed: mimeRecordKeys, name: name)
            return try NdefRecord.mime(
                mediaType: try requiredString(
                    record,
                    key: "mediaType",
                    name: "\(name).mediaType"
                ),
                payload: try requiredBase64(
                    record,
                    key: "payloadBase64",
                    name: "\(name).payloadBase64"
                ),
                identifier: try optionalBase64(
                    record,
                    key: "identifierBase64",
                    name: "\(name).identifierBase64"
                )
            )
        case "external":
            try validateKeys(
                record,
                allowed: externalRecordKeys,
                name: name
            )
            return try NdefRecord.external(
                domain: try requiredString(
                    record,
                    key: "domain",
                    name: "\(name).domain"
                ),
                type: try requiredString(
                    record,
                    key: "type",
                    name: "\(name).type"
                ),
                payload: try requiredBase64(
                    record,
                    key: "payloadBase64",
                    name: "\(name).payloadBase64"
                ),
                identifier: try optionalBase64(
                    record,
                    key: "identifierBase64",
                    name: "\(name).identifierBase64"
                )
            )
        default:
            throw invalid(
                "\(name).kind must be text, uri, mime, or external"
            )
        }
    }

    private static func parseWriterConfiguration(
        _ rawOptions: Any?
    ) throws -> NfcWriteConfiguration {
        let options = try dictionary(
            rawOptions,
            name: "options",
            nilAsEmpty: true
        )
        try validateKeys(
            options,
            allowed: writeOptionKeys,
            name: "options"
        )
        let timeoutMilliseconds =
            try options["timeoutMilliseconds"].map {
                try integer($0, name: "timeoutMilliseconds")
            } ?? 30_000
        let presentationMessages =
            try options["messages"].map(
                SfioraBridgePresentationMessages.writer
            ) ?? .standard
        return try NfcWriteConfiguration(
            timeoutMilliseconds: timeoutMilliseconds,
            presentationMessages: presentationMessages
        )
    }

    private static func requiredBase64(
        _ values: NSDictionary,
        key: String,
        name: String
    ) throws -> Data {
        let value = try requiredString(
            values,
            key: key,
            name: name,
            allowEmpty: true
        )
        return try decodeBase64(value, name: name)
    }

    private static func optionalBase64(
        _ values: NSDictionary,
        key: String,
        name: String
    ) throws -> Data {
        guard values[key] != nil else {
            return Data()
        }
        return try requiredBase64(values, key: key, name: name)
    }

    private static func decodeBase64(
        _ value: String,
        name: String
    ) throws -> Data {
        guard
            value.range(
                of: standardBase64Pattern,
                options: .regularExpression
            ) != nil,
            let decoded = Data(base64Encoded: value, options: []),
            decoded.base64EncodedString() == value
        else {
            throw invalid("\(name) must be canonical padded Base64")
        }
        return decoded
    }

    private static func requiredString(
        _ values: NSDictionary,
        key: String,
        name: String,
        allowEmpty: Bool = false
    ) throws -> String {
        guard let value = values[key] else {
            throw invalid("\(name) is required")
        }
        return try string(value, name: name, allowEmpty: allowEmpty)
    }

    private static func dictionary(
        _ value: Any?,
        name: String,
        nilAsEmpty: Bool = false
    ) throws -> NSDictionary {
        if value == nil, nilAsEmpty {
            return NSDictionary()
        }
        guard let value = value as? NSDictionary else {
            throw invalid("\(name) must be an object")
        }
        return value
    }

    private static func validateKeys(
        _ values: NSDictionary,
        allowed: Set<String>,
        name: String
    ) throws {
        for rawKey in values.allKeys {
            guard
                let key = rawKey as? String,
                allowed.contains(key)
            else {
                throw invalid(
                    "\(name) contains an unsupported field: \(rawKey)"
                )
            }
        }
    }

    private static func string(
        _ value: Any,
        name: String,
        allowEmpty: Bool = false
    ) throws -> String {
        guard
            let value = value as? String,
            allowEmpty || !value.isEmpty
        else {
            throw invalid(
                "\(name) must be \(allowEmpty ? "a string" : "a non-empty string")"
            )
        }
        return value
    }

    private static func integer(_ value: Any, name: String) throws -> Int {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw invalid("\(name) must be an integer")
        }

        let doubleValue = number.doubleValue
        guard
            doubleValue.isFinite,
            doubleValue.rounded(.towardZero) == doubleValue,
            doubleValue >= Double(Int.min),
            doubleValue <= Double(Int.max)
        else {
            throw invalid("\(name) must be an integer")
        }
        return Int(doubleValue)
    }

    private static func invalid(
        _ message: String
    ) -> SfioraBridgeWriteRequestError {
        .invalid(message)
    }
}
