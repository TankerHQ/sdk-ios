
#import <Foundation/Foundation.h>

#import <stdint.h>

// contains a NSUInteger constructed from a uintptr_t, and the size of the buffer
@interface PtrAndSizePair : NSObject

@property NSUInteger ptrValue;
@property NSUInteger ptrSize;

@end

NSNumber* ptrToNumber(void* ptr);
void* numberToPtr(NSNumber* nb);
NSError* getOptionalFutureError(void* future);
void* resolvePromise(void* future, void* arg);
void* unwrapAndFreeExpected(void* expected);
char* copyUTF8CString(NSString* str);
NSData* convertStringToData(NSString* clearText);
char** convertStringstoCStrings(NSArray<NSString*>* strings);
