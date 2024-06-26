
#import <Foundation/Foundation.h>

#import <stdint.h>

// https://stackoverflow.com/a/15707096/4116453
#define TKRAntiARCRetain(value)                            \
  void* retained_##value = (__bridge_retained void*)value; \
  (void)retained_##value

#define TKRAntiARCRelease(value)                                  \
  void* retained_##value = (__bridge void*)value;                 \
  id unretained_##value = (__bridge_transfer id)retained_##value; \
  unretained_##value = nil

// contains a NSUInteger constructed from a uintptr_t, and the size of the buffer
@interface TKRPtrAndSizePair : NSObject

@property NSUInteger ptrValue;
@property NSUInteger ptrSize;

@end

// Internal block used to wrap C futures
NS_SWIFT_NAME(Adapter)
typedef void (^TKRAdapter)(NSNumber* _Nullable ptrValue, NSError* _Nullable err);

void TKR_runOnMainQueue(void (^_Nonnull block)(void));
void TKR_freeCStringArray(char* _Nonnull* _Nonnull toFree, NSUInteger nbElems);
NSError* _Nonnull TKR_createNSError(NSUInteger code, NSString* _Nonnull message);
NSError* _Nonnull TKR_createNSErrorWithDomain(NSString* _Nonnull domain, NSUInteger code, NSString* _Nonnull message);
NSNumber* _Nonnull TKR_ptrToNumber(void* _Nonnull ptr);
void* _Nonnull TKR_numberToPtr(NSNumber* _Nonnull nb);
NSError* _Nullable TKR_getOptionalFutureError(void* _Nonnull future);
void* _Nullable TKR_resolvePromise(void* _Nonnull future, void* _Nullable arg);
void* _Nullable TKR_unwrapAndFreeExpected(void* _Nonnull expected, NSError* _Nullable* _Nonnull err);
char* _Nullable TKR_copyUTF8CString(NSString* _Nonnull str, NSError* _Nullable* _Nonnull err);
NSData* _Nullable TKR_convertStringToData(NSString* _Nonnull clearText, NSError* _Nullable* _Nonnull err);
char* _Nonnull* _Nullable TKR_convertStringstoCStrings(NSArray<NSString*>* _Nonnull strings,
                                                       NSError* _Nullable* _Nonnull err);
