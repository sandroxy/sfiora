import Foundation

#if os(iOS) && canImport(Sfiora)
    import Sfiora

    /// Process-wide coordinator shared by the React Native and UniApp
    /// adapters. It exposes Foundation values only; NFC state and protocol work
    /// remain owned by `NfcClient`.
    @objc(SfioraBridgeCoordinator)
    @objcMembers
    public final class SfioraBridgeCoordinator: NSObject {
        public typealias SuccessHandler = (NSDictionary) -> Void
        public typealias FailureHandler = (NSDictionary) -> Void

        public static let shared = SfioraBridgeCoordinator()

        private let client = NfcClient()

        private override init() {
            super.init()
        }

        public func getCapabilities() -> NSDictionary {
            client.capabilities.dictionary as NSDictionary
        }

        @objc(startScanWithOptions:success:failure:)
        public func startScan(
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeOptions.parse(options)
                    self.client.startRead(
                        configuration: request.readerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        public func cancelScan() {
            client.cancelRead()
        }

        public func isScanning() -> Bool {
            client.isReading
        }

        @objc(writeNdefWithMessage:options:success:failure:)
        public func writeNdef(
            message: NSDictionary,
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeWriteRequest.parse(
                        message: message,
                        options: options
                    )
                    self.client.startWrite(
                        message: request.message,
                        configuration: request.writerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        @objc(initializeNdefWithMessage:marker:options:success:failure:)
        public func initializeNdef(
            message: NSDictionary,
            marker: NSDictionary,
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeWriteRequest.parse(
                        message: message,
                        options: options
                    )
                    let externalType =
                        try SfioraBridgeWriteRequest
                        .parseExternalTypeMarker(marker)
                    try self.client.startInitialize(
                        message: request.message,
                        marker: externalType,
                        configuration: request.writerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        public func cancelWrite() {
            client.cancelWrite()
        }

        public func isWriting() -> Bool {
            client.isWriting
        }

        public func stop() {
            client.stop()
        }

        /// A Foundation-only transport for UTS. The same parsers and client
        /// serve all adapters; JSON carries values without platform type casts.
        @objc(invokeJSON:argumentsJSON:completion:)
        public func invokeJSON(
            _ method: String,
            argumentsJSON: String,
            completion: @escaping (String) -> Void
        ) {
            runOnMain {
                let emit: (Bool, Any) -> Void = { ok, value in
                    let envelope: [String: Any] = ["ok": ok, ok ? "data" : "error": value]
                    do {
                        let data = try JSONSerialization.data(withJSONObject: envelope)
                        completion(String(decoding: data, as: UTF8.self))
                    } catch {
                        completion(
                            "{\"ok\":false,\"error\":{\"code\":\"INTERNAL_ERROR\","
                                + "\"message\":\"Unable to encode NFC result\",\"recoverable\":false}}"
                        )
                    }
                }
                let success: SuccessHandler = { emit(true, $0) }
                let failure: FailureHandler = { emit(false, $0) }
                do {
                    guard
                        let args = try JSONSerialization.jsonObject(
                            with: Data(argumentsJSON.utf8)
                        ) as? [Any],
                        let count = [
                            "getCapabilities": 0, "startScan": 1, "cancelScan": 0,
                            "isScanning": 0, "writeNdef": 2, "initializeNdef": 3,
                            "cancelWrite": 0, "isWriting": 0,
                        ][method], args.count == count
                    else {
                        throw NfcError(
                            code: .invalidOptions, message: "Invalid NFC method or arguments",
                            recoverable: true
                        )
                    }
                    func object(_ index: Int) throws -> NSDictionary {
                        guard let value = args[index] as? NSDictionary else {
                            throw NfcError(
                                code: .invalidOptions, message: "NFC arguments must be objects",
                                recoverable: true
                            )
                        }
                        return value
                    }
                    switch method {
                    case "getCapabilities": emit(true, self.getCapabilities())
                    case "isScanning": emit(true, self.isScanning())
                    case "isWriting": emit(true, self.isWriting())
                    case "cancelScan":
                        self.cancelScan()
                        emit(true, [:] as [String: Any])
                    case "cancelWrite":
                        self.cancelWrite()
                        emit(true, [:] as [String: Any])
                    case "startScan":
                        self.startScan(options: try object(0), success: success, failure: failure)
                    case "writeNdef":
                        self.writeNdef(
                            message: try object(0), options: try object(1), success: success,
                            failure: failure
                        )
                    case "initializeNdef":
                        self.initializeNdef(
                            message: try object(0), marker: try object(1), options: try object(2),
                            success: success, failure: failure
                        )
                    default: break
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        private func runOnMain(_ operation: @escaping () -> Void) {
            if Thread.isMainThread {
                operation()
            } else {
                DispatchQueue.main.async(execute: operation)
            }
        }

        private static func finish<Value>(
            _ result: Result<Value, NfcError>,
            value: (Value) -> [String: Any],
            success: SuccessHandler,
            failure: FailureHandler
        ) {
            switch result {
            case .success(let resultValue):
                success(value(resultValue) as NSDictionary)
            case .failure(let error):
                failure(error.dictionary as NSDictionary)
            }
        }

        private static func invalidOptions(_ error: Error) -> NSDictionary {
            NfcError(
                code: .invalidOptions,
                message: error.localizedDescription,
                recoverable: true,
                nativeError: NfcNativeError(error)
            ).dictionary as NSDictionary
        }
    }
#endif
