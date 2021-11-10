#import <Foundation/Foundation.h>

#import <Tanker/TKRUtils+Private.h>

#include "ctanker.h"

@implementation TKRPtrAndSizePair

@synthesize ptrValue;
@synthesize ptrSize;

@end

NSError* TKR_createNSError(NSString* _Nonnull domain, NSString* _Nonnull message, NSUInteger code)
{
  return [NSError errorWithDomain:domain code:code userInfo:@{NSLocalizedDescriptionKey : message}];
}

NSNumber* TKR_ptrToNumber(void* ptr)
{
  return [NSNumber numberWithUnsignedLong:(uintptr_t)ptr];
}

void* TKR_numberToPtr(NSNumber* nb)
{
  return (void*)((uintptr_t)nb.unsignedLongValue);
}

// returns nil if no error
NSError* TKR_getOptionalFutureError(void* future)
{
  tanker_future_t* fut = (tanker_future_t*)future;
  tanker_error_t* err = tanker_future_get_error(fut);
  if (!err)
    return nil;
  return TKR_createNSError(
      @"TKRErrorDomain", [NSString stringWithCString:err->message encoding:NSUTF8StringEncoding], err -> code);
}

void TKR_runOnMainQueue(void (^block)(void))
{
  dispatch_async(dispatch_get_main_queue(), ^{
    block();
  });
}

// To understand the __bridge_madness: https://stackoverflow.com/a/14782488/4116453
// and https://stackoverflow.com/a/14207961/4116453
void* TKR_resolvePromise(void* future, void* arg)
{
  NSError* optErr = TKR_getOptionalFutureError(future);
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

void TKR_freeCStringArray(char** toFree, NSUInteger nbElems)
{
  for (int i = 0; i < nbElems; ++i)
    free(toFree[i]);
  free(toFree);
}

void* TKR_unwrapAndFreeExpected(void* expected)
{
  NSError* optErr = TKR_getOptionalFutureError(expected);
  if (optErr)
  {
    tanker_future_destroy((tanker_future_t*)expected);
    @throw optErr;
  }

  void* ptr = tanker_future_get_voidptr((tanker_future_t*)expected);
  tanker_future_destroy((tanker_future_t*)expected);

  return ptr;
}

char* TKR_copyUTF8CString(NSString* str, NSError* _Nullable* _Nonnull err)
{
  size_t const length = strlen(str.UTF8String);
  char* utf8_cstr = (char*)malloc(length + 1);
  if (!utf8_cstr)
  {
    *err = [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:ENOMEM
                           userInfo:@{NSLocalizedDescriptionKey : @"could not allocate UTF-8 C string buffer"}];
    return nil;
  }
  memcpy(utf8_cstr, str.UTF8String, length);
  utf8_cstr[length] = '\0';
  err = nil;
  return utf8_cstr;
}

NSData* TKR_convertStringToData(NSString* clearText, NSError* _Nullable* _Nonnull err)
{
  char* clear_text = TKR_copyUTF8CString(clearText, err);
  if (*err)
    return nil;
  return [NSData dataWithBytesNoCopy:clear_text length:strlen(clear_text) freeWhenDone:YES];
}

char** TKR_convertStringstoCStrings(NSArray<NSString*>* strings, NSError* _Nullable* _Nonnull err)
{
  if (!strings || strings.count == 0)
    return nil;
  unsigned long const size_to_allocate = strings.count * sizeof(char*);
  __block char** c_strs = (char**)malloc(size_to_allocate);
  if (!c_strs)
  {
    *err = [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:ENOMEM
                           userInfo:@{NSLocalizedDescriptionKey : @"could not allocate array UTF-8 C strings"}];
    return nil;
  }

  __block NSError* err2 = nil;
  [strings enumerateObjectsUsingBlock:^(NSString* str, NSUInteger idx, BOOL* stop) {
    c_strs[idx] = TKR_copyUTF8CString(str, &err2);
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
