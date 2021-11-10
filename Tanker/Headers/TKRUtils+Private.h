
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
typedef void (^TKRAdapter)(NSNumber* _Nullable ptrValue, NSError* _Nullable err);

void runOnMainQueue(void (^_Nonnull block)(void));
void freeCStringArray(char* _Nonnull* _Nonnull toFree, NSUInteger nbElems);
NSError* _Nonnull createNSError(NSString* _Nonnull domain, NSString* _Nonnull message, NSUInteger code);
NSNumber* _Nonnull ptrToNumber(void* _Nonnull ptr);
void* _Nonnull numberToPtr(NSNumber* _Nonnull nb);
NSError* _Nullable getOptionalFutureError(void* _Nonnull future);
void* _Nullable resolvePromise(void* _Nonnull future, void* _Nullable arg);
void* _Nonnull unwrapAndFreeExpected(void* _Nonnull expected);
char* _Nullable copyUTF8CString(NSString* _Nonnull str, NSError* _Nullable* _Nonnull err);
NSData* _Nullable convertStringToData(NSString* _Nonnull clearText, NSError* _Nullable* _Nonnull err);
char* _Nonnull* _Nullable convertStringstoCStrings(NSArray<NSString*>* _Nonnull strings,
                                                   NSError* _Nullable* _Nonnull err);
