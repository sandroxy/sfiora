#if os(iOS) && canImport(CoreNFC)
    import CoreNFC
    import Foundation

    struct NfcPlatformTagContext {
        let identifier: Data
        let nativeTechnology: String
        let technologies: [NfcTechnology]
        let iosDetails: [String: Any]
        let ndefTag: NFCNDEFTag
        let warnings: [String]
    }

    struct NfcPlatformNdefObservation {
        let status: NfcNdefStatus
        let accessStatus: NfcNdefStatus?
        let capacityBytes: Int?
        let writable: Bool?
        let nativeType: String?
        let platformMessage: NFCNDEFMessage?
        let message: NdefMessage?
        let readError: NfcNativeError?
        let warning: String?

        static func notChecked() -> NfcPlatformNdefObservation {
            NfcPlatformNdefObservation(
                status: .notChecked,
                accessStatus: nil,
                capacityBytes: nil,
                writable: nil,
                nativeType: nil,
                platformMessage: nil,
                message: nil,
                readError: nil,
                warning: nil
            )
        }

        static func unsupported() -> NfcPlatformNdefObservation {
            NfcPlatformNdefObservation(
                status: .notSupported,
                accessStatus: nil,
                capacityBytes: nil,
                writable: nil,
                nativeType: nil,
                platformMessage: nil,
                message: nil,
                readError: nil,
                warning: nil
            )
        }
    }

    enum NfcPlatformCodec {
        static func fromPlatform(_ message: NFCNDEFMessage?) throws -> NdefMessage? {
            guard let message else {
                return nil
            }
            do {
                let records = try message.records.map { record in
                    guard
                        let typeNameFormat = NdefTypeNameFormat(
                            rawValue: record.typeNameFormat.rawValue
                        )
                    else {
                        throw NfcError(
                            code: .readFailed,
                            message: "The tag contains an unsupported NDEF type name format",
                            recoverable: false
                        )
                    }
                    return try NdefRecord(
                        typeNameFormat: typeNameFormat,
                        type: record.type,
                        identifier: record.identifier,
                        payload: record.payload
                    )
                }
                return try NdefMessage(records: records)
            } catch let error as NfcError {
                throw error
            } catch {
                throw NfcError(
                    code: .readFailed,
                    message: "The tag contains an unsupported or malformed NDEF message",
                    recoverable: false,
                    nativeError: NfcNativeError(error)
                )
            }
        }

        static func tolerantMessage(
            _ message: NFCNDEFMessage?
        ) -> (NdefMessage?, String?) {
            do {
                return (try fromPlatform(message), nil)
            } catch {
                return (
                    nil,
                    "The raw NDEF message was preserved, but it could not be "
                        + "represented by Sfiora's typed NDEF model."
                )
            }
        }

        static func toPlatform(_ message: NdefMessage) -> NFCNDEFMessage {
            NFCNDEFMessage(
                records: message.records.map { record in
                    NFCNDEFPayload(
                        format: platformTypeNameFormat(record.typeNameFormat),
                        type: record.type,
                        identifier: record.identifier,
                        payload: record.payload
                    )
                }
            )
        }

        static func context(for tag: NFCTag) throws -> NfcPlatformTagContext {
            switch tag {
            case .miFare(let value):
                var details: [String: Any] = ["tagType": "mifare"]
                var mifare: [String: Any] = [
                    "family": mifareFamilyName(value.mifareFamily),
                    "familyValue": Int(value.mifareFamily.rawValue),
                ]
                NfcTagSnapshot.putBytes(
                    value.historicalBytes,
                    name: "historicalBytes",
                    into: &mifare
                )
                details["mifare"] = mifare

                var technologies: [NfcTechnology] = [.nfcA, .mifare]
                var warnings: [String] = []
                switch value.mifareFamily {
                case .unknown:
                    technologies.append(.mifareUnknown)
                    warnings.append(
                        "Core NFC reports an unknown MIFARE-compatible tag; "
                            + "the exact product family is unavailable."
                    )
                case .ultralight:
                    technologies.append(.mifareUltralight)
                case .plus:
                    technologies.append(.mifarePlus)
                case .desfire:
                    technologies.append(contentsOf: [.isoDep, .mifareDesfire])
                @unknown default:
                    technologies.append(.mifareUnknown)
                    warnings.append("Core NFC returned an unrecognized MIFARE family.")
                }
                return NfcPlatformTagContext(
                    identifier: value.identifier,
                    nativeTechnology: "CoreNFC.NFCMiFareTag",
                    technologies: technologies,
                    iosDetails: details,
                    ndefTag: value,
                    warnings: warnings
                )

            case .iso7816(let value):
                var details: [String: Any] = ["tagType": "iso7816"]
                var iso7816: [String: Any] = [
                    "initialSelectedAID": value.initialSelectedAID,
                    "proprietaryApplicationDataCoding":
                        value.proprietaryApplicationDataCoding,
                ]
                NfcTagSnapshot.putBytes(
                    value.historicalBytes,
                    name: "historicalBytes",
                    into: &iso7816
                )
                NfcTagSnapshot.putBytes(
                    value.applicationData,
                    name: "applicationData",
                    into: &iso7816
                )
                details["iso7816"] = iso7816
                return NfcPlatformTagContext(
                    identifier: value.identifier,
                    nativeTechnology: "CoreNFC.NFCISO7816Tag",
                    technologies: [.isoDep, .iso7816],
                    iosDetails: details,
                    ndefTag: value,
                    warnings: []
                )

            case .iso15693(let value):
                var details: [String: Any] = ["tagType": "iso15693"]
                var iso15693: [String: Any] = [
                    "icManufacturerCode": value.icManufacturerCode
                ]
                NfcTagSnapshot.putBytes(
                    value.icSerialNumber,
                    name: "icSerialNumber",
                    into: &iso15693
                )
                details["iso15693"] = iso15693
                return NfcPlatformTagContext(
                    identifier: value.identifier,
                    nativeTechnology: "CoreNFC.NFCISO15693Tag",
                    technologies: [.nfcV, .iso15693],
                    iosDetails: details,
                    ndefTag: value,
                    warnings: []
                )

            case .feliCa(let value):
                var details: [String: Any] = ["tagType": "felica"]
                var felica: [String: Any] = [:]
                NfcTagSnapshot.putBytes(
                    value.currentSystemCode,
                    name: "currentSystemCode",
                    into: &felica
                )
                NfcTagSnapshot.putBytes(
                    value.currentIDm,
                    name: "currentIDm",
                    into: &felica
                )
                details["felica"] = felica
                return NfcPlatformTagContext(
                    identifier: value.currentIDm,
                    nativeTechnology: "CoreNFC.NFCFeliCaTag",
                    technologies: [.nfcF, .felica],
                    iosDetails: details,
                    ndefTag: value,
                    warnings: []
                )

            @unknown default:
                throw NfcError(
                    code: .unsupportedTag,
                    message: "Core NFC returned an unsupported tag protocol",
                    recoverable: true
                )
            }
        }

        static func snapshot(
            context: NfcPlatformTagContext,
            observation: NfcPlatformNdefObservation
        ) throws -> NfcTagSnapshot {
            var warnings = context.warnings
            if let warning = observation.warning {
                warnings.append(warning)
            }
            var technologies = context.technologies
            if observation.status != .notChecked
                && observation.status != .notSupported
            {
                technologies.append(.ndef)
            }
            technologies = unique(technologies)
            let discoveredAt = currentEpochMilliseconds()
            var root: [String: Any] = [
                "schemaVersion": NfcTagSnapshot.schemaVersion,
                "platform": "ios",
                "discoveredAtEpochMs": discoveredAt,
                "id": NfcTagSnapshot.bytesValue(context.identifier),
                "technologies": technologies.map(\.rawValue),
                "nativeTechnologies": [context.nativeTechnology],
                "platformDetails": ["ios": context.iosDetails],
                "warnings": warnings,
            ]
            if observation.status != .notChecked {
                root["ndef"] = try ndefValue(observation, warnings: &warnings)
                root["warnings"] = warnings
            }
            return try NfcTagSnapshot(
                identifier: context.identifier,
                technologies: technologies,
                nativeTechnologies: [context.nativeTechnology],
                ndefStatus: observation.status,
                ndefAccessStatus: observation.accessStatus,
                ndefCapacityBytes: observation.capacityBytes,
                ndefWritable: observation.writable,
                ndefType: observation.nativeType,
                ndefMessage: observation.message,
                ndefReadError: observation.readError,
                warnings: warnings,
                discoveredAtEpochMilliseconds: discoveredAt,
                bridgeValues: root
            )
        }

        static func compatibilitySnapshot(
            message: NFCNDEFMessage,
            detectedMessageCount: Int,
            status: NfcNdefStatus = .read,
            writable: Bool? = nil,
            capacityBytes: Int? = nil
        ) throws -> NfcTagSnapshot {
            var warnings = [
                "NDEF compatibility mode does not expose the tag UID or "
                    + "protocol-specific metadata."
            ]
            if detectedMessageCount > 1 {
                warnings.append(
                    "Core NFC returned \(detectedMessageCount) NDEF messages; "
                        + "this snapshot contains the first message."
                )
            }
            let (typedMessage, conversionWarning) = tolerantMessage(message)
            if let conversionWarning {
                warnings.append(conversionWarning)
            }
            let discoveredAt = currentEpochMilliseconds()
            let nativeTechnology = "CoreNFC.NFCNDEFReaderSession"
            let observation = NfcPlatformNdefObservation(
                status: status,
                accessStatus: writable == nil ? .unknown : nil,
                capacityBytes: capacityBytes,
                writable: writable,
                nativeType: nativeTechnology,
                platformMessage: message,
                message: typedMessage,
                readError: nil,
                warning: nil
            )
            var ndefWarnings = warnings
            let ndef = try ndefValue(observation, warnings: &ndefWarnings)
            let root: [String: Any] = [
                "schemaVersion": NfcTagSnapshot.schemaVersion,
                "platform": "ios",
                "discoveredAtEpochMs": discoveredAt,
                "id": NfcTagSnapshot.bytesValue(Data()),
                "technologies": [NfcTechnology.ndef.rawValue],
                "nativeTechnologies": [nativeTechnology],
                "ndef": ndef,
                "platformDetails": [
                    "ios": [
                        "tagType": "ndefCompatibility",
                        "tagMetadataAvailable": false,
                    ]
                ],
                "warnings": ndefWarnings,
            ]
            return try NfcTagSnapshot(
                identifier: nil,
                technologies: [.ndef],
                nativeTechnologies: [nativeTechnology],
                ndefStatus: status,
                ndefAccessStatus: writable == nil ? .unknown : nil,
                ndefCapacityBytes: capacityBytes,
                ndefWritable: writable,
                ndefType: nativeTechnology,
                ndefMessage: typedMessage,
                warnings: ndefWarnings,
                discoveredAtEpochMilliseconds: discoveredAt,
                bridgeValues: root
            )
        }

        static func status(_ value: NFCNDEFStatus) throws -> NfcNdefStatus {
            switch value {
            case .notSupported:
                return .notSupported
            case .readOnly:
                return .readOnly
            case .readWrite:
                return .readWrite
            @unknown default:
                throw NfcError(
                    code: .unsupportedTag,
                    message: "Core NFC returned an unknown NDEF access status",
                    recoverable: true
                )
            }
        }

        static func containsMarker(
            _ marker: NdefExternalType,
            in message: NFCNDEFMessage?
        ) -> Bool {
            message?.records.contains { record in
                marker.matches(
                    typeNameFormat: record.typeNameFormat.rawValue,
                    type: record.type
                )
            } ?? false
        }

        private static func ndefValue(
            _ observation: NfcPlatformNdefObservation,
            warnings: inout [String]
        ) throws -> [String: Any] {
            var value: [String: Any] = [
                "status": NfcTagSnapshot.bridgeStatus(observation.status)
            ]
            if let accessStatus = observation.accessStatus {
                value["accessStatus"] = NfcTagSnapshot.bridgeStatus(accessStatus)
            }
            if let writable = observation.writable {
                value["writable"] = writable
            }
            if let capacityBytes = observation.capacityBytes {
                value["maxSize"] = capacityBytes
            }
            if let nativeType = observation.nativeType {
                value["type"] = nativeType
            }
            if let readError = observation.readError {
                value["readError"] = readError.dictionary
            }
            guard let message = observation.platformMessage else {
                value["recordCount"] = 0
                value["records"] = [Any]()
                return value
            }
            let records = message.records.map {
                NdefRecordValue(
                    typeNameFormat: $0.typeNameFormat.rawValue,
                    type: $0.type,
                    identifier: $0.identifier,
                    payload: $0.payload
                )
            }
            let serialized = try NdefMessageEncoder.encode(records)
            value["messageHex"] = NfcTagSnapshot.hex(serialized)
            value["messageBase64"] = serialized.base64EncodedString()
            value["recordCount"] = records.count
            value["records"] = records.enumerated().map { index, record in
                inspectRecord(record, index: index, warnings: &warnings)
            }
            return value
        }

        private static func inspectRecord(
            _ record: NdefRecordValue,
            index: Int,
            warnings: inout [String]
        ) -> [String: Any] {
            var value: [String: Any] = [
                "index": index,
                "tnf": Int(record.typeNameFormat),
                "tnfName": NfcTagSnapshot.tnfName(record.typeNameFormat),
            ]
            NfcTagSnapshot.putBytes(record.type, name: "type", into: &value)
            NfcTagSnapshot.putBytes(record.identifier, name: "id", into: &value)
            NfcTagSnapshot.putBytes(record.payload, name: "payload", into: &value)

            let printableType = NfcTagSnapshot.printableAscii(record.type)
            if let printableType {
                value["typeAscii"] = printableType
            }
            if record.typeNameFormat == 0x01, record.type == Data([0x54]) {
                if let text = NdefPayloadDecoder.decodeText(record.payload) {
                    value["text"] = text.text
                    value["languageCode"] = text.languageCode
                    value["textEncoding"] = text.encoding.rawValue
                } else {
                    warnings.append("NDEF Text record \(index) has an invalid payload.")
                }
            }
            if record.typeNameFormat == 0x01, record.type == Data([0x55]) {
                if let uri = NdefUriCodec.decode(record.payload) {
                    value["uri"] = uri
                } else {
                    warnings.append("NDEF URI record \(index) has an invalid payload.")
                }
            } else if record.typeNameFormat == 0x03, let printableType {
                value["uri"] = printableType
            }
            if record.typeNameFormat == 0x02, let printableType {
                value["mimeType"] = printableType
            }
            if record.typeNameFormat == 0x04, let printableType {
                value["externalType"] = printableType
            }
            return value
        }

        private static func mifareFamilyName(_ family: NFCMiFareFamily) -> String {
            switch family {
            case .unknown: return "unknown"
            case .ultralight: return "ultralight"
            case .plus: return "plus"
            case .desfire: return "desfire"
            @unknown default: return "unknown"
            }
        }

        private static func currentEpochMilliseconds() -> Int64 {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }

        private static func unique(
            _ values: [NfcTechnology]
        ) -> [NfcTechnology] {
            var seen: Set<NfcTechnology> = []
            return values.filter { seen.insert($0).inserted }
        }

        private static func platformTypeNameFormat(
            _ value: NdefTypeNameFormat
        ) -> NFCTypeNameFormat {
            switch value {
            case .empty:
                return .empty
            case .wellKnown:
                return .nfcWellKnown
            case .mimeMedia:
                return .media
            case .absoluteUri:
                return .absoluteURI
            case .externalType:
                return .nfcExternal
            case .unknown:
                return .unknown
            }
        }
    }
#endif
