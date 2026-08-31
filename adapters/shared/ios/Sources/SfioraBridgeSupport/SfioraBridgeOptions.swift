import CoreFoundation
import Foundation

#if canImport(Sfiora)
    import Sfiora
#endif

enum SfioraBridgeOptionsError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

struct SfioraBridgeOptions {
    private static let rootKeys: Set<String> = [
        "mode",
        "timeoutMilliseconds",
        "android",
        "ios",
        "messages",
    ]
    private static let androidKeys: Set<String> = [
        "presentation",
        "deepReadEnabled",
        "presenceCheckDelayMilliseconds",
    ]
    private static let iosKeys: Set<String> = ["pollingTechnologies"]
    private static let pollingTechnologyValues: Set<String> = [
        "iso14443",
        "iso15693",
        "iso18092",
    ]

    let readerConfiguration: NfcReadConfiguration

    static func parse(_ rawOptions: Any?) throws -> SfioraBridgeOptions {
        let options = try dictionary(
            rawOptions,
            name: "options",
            nilAsEmpty: true
        )
        try validateKeys(options, allowed: rootKeys, name: "options")

        let mode = try options["mode"].map(readMode) ?? .automatic
        let timeoutMilliseconds =
            try options["timeoutMilliseconds"].map {
                try integer($0, name: "timeoutMilliseconds")
            } ?? 30_000

        if let rawAndroid = options["android"] {
            try validateAndroidOptions(rawAndroid)
        }

        let pollingTechnologies: Set<NfcPollingTechnology>
        if let rawIos = options["ios"] {
            pollingTechnologies = try readIosOptions(rawIos)
        } else {
            pollingTechnologies = [.iso14443, .iso15693]
        }
        let presentationMessages: NfcReaderPresentationMessages
        do {
            presentationMessages =
                try options["messages"].map(
                    SfioraBridgePresentationMessages.reader
                ) ?? .standard
        } catch {
            throw SfioraBridgeOptionsError.invalid(error.localizedDescription)
        }

        do {
            return SfioraBridgeOptions(
                readerConfiguration: try NfcReadConfiguration(
                    mode: mode,
                    timeoutMilliseconds: timeoutMilliseconds,
                    pollingTechnologies: pollingTechnologies,
                    presentationMessages: presentationMessages
                )
            )
        } catch let error as NfcConfigurationError {
            throw SfioraBridgeOptionsError.invalid(
                error.errorDescription ?? "The NFC scan options are invalid"
            )
        }
    }

    private static func readMode(_ value: Any) throws -> NfcReadMode {
        switch try string(value, name: "mode") {
        case "automatic":
            return .automatic
        case "ndef":
            return .ndef
        case "discover":
            return .discover
        default:
            throw SfioraBridgeOptionsError.invalid(
                "mode must be automatic, ndef, or discover"
            )
        }
    }

    private static func validateAndroidOptions(_ value: Any) throws {
        let options = try dictionary(value, name: "android")
        try validateKeys(options, allowed: androidKeys, name: "android")

        if let presentation = options["presentation"] {
            let value = try string(
                presentation,
                name: "android.presentation"
            )
            guard value == "managed" || value == "none" else {
                throw SfioraBridgeOptionsError.invalid(
                    "android.presentation must be managed or none"
                )
            }
        }

        if let deepReadEnabled = options["deepReadEnabled"] {
            try boolean(
                deepReadEnabled,
                name: "android.deepReadEnabled"
            )
        }

        if let rawDelay = options["presenceCheckDelayMilliseconds"] {
            let delay = try integer(
                rawDelay,
                name: "android.presenceCheckDelayMilliseconds"
            )
            guard 50...5_000 ~= delay else {
                throw SfioraBridgeOptionsError.invalid(
                    "android.presenceCheckDelayMilliseconds must be between 50 and 5000"
                )
            }
        }
    }

    private static func readIosOptions(
        _ value: Any
    ) throws -> Set<NfcPollingTechnology> {
        let options = try dictionary(value, name: "ios")
        try validateKeys(options, allowed: iosKeys, name: "ios")

        guard let rawTechnologies = options["pollingTechnologies"] else {
            return [.iso14443, .iso15693]
        }
        guard let values = rawTechnologies as? [Any], !values.isEmpty else {
            throw SfioraBridgeOptionsError.invalid(
                "ios.pollingTechnologies must be a non-empty array"
            )
        }

        var rawUniqueValues = Set<String>()
        var technologies = Set<NfcPollingTechnology>()
        for (index, rawValue) in values.enumerated() {
            let name = "ios.pollingTechnologies[\(index)]"
            let value = try string(rawValue, name: name)
            guard pollingTechnologyValues.contains(value) else {
                throw SfioraBridgeOptionsError.invalid(
                    "ios.pollingTechnologies contains an unsupported value"
                )
            }
            guard rawUniqueValues.insert(value).inserted else {
                throw SfioraBridgeOptionsError.invalid(
                    "ios.pollingTechnologies must not contain duplicates"
                )
            }
            guard let technology = NfcPollingTechnology(rawValue: value) else {
                throw SfioraBridgeOptionsError.invalid(
                    "ios.pollingTechnologies contains an unsupported value"
                )
            }
            technologies.insert(technology)
        }
        return technologies
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
            throw SfioraBridgeOptionsError.invalid("\(name) must be an object")
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
                throw SfioraBridgeOptionsError.invalid(
                    "\(name) contains an unsupported field: \(rawKey)"
                )
            }
        }
    }

    private static func string(_ value: Any, name: String) throws -> String {
        guard let value = value as? String, !value.isEmpty else {
            throw SfioraBridgeOptionsError.invalid(
                "\(name) must be a non-empty string"
            )
        }
        return value
    }

    @discardableResult
    private static func boolean(_ value: Any, name: String) throws -> Bool {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw SfioraBridgeOptionsError.invalid("\(name) must be a boolean")
        }
        return number.boolValue
    }

    private static func integer(_ value: Any, name: String) throws -> Int {
        guard
            let number = value as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else {
            throw SfioraBridgeOptionsError.invalid("\(name) must be an integer")
        }

        let doubleValue = number.doubleValue
        guard
            doubleValue.isFinite,
            doubleValue.rounded(.towardZero) == doubleValue,
            doubleValue >= Double(Int.min),
            doubleValue <= Double(Int.max)
        else {
            throw SfioraBridgeOptionsError.invalid("\(name) must be an integer")
        }
        return Int(doubleValue)
    }
}
