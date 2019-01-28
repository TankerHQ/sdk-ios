#import <Foundation/Foundation.h>

#import "TKRTanker.h"
#import "TKRUtils+Private.h"

#include <tanker/tanker.h>

@implementation PtrAndSizePair

@synthesize ptrValue;
@synthesize ptrSize;

@end

NSError* createNSError(char const* message, TKRError code)
{
  return [NSError
      errorWithDomain:TKRErrorDomain
                 code:code
             userInfo:@{
               NSLocalizedDescriptionKey : [NSString stringWithCString:message encoding:NSUTF8StringEncoding]
             }];
}

NSNumber* ptrToNumber(void* ptr)
{
  return [NSNumber numberWithUnsignedLong:(uintptr_t)ptr];
}

void* numberToPtr(NSNumber* nb)
{
  return (void*)((uintptr_t)nb.unsignedLongValue);
}

// returns nil if no error
NSError* getOptionalFutureError(void* future)
{
  tanker_future_t* fut = (tanker_future_t*)future;
  tanker_error_t* err = tanker_future_get_error(fut);
  if (!err)
    return nil;
  NSError* error = [NSError
      errorWithDomain:TKRErrorDomain
                 code:err->code
             userInfo:@{
               NSLocalizedDescriptionKey : [NSString stringWithCString:err->message encoding:NSUTF8StringEncoding]
             }];
  return error;
}

// To understand the __bridge_madness: https://stackoverflow.com/a/14782488/4116453
// and https://stackoverflow.com/a/14207961/4116453
void* resolvePromise(void* future, void* arg)
{
  NSError* optErr = getOptionalFutureError(future);
  NSNumber* ptrValue = nil;

  if (!optErr)
  {
    void* ptr = tanker_future_get_voidptr((tanker_future_t*)future);
    // uintptr_t is an optional type, but has been in the macOS SDK since 10.0 (2001).
    // It doesn't look safe, but it is. As long as the uintptr_t value is left untouched.
    // https://developer.apple.com/library/content/documentation/General/Conceptual/CocoaTouch64BitGuide/ConvertingYourAppto64-Bit/ConvertingYourAppto64-Bit.html
    ptrValue = [NSNumber numberWithUnsignedLongLong:(uintptr_t)ptr];
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    TKRAdapter resolve = (__bridge_transfer typeof(TKRAdapter))arg;
    resolve(ptrValue, optErr);
  });
  return nil;
}

void freeCStringArray(char** toFree, NSUInteger nbElems)
{
  for (int i = 0; i < nbElems; ++i)
    free(toFree[i]);
  free(toFree);
}

void* unwrapAndFreeExpected(void* expected)
{
  NSError* optErr = getOptionalFutureError(expected);
  if (optErr)
  {
    tanker_future_destroy((tanker_future_t*)expected);
    @throw optErr;
  }

  void* ptr = tanker_future_get_voidptr((tanker_future_t*)expected);
  tanker_future_destroy((tanker_future_t*)expected);

  return ptr;
}

char* copyUTF8CString(NSString* str, NSError* _Nullable* _Nonnull err)
{
  size_t const length = strlen(str.UTF8String);
  char* utf8_cstr = (char*)malloc(length + 1);
  if (!utf8_cstr)
  {
    *err = createNSError("could not allocate UTF-8 C string buffer", TKRErrorOther);
    return nil;
  }
  memcpy(utf8_cstr, str.UTF8String, length);
  utf8_cstr[length] = '\0';
  err = nil;
  return utf8_cstr;
}

NSData* convertStringToData(NSString* clearText, NSError* _Nullable* _Nonnull err)
{
  char* clear_text = copyUTF8CString(clearText, err);
  if (*err)
    return nil;
  return [NSData dataWithBytesNoCopy:clear_text length:strlen(clear_text) freeWhenDone:YES];
}

char** convertStringstoCStrings(NSArray<NSString*>* strings, NSError* _Nullable* _Nonnull err)
{
  if (!strings || strings.count == 0)
    return nil;
  unsigned long const size_to_allocate = strings.count * sizeof(char*);
  __block char** c_strs = (char**)malloc(size_to_allocate);
  if (!c_strs)
  {
    *err = createNSError("could not allocate array of UTF-8 C strings", TKRErrorOther);
    return nil;
  }

  __block NSError* err2 = nil;
  [strings enumerateObjectsUsingBlock:^(NSString* str, NSUInteger idx, BOOL* stop) {
    c_strs[idx] = copyUTF8CString(str, &err2);
    if (err2)
    {
      for (; idx != 0; --idx)
        free(c_strs[idx]);
      *stop = YES;
      free(c_strs);
      c_strs = nil;
    }
  }];
  *err = err2;
  return c_strs;
}
