#import "ControlledCoreNFC.h"

@implementation SFControlledSession {
    dispatch_queue_t _testQueue;
    NSString *_testAlert;
    NSUInteger _invalidations;
}
- (instancetype)initWithQueue:(dispatch_queue_t)queue {
    // Deliberately bypass the hardware-backed base initializer. Every OS method
    // used in these tests is overridden; this object never opens a real session.
    _testQueue = queue;
    return self;
}
- (NSString *)alertMessage { return _testAlert ?: @""; }
- (void)setAlertMessage:(NSString *)message { _testAlert = [message copy]; }
- (NSUInteger)invalidations { return _invalidations; }
- (void)beginSession {
    dispatch_async(_testQueue, ^{ if (self.onActive) self.onActive(); });
}
- (void)invalidateSession { _invalidations++; }
- (void)invalidateSessionWithErrorMessage:(NSString *)message { [self invalidateSession]; }
- (void)restartPolling { }
- (void)connectToTag:(id<NFCTag>)tag completionHandler:(void (^)(NSError *))completion {
    dispatch_async(_testQueue, ^{ completion(nil); });
}
- (void)completeInvalidation {
    dispatch_async(_testQueue, ^{
        if (self.onInvalidated) self.onInvalidated();
    });
}
@end

@implementation SFControlledTag {
    void (^_query)(NFCNDEFStatus, NSUInteger, NSError *);
    void (^_read)(NFCNDEFMessage *, NSError *);
    NSUInteger _queryCount, _readCount;
}
- (NSUInteger)queryCount { return _queryCount; }
- (NSUInteger)readCount { return _readCount; }
- (NFCTagType)type { return NFCTagTypeMiFare; }
- (id<NFCReaderSession>)session { return nil; }
- (BOOL)isAvailable { return YES; }
- (id<NFCMiFareTag>)asNFCMiFareTag { return self; }
- (id<NFCISO7816Tag>)asNFCISO7816Tag { return nil; }
- (id<NFCISO15693Tag>)asNFCISO15693Tag { return nil; }
- (id<NFCFeliCaTag>)asNFCFeliCaTag { return nil; }
- (NFCMiFareFamily)mifareFamily { return NFCMiFareUltralight; }
- (NSData *)identifier { return [NSData dataWithBytes:"\x01\x02\x03\x04" length:4]; }
- (NSData *)historicalBytes { return nil; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (void)queryNDEFStatusWithCompletionHandler:(void (^)(NFCNDEFStatus, NSUInteger, NSError *))completion {
    _queryCount++; _query = [completion copy];
}
- (void)readNDEFWithCompletionHandler:(void (^)(NFCNDEFMessage *, NSError *))completion {
    _readCount++; _read = [completion copy];
}
- (void)completeQueryWithError:(NSError *)error {
    NSAssert(_query != nil, @"The production client has not queried this tag");
    void (^callback)(NFCNDEFStatus, NSUInteger, NSError *) = _query;
    _query = nil;
    dispatch_async(dispatch_get_main_queue(), ^{ callback(NFCNDEFStatusReadWrite, 1024, error); });
}
- (void)completeReadWithText:(NSString *)text error:(NSError *)error {
    NSAssert(_read != nil, @"The production client has not read this tag");
    void (^callback)(NFCNDEFMessage *, NSError *) = _read;
    _read = nil;
    NFCNDEFPayload *payload = [NFCNDEFPayload wellKnownTypeTextPayloadWithString:text locale:[NSLocale localeWithLocaleIdentifier:@"en"]];
    NFCNDEFMessage *message = [[NFCNDEFMessage alloc] initWithNDEFRecords:@[payload]];
    dispatch_async(dispatch_get_main_queue(), ^{ callback(error ? nil : message, error); });
}
- (void)writeNDEF:(NFCNDEFMessage *)message completionHandler:(void (^)(NSError *))completion { NSAssert(NO, @"Unexpected write"); }
- (void)writeLockWithCompletionHandler:(void (^)(NSError *))completion { NSAssert(NO, @"Unexpected lock"); }
- (void)sendMiFareCommand:(NSData *)command completionHandler:(void (^)(NSData *, NSError *))completion { NSAssert(NO, @"Unexpected memory probe"); }
- (void)sendMiFareISO7816Command:(NFCISO7816APDU *)command completionHandler:(void (^)(NSData *, uint8_t, uint8_t, NSError *))completion { NSAssert(NO, @"Unexpected APDU"); }
@end
