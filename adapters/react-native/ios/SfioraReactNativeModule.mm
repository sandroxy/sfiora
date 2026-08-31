#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTInvalidating.h>

#import "SfioraReactNative-Swift.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import <SfioraSpec/SfioraSpec.h>
#endif

@interface SfioraReactNativeModule : NSObject <
    RCTBridgeModule,
    RCTInvalidating
#ifdef RCT_NEW_ARCH_ENABLED
    , NativeSfioraSpec
#endif
>
@end

@implementation SfioraReactNativeModule

RCT_EXPORT_MODULE(Sfiora)

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(getCapabilities
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (__unused RCTPromiseRejectBlock)reject)
{
    resolve([[SfioraBridgeCoordinator shared] getCapabilities]);
}

RCT_EXPORT_METHOD(startScan
                  : (NSDictionary *)options
                  resolve
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (RCTPromiseRejectBlock)reject)
{
    [[SfioraBridgeCoordinator shared]
        startScanWithOptions:options
        success:^(NSDictionary *snapshot) {
            resolve(snapshot);
        }
        failure:^(NSDictionary *error) {
            [self reject:reject withPayload:error];
        }];
}

RCT_EXPORT_METHOD(cancelScan
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (__unused RCTPromiseRejectBlock)reject)
{
    [[SfioraBridgeCoordinator shared] cancelScan];
    resolve(nil);
}

RCT_EXPORT_METHOD(isScanning
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (__unused RCTPromiseRejectBlock)reject)
{
    resolve(@([[SfioraBridgeCoordinator shared] isScanning]));
}

RCT_EXPORT_METHOD(writeNdef
                  : (NSDictionary *)message
                  options
                  : (NSDictionary *)options
                  resolve
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (RCTPromiseRejectBlock)reject)
{
    if (![message isKindOfClass:NSDictionary.class]) {
        [self reject:reject withPayload:@{
            @"code": @"INVALID_OPTIONS",
            @"message": @"message must be an object",
            @"recoverable": @YES
        }];
        return;
    }
    if (options != nil && ![options isKindOfClass:NSDictionary.class]) {
        [self reject:reject withPayload:@{
            @"code": @"INVALID_OPTIONS",
            @"message": @"options must be an object",
            @"recoverable": @YES
        }];
        return;
    }

    [[SfioraBridgeCoordinator shared]
        writeNdefWithMessage:message
        options:options
        success:^(NSDictionary *result) {
            resolve(result);
        }
        failure:^(NSDictionary *error) {
            [self reject:reject withPayload:error];
        }];
}

RCT_EXPORT_METHOD(initializeNdef
                  : (NSDictionary *)message
                  marker
                  : (NSDictionary *)marker
                  options
                  : (NSDictionary *)options
                  resolve
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (RCTPromiseRejectBlock)reject)
{
    if (![message isKindOfClass:NSDictionary.class] ||
        ![marker isKindOfClass:NSDictionary.class]) {
        [self reject:reject withPayload:@{
            @"code": @"INVALID_OPTIONS",
            @"message": @"message and marker must be objects",
            @"recoverable": @YES
        }];
        return;
    }
    if (options != nil && ![options isKindOfClass:NSDictionary.class]) {
        [self reject:reject withPayload:@{
            @"code": @"INVALID_OPTIONS",
            @"message": @"options must be an object",
            @"recoverable": @YES
        }];
        return;
    }

    [[SfioraBridgeCoordinator shared]
        initializeNdefWithMessage:message
        marker:marker
        options:options
        success:^(NSDictionary *result) {
            resolve(result);
        }
        failure:^(NSDictionary *error) {
            [self reject:reject withPayload:error];
        }];
}

RCT_EXPORT_METHOD(cancelWrite
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (__unused RCTPromiseRejectBlock)reject)
{
    [[SfioraBridgeCoordinator shared] cancelWrite];
    resolve(nil);
}

RCT_EXPORT_METHOD(isWriting
                  : (RCTPromiseResolveBlock)resolve
                  reject
                  : (__unused RCTPromiseRejectBlock)reject)
{
    resolve(@([[SfioraBridgeCoordinator shared] isWriting]));
}

- (void)invalidate
{
    [[SfioraBridgeCoordinator shared] cancelScan];
    [[SfioraBridgeCoordinator shared] cancelWrite];
}

- (void)reject:(RCTPromiseRejectBlock)reject
   withPayload:(NSDictionary *)payload
{
    NSString *code = [payload[@"code"] isKindOfClass:NSString.class]
        ? payload[@"code"]
        : @"INTERNAL_ERROR";
    NSString *message = [payload[@"message"] isKindOfClass:NSString.class]
        ? payload[@"message"]
        : @"The NFC operation failed";
    NSMutableDictionary *userInfo = [payload mutableCopy]
        ?: [NSMutableDictionary dictionary];
    userInfo[NSLocalizedDescriptionKey] = message;
    NSError *error = [NSError
        errorWithDomain:@"io.github.sandroxy.sfiora"
        code:1
        userInfo:userInfo];
    reject(code, message, error);
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeSfioraSpecJSI>(params);
}
#endif

@end
