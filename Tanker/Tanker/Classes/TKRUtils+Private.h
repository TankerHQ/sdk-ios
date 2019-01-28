
#import <Foundation/Foundation.h>

#import <stdint.h>

#import "TKRError.h"

// contains a NSUInteger constructed from a uintptr_t, and the size of the buffer
@interface PtrAndSizePair : NSObject

@property NSUInteger ptrValue;
@property NSUInteger ptrSize;

@end

// Internal block used to wrap C futures
typedef void (^TKRAdapter)(NSNumber* ptrValue, NSError* err);

void freeCStringArray(char** toFree, NSUInteger nbElems);
NSError* createNSError(char const* message, TKRError code);
NSNumber* ptrToNumber(void* ptr);
void* numberToPtr(NSNumber* nb);
NSError* getOptionalFutureError(void* future);
void* resolvePromise(void* future, void* arg);
void* unwrapAndFreeExpected(void* expected);
char* copyUTF8CString(NSString* str, NSError* _Nullable* _Nonnull err);
NSData* convertStringToData(NSString* clearText, NSError* _Nullable* _Nonnull err);
char** convertStringstoCStrings(NSArray<NSString*>* strings, NSError* _Nullable* _Nonnull err);
