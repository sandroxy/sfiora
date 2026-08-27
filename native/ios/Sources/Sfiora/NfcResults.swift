import Foundation

enum NfcResultEncodingError: Error {
    case invalidJsonValue
    case stringEncodingFailed
}

/// Result of an NDEF write that was immediately read back and verified.
public struct NfcWriteResult: Equatable, Sendable {
    public let tag: NfcTagSnapshot
    public let message: NdefMessage
    public let completedAtEpochMilliseconds: Int64

    init(
        tag: NfcTagSnapshot,
        message: NdefMessage,
        completedAtEpochMilliseconds: Int64 = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded()
        )
    ) {
        self.tag = tag
        self.message = message
        self.completedAtEpochMilliseconds = completedAtEpochMilliseconds
    }

    public var verified: Bool { true }
    public var bytesWritten: Int { message.byteCount }
    public var recordCount: Int { message.records.count }

    public var dictionary: [String: Any] {
        [
            "schemaVersion": 1,
            "platform": "ios",
            "operation": "writeNdef",
            "completedAtEpochMs": completedAtEpochMilliseconds,
            "verified": true,
            "bytesWritten": bytesWritten,
            "recordCount": recordCount,
            "messageHex": NfcTagSnapshot.hex(message.serializedData),
            "messageBase64": message.serializedData.base64EncodedString(),
            "tag": tag.dictionary,
        ]
    }

    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        try NfcResultEncoding.jsonData(
            dictionary,
            prettyPrinted: prettyPrinted
        )
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        try NfcResultEncoding.jsonString(
            dictionary,
            prettyPrinted: prettyPrinted
        )
    }
}

/// Outcome of preserving or initializing one marked NDEF message.
public enum NfcInitializationAction: String, Equatable, Sendable {
    case preserved
    case initialized
}

/// Result of one marker-based, single-tag NDEF initialization operation.
public struct NfcInitializationResult: Equatable, Sendable {
    public let action: NfcInitializationAction
    public let marker: NdefExternalType
    public let tag: NfcTagSnapshot
    public let writtenMessage: NdefMessage?
    public let completedAtEpochMilliseconds: Int64

    public var verified: Bool { action == .initialized }
    public var bytesWritten: Int { writtenMessage?.byteCount ?? 0 }
    public var recordCount: Int { writtenMessage?.records.count ?? 0 }

    public var dictionary: [String: Any] {
        var value: [String: Any] = [
            "schemaVersion": 1,
            "platform": "ios",
            "operation": "initializeNdef",
            "completedAtEpochMs": completedAtEpochMilliseconds,
            "action": action.rawValue,
            "marker": [
                "domain": marker.domain,
                "type": marker.type,
                "externalType": marker.value,
            ],
            "tag": tag.dictionary,
        ]
        if let writtenMessage {
            value["verified"] = true
            value["bytesWritten"] = writtenMessage.byteCount
            value["recordCount"] = writtenMessage.records.count
            value["messageHex"] = NfcTagSnapshot.hex(
                writtenMessage.serializedData
            )
            value["messageBase64"] = writtenMessage.serializedData
                .base64EncodedString()
        }
        return value
    }

    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        try NfcResultEncoding.jsonData(
            dictionary,
            prettyPrinted: prettyPrinted
        )
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        try NfcResultEncoding.jsonString(
            dictionary,
            prettyPrinted: prettyPrinted
        )
    }

    static func preserved(
        marker: NdefExternalType,
        tag: NfcTagSnapshot
    ) -> NfcInitializationResult {
        NfcInitializationResult(
            action: .preserved,
            marker: marker,
            tag: tag,
            writtenMessage: nil
        )
    }

    static func initialized(
        marker: NdefExternalType,
        tag: NfcTagSnapshot,
        message: NdefMessage
    ) -> NfcInitializationResult {
        NfcInitializationResult(
            action: .initialized,
            marker: marker,
            tag: tag,
            writtenMessage: message
        )
    }

    private init(
        action: NfcInitializationAction,
        marker: NdefExternalType,
        tag: NfcTagSnapshot,
        writtenMessage: NdefMessage?,
        completedAtEpochMilliseconds: Int64 = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded()
        )
    ) {
        precondition(
            action == .preserved
                ? writtenMessage == nil
                : writtenMessage != nil
        )
        self.action = action
        self.marker = marker
        self.tag = tag
        self.writtenMessage = writtenMessage
        self.completedAtEpochMilliseconds = completedAtEpochMilliseconds
    }
}

private enum NfcResultEncoding {
    static func jsonData(
        _ values: [String: Any],
        prettyPrinted: Bool
    ) throws -> Data {
        guard JSONSerialization.isValidJSONObject(values) else {
            throw NfcResultEncodingError.invalidJsonValue
        }
        let options: JSONSerialization.WritingOptions =
            prettyPrinted
            ? [.prettyPrinted, .sortedKeys]
            : [.sortedKeys]
        return try JSONSerialization.data(
            withJSONObject: values,
            options: options
        )
    }

    static func jsonString(
        _ values: [String: Any],
        prettyPrinted: Bool
    ) throws -> String {
        let data = try jsonData(values, prettyPrinted: prettyPrinted)
        guard let value = String(data: data, encoding: .utf8) else {
            throw NfcResultEncodingError.stringEncodingFailed
        }
        return value
    }
}
