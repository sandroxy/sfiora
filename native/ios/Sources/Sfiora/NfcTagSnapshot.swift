import Foundation

/// Platform-neutral NFC technology names reported in tag snapshots.
public enum NfcTechnology: String, Equatable, Hashable, Sendable {
    case nfcA
    case nfcB
    case nfcF
    case nfcV
    case isoDep
    case iso7816
    case iso15693
    case mifare
    case mifareClassic
    case mifareUltralight
    case mifarePlus
    case mifareDesfire
    case mifareUnknown
    case felica
    case ndef
    case ndefFormatable
    case nfcBarcode
    case unknown
}

/// NDEF access information observed during one tag operation.
public enum NfcNdefStatus: String, Equatable, Sendable {
    case notChecked
    case notSupported
    case readOnly
    case readWrite
    case read
    case readError
    case unknown
}

public enum NfcTagSnapshotError: Error, Equatable, Sendable {
    case invalidBridgeValue
    case stringEncodingFailed
}

/// Immutable typed data plus a complete bridge-safe representation of one tag.
public struct NfcTagSnapshot: Equatable, Sendable {
    public static let schemaVersion = 1

    public let identifier: Data?
    public let technologies: [NfcTechnology]
    public let nativeTechnologies: [String]
    public let ndefStatus: NfcNdefStatus
    public let ndefAccessStatus: NfcNdefStatus?
    public let ndefCapacityBytes: Int?
    public let ndefWritable: Bool?
    public let ndefCanMakeReadOnly: Bool?
    public let ndefType: String?
    public let ndefMessage: NdefMessage?
    public let ndefReadError: NfcNativeError?
    public let warnings: [String]
    public let discoveredAtEpochMilliseconds: Int64

    private let bridgeData: Data

    init(
        identifier: Data?,
        technologies: [NfcTechnology],
        nativeTechnologies: [String] = [],
        ndefStatus: NfcNdefStatus,
        ndefAccessStatus: NfcNdefStatus? = nil,
        ndefCapacityBytes: Int?,
        ndefWritable: Bool? = nil,
        ndefCanMakeReadOnly: Bool? = nil,
        ndefType: String? = nil,
        ndefMessage: NdefMessage?,
        ndefReadError: NfcNativeError? = nil,
        warnings: [String] = [],
        discoveredAtEpochMilliseconds: Int64 = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded()
        ),
        bridgeValues: [String: Any]? = nil
    ) throws {
        guard (ndefCapacityBytes ?? 0) >= 0 else {
            throw NfcTagSnapshotError.invalidBridgeValue
        }
        self.identifier = identifier.map { Data($0) }
        self.technologies = Self.unique(technologies)
        self.nativeTechnologies = nativeTechnologies
        self.ndefStatus = ndefStatus
        self.ndefAccessStatus = ndefAccessStatus
        self.ndefCapacityBytes = ndefCapacityBytes
        self.ndefWritable = ndefWritable
        self.ndefCanMakeReadOnly = ndefCanMakeReadOnly
        self.ndefType = ndefType
        self.ndefMessage = ndefMessage
        self.ndefReadError = ndefReadError
        self.warnings = warnings
        self.discoveredAtEpochMilliseconds = discoveredAtEpochMilliseconds

        let values =
            bridgeValues
            ?? Self.defaultBridgeValues(
                identifier: identifier,
                technologies: Self.unique(technologies),
                nativeTechnologies: nativeTechnologies,
                ndefStatus: ndefStatus,
                ndefAccessStatus: ndefAccessStatus,
                capacityBytes: ndefCapacityBytes,
                writable: ndefWritable,
                canMakeReadOnly: ndefCanMakeReadOnly,
                type: ndefType,
                message: ndefMessage,
                readError: ndefReadError,
                warnings: warnings,
                discoveredAt: discoveredAtEpochMilliseconds
            )
        guard JSONSerialization.isValidJSONObject(values) else {
            throw NfcTagSnapshotError.invalidBridgeValue
        }
        bridgeData = try JSONSerialization.data(
            withJSONObject: values,
            options: [.sortedKeys]
        )
    }

    /// Returns a fresh recursive value suitable for React Native or UniApp bridges.
    public var dictionary: [String: Any] {
        (try? JSONSerialization.jsonObject(with: bridgeData)) as? [String: Any] ?? [:]
    }

    public func jsonData(prettyPrinted: Bool = false) throws -> Data {
        guard prettyPrinted else {
            return Data(bridgeData)
        }
        return try JSONSerialization.data(
            withJSONObject: dictionary,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        let data = try jsonData(prettyPrinted: prettyPrinted)
        guard let value = String(data: data, encoding: .utf8) else {
            throw NfcTagSnapshotError.stringEncodingFailed
        }
        return value
    }

    private static func defaultBridgeValues(
        identifier: Data?,
        technologies: [NfcTechnology],
        nativeTechnologies: [String],
        ndefStatus: NfcNdefStatus,
        ndefAccessStatus: NfcNdefStatus?,
        capacityBytes: Int?,
        writable: Bool?,
        canMakeReadOnly: Bool?,
        type: String?,
        message: NdefMessage?,
        readError: NfcNativeError?,
        warnings: [String],
        discoveredAt: Int64
    ) -> [String: Any] {
        var root: [String: Any] = [
            "schemaVersion": schemaVersion,
            "platform": "ios",
            "discoveredAtEpochMs": discoveredAt,
            "id": bytesValue(identifier ?? Data()),
            "technologies": technologies.map(\.rawValue),
            "nativeTechnologies": nativeTechnologies,
            "platformDetails": ["ios": [String: Any]()],
            "warnings": warnings,
        ]
        guard ndefStatus != .notChecked else {
            return root
        }

        var ndef: [String: Any] = ["status": bridgeStatus(ndefStatus)]
        if let ndefAccessStatus {
            ndef["accessStatus"] = bridgeStatus(ndefAccessStatus)
        }
        if let capacityBytes {
            ndef["maxSize"] = capacityBytes
        }
        if let writable {
            ndef["writable"] = writable
        }
        if let canMakeReadOnly {
            ndef["canMakeReadOnly"] = canMakeReadOnly
        }
        if let type {
            ndef["type"] = type
        }
        if let readError {
            ndef["readError"] = readError.dictionary
        }
        if let message {
            addMessage(message, to: &ndef)
        } else {
            ndef["recordCount"] = 0
            ndef["records"] = [Any]()
        }
        root["ndef"] = ndef
        return root
    }

    private static func addMessage(
        _ message: NdefMessage,
        to value: inout [String: Any]
    ) {
        value["messageHex"] = hex(message.serializedData)
        value["messageBase64"] = message.serializedData.base64EncodedString()
        value["recordCount"] = message.records.count
        value["records"] = message.records.enumerated().map { index, record in
            var item: [String: Any] = [
                "index": index,
                "tnf": Int(record.typeNameFormat.rawValue),
                "tnfName": tnfName(record.typeNameFormat.rawValue),
            ]
            putBytes(record.type, name: "type", into: &item)
            putBytes(record.identifier, name: "id", into: &item)
            putBytes(record.payload, name: "payload", into: &item)
            if let typeAscii = printableAscii(record.type) {
                item["typeAscii"] = typeAscii
            }
            if let text = record.decodedText {
                item["text"] = text.text
                item["languageCode"] = text.languageCode
                item["textEncoding"] = text.encoding.rawValue
            }
            if let uri = record.decodedUri {
                item["uri"] = uri
            }
            if let mediaType = record.mediaType {
                item["mimeType"] = mediaType
            }
            if let externalType = record.externalType {
                item["externalType"] = externalType
            }
            return item
        }
    }

    static func bytesValue(_ data: Data) -> [String: Any] {
        [
            "hex": hex(data),
            "base64": data.base64EncodedString(),
            "length": data.count,
        ]
    }

    static func putBytes(
        _ data: Data?,
        name: String,
        into value: inout [String: Any]
    ) {
        let safeData = data ?? Data()
        value["\(name)Hex"] = hex(safeData)
        value["\(name)Base64"] = safeData.base64EncodedString()
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    static func printableAscii(_ data: Data) -> String? {
        guard !data.isEmpty, data.allSatisfy({ 0x20...0x7E ~= $0 }) else {
            return nil
        }
        return String(data: data, encoding: .ascii)
    }

    static func tnfName(_ value: UInt8) -> String {
        switch value {
        case 0x00: return "empty"
        case 0x01: return "wellKnown"
        case 0x02: return "mimeMedia"
        case 0x03: return "absoluteUri"
        case 0x04: return "externalType"
        case 0x05: return "unknown"
        case 0x06: return "unchanged"
        default: return "reserved"
        }
    }

    static func bridgeStatus(_ status: NfcNdefStatus) -> String {
        switch status {
        case .notChecked: return "notChecked"
        case .notSupported: return "unsupported"
        case .readOnly: return "readOnly"
        case .readWrite: return "writable"
        case .read: return "read"
        case .readError: return "readError"
        case .unknown: return "unknown"
        }
    }

    private static func unique(_ values: [NfcTechnology]) -> [NfcTechnology] {
        var seen: Set<NfcTechnology> = []
        return values.filter { seen.insert($0).inserted }
    }
}
