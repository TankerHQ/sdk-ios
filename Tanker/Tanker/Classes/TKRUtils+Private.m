#import <Foundation/Foundation.h>

#import "TKRTanker.h"
#import "TKRUtils+Private.h"

#include <tanker/tanker.h>

@implementation PtrAndSizePair

@synthesize ptrValue;
@synthesize ptrSize;

@end

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
  TKRAdapter resolve = (__bridge_transfer typeof(TKRAdapter))arg;

  NSError* optErr = getOptionalFutureError(future);
  if (optErr)
    resolve(nil, optErr);
  else
  {
    void* ptr = tanker_future_get_voidptr((tanker_future_t*)future);
    // uintptr_t is an optional type, but has been in the macOS SDK since 10.0 (2001).
    // It doesn't look safe, but it is. As long as the uintptr_t value is left untouched.
    // https://developer.apple.com/library/content/documentation/General/Conceptual/CocoaTouch64BitGuide/ConvertingYourAppto64-Bit/ConvertingYourAppto64-Bit.html
    NSNumber* ptrValue = [NSNumber numberWithUnsignedLongLong:(uintptr_t)ptr];
    resolve(ptrValue, nil);
  }
  return nil;
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

char* copyUTF8CString(NSString* str)
{
  size_t const length = strlen(str.UTF8String);
  char* utf8_cstr = (char*)malloc(length + 1);
  if (!utf8_cstr)
  {
    [NSException raise:NSMallocException format:@"could not allocate %lu bytes", length];
  }
  memcpy(utf8_cstr, str.UTF8String, length);
  utf8_cstr[length] = '\0';
  return utf8_cstr;
}

NSData* convertStringToData(NSString* clearText)
{
  char* clear_text = copyUTF8CString(clearText);
  return [NSData dataWithBytesNoCopy:clear_text length:strlen(clear_text) freeWhenDone:YES];
}

char** convertStringstoCStrings(NSArray<NSString*>* strings)
{
  if (!strings || strings.count == 0)
    return nil;
  unsigned long const size_to_allocate = strings.count * sizeof(char*);
  __block char** c_strs = (char**)malloc(size_to_allocate);
  if (!c_strs)
  {
    [NSException raise:NSMallocException format:@"could not allocate %lu bytes", size_to_allocate];
  }

  [strings enumerateObjectsUsingBlock:^(NSString* str, NSUInteger idx, BOOL* stop) {
    @try
    {
      c_strs[idx] = copyUTF8CString(str);
    }
    @catch (NSException* e)
    {
      for (; idx != 0; --idx)
        free(c_strs[idx]);
      [e raise];
    }
  }];
  return c_strs;
}
