import CoreFoundation
import Foundation

/// iOS owns Core NFC presentation and does not expose Android foreground dispatch.
/// Validate inputs before reporting an unsupported capability, identically on every bridge.
public enum SfioraBridgeHostCapabilities {
    public static func response(method: String, argument: Any? = nil) -> NSDictionary {
        switch method {
        case "getForegroundDispatchState":
            return [
                "ok": true,
                "data": [
                    "platform": "ios", "revision": 0, "state": "unavailable", "error": NSNull(),
                ],
            ]
        case "getPresentationState":
            return [
                "ok": true,
                "data": [
                    "platform": "ios", "supported": false, "activePresentationIds": [String](),
                ],
            ]
        case "acquireForegroundDispatch", "releaseForegroundDispatch":
            guard let owner = argument as? String,
                owner.range(
                    of: "\\A[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\\z", options: .regularExpression)
                    != nil
            else {
                return error(
                    "INVALID_OPTIONS",
                    "ownerId must be 1-128 ASCII letters, digits, '.', '_', ':' or '-', starting with a letter or digit",
                    true)
            }
        case "waitForPresentationEnd":
            guard let values = argument as? NSDictionary,
                values.allKeys.allSatisfy({ ($0 as? String) == "timeoutMilliseconds" })
            else {
                return error(
                    "INVALID_OPTIONS",
                    "waitForPresentationEnd options must contain only timeoutMilliseconds", true)
            }
            if let raw = values["timeoutMilliseconds"] {
                guard let value = raw as? NSNumber,
                    CFGetTypeID(value) != CFBooleanGetTypeID(),
                    value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
                    (1...60000).contains(value.doubleValue)
                else {
                    return error(
                        "INVALID_OPTIONS", "timeoutMilliseconds must be an integer from 1 to 60000",
                        true)
                }
            }
        default:
            return error("INVALID_OPTIONS", "Unknown NFC host capability method", true)
        }
        return error(
            "NFC_UNSUPPORTED",
            "This capability is available only for Sfiora-managed Android hosts and panels", false)
    }

    private static func error(_ code: String, _ message: String, _ recoverable: Bool)
        -> NSDictionary
    {
        ["ok": false, "error": ["code": code, "message": message, "recoverable": recoverable]]
    }
}
