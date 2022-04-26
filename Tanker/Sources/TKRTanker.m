#import <Foundation/Foundation.h>

#import <POSInputStreamLibrary/POSBlobInputStream.h>

#import <Tanker/Storage/TKRDatastoreBindings.h>
#import <Tanker/TKRAsyncStreamReader+Private.h>
#import <Tanker/TKRAttachResult+Private.h>
#import <Tanker/TKREncryptionSession+Private.h>
#import <Tanker/TKRError.h>
#import <Tanker/TKRInputStreamDataSource+Private.h>
#import <Tanker/TKRLogEntry.h>
#import <Tanker/TKRNetwork+Private.h>
#import <Tanker/TKRTanker+Private.h>
#import <Tanker/TKRTankerOptions.h>
#import <Tanker/TKRVerification+Private.h>
#import <Tanker/TKRVerificationKey+Private.h>
#import <Tanker/TKRVerificationMethod+Private.h>
#import <Tanker/Utils/TKRUtils.h>

#include <assert.h>
#include <string.h>

#include "ctanker.h"
#include "ctanker/stream.h"

NSString* const TKRErrorDomain = @"TKRErrorDomain";

#define TANKER_IOS_VERSION @"9999"

TKRLogHandler globalLogHandler = ^(TKRLogEntry* _Nonnull entry) {
  switch (entry.level)
  {
  case TKRLogLevelDebug:
    break;
  case TKRLogLevelInfo:
    break;
  case TKRLogLevelWarning:
    break;
  case TKRLogLevelError:
    NSLog(@"Tanker Error: [%@] %@", entry.category, entry.message);
    break;
  default:
    NSLog(@"Unknown Tanker log level: %c: [%@] %@", (int)entry.level, entry.category, entry.message);
  }
};

static void verificationToCVerification(TKRVerification* _Nonnull verification, tanker_verification_t* c_verification)
{
  c_verification->verification_method_type = verification.type;
  switch (verification.type)
  {
  case TKRVerificationMethodTypeEmail:
    c_verification->email_verification.email = [verification.email.email cStringUsingEncoding:NSUTF8StringEncoding];
    c_verification->email_verification.verification_code =
        [verification.email.verificationCode cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePassphrase:
    c_verification->passphrase = [verification.passphrase cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypeVerificationKey:
    c_verification->verification_key = [verification.verificationKey.value cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypeOIDCIDToken:
    c_verification->oidc_id_token = [verification.oidcIDToken cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePhoneNumber:
    c_verification->phone_number_verification.phone_number =
        [verification.phoneNumber.phoneNumber cStringUsingEncoding:NSUTF8StringEncoding];
    c_verification->phone_number_verification.verification_code =
        [verification.phoneNumber.verificationCode cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePreverifiedEmail:
    c_verification->preverified_email = [verification.preverifiedEmail cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePreverifiedPhoneNumber:
    c_verification->preverified_phone_number =
        [verification.preverifiedPhoneNumber cStringUsingEncoding:NSUTF8StringEncoding];
    break;
  default:
    NSLog(@"Unreachable code: unknown verification method type: %lu", (unsigned long)verification.type);
    assert(false);
  }
}

static TKRVerificationMethod* _Nonnull cVerificationMethodToVerificationMethod(
    tanker_verification_method_t* c_verification)
{
  TKRVerificationMethod* ret = [[TKRVerificationMethod alloc] init];

  ret.type = c_verification->verification_method_type;
  switch (ret.type)
  {
  case TKRVerificationMethodTypeEmail:
    ret.email = [NSString stringWithCString:c_verification->value encoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePhoneNumber:
    ret.phoneNumber = [NSString stringWithCString:c_verification->value encoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePreverifiedEmail:
    ret.preverifiedEmail = [NSString stringWithCString:c_verification->value encoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePreverifiedPhoneNumber:
    ret.preverifiedPhoneNumber = [NSString stringWithCString:c_verification->value encoding:NSUTF8StringEncoding];
    break;
  case TKRVerificationMethodTypePassphrase:
  case TKRVerificationMethodTypeVerificationKey:
  case TKRVerificationMethodTypeOIDCIDToken:
    break;
  default:
    NSLog(@"Unreachable code: unknown verification method type: %lu", (unsigned long)ret.type);
    assert(false);
  }
  return ret;
}

static void dispatchInBackground(id block)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

static void defaultLogHandler(tanker_log_record_t const* record)
{
  TKRLogEntry* entry = [[TKRLogEntry alloc] init];
  entry.category = [NSString stringWithCString:record->category encoding:NSUTF8StringEncoding];
  entry.file = [NSString stringWithCString:record->file encoding:NSUTF8StringEncoding];
  entry.message = [NSString stringWithCString:record->message encoding:NSUTF8StringEncoding];
  entry.level = (TKRLogLevel)record->level;
  entry.line = record->line;
  globalLogHandler(entry);
}

static void convertOptions(TKRTankerOptions const* options, tanker_options_t* cOptions)
{
  cOptions->app_id = [options.appID cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->persistent_path = [options.persistentPath cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->cache_path = [options.cachePath cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->url = [options.url cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->sdk_type = [options.sdkType cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->sdk_version = [TANKER_IOS_VERSION cStringUsingEncoding:NSUTF8StringEncoding];
}

@interface TKRTanker ()

// Redeclare them as readwrite to set them.
@property(nonnull, readwrite) TKRTankerOptions* options;

@end

@implementation TKRTanker

@synthesize options = _options;

// MARK: Class methods

// Note: this constructor blocks until tanker_create resolves.
// If we start doing background operation in tanker_create, we should
// get rid of the tanker_future_wait()
+ (nonnull TKRTanker*)tankerWithOptions:(nonnull TKRTankerOptions*)options
{
  __block TKRTanker* tanker = [[[self class] alloc] init];
  tanker_set_log_handler(&defaultLogHandler);
  tanker.options = options;

  tanker_options_t cOptions = TANKER_OPTIONS_INIT;
  convertOptions(options, &cOptions);
  cOptions.http_options.send_request = httpSendRequestCallback;
  cOptions.http_options.cancel_request = httpCancelRequestCallback;
  cOptions.datastore_options.open = TKR_datastore_open;
  cOptions.datastore_options.close = TKR_datastore_close;
  cOptions.datastore_options.nuke = TKR_datastore_nuke;
  cOptions.datastore_options.put_serialized_device = TKR_datastore_put_serialized_device;
  cOptions.datastore_options.find_serialized_device = TKR_datastore_find_serialized_device;
  cOptions.datastore_options.put_cache_values = TKR_datastore_put_cache_values;
  cOptions.datastore_options.find_cache_values = TKR_datastore_find_cache_values;

  tanker_future_t* create_future = tanker_create(&cOptions);
  tanker_future_wait(create_future);
  NSError* error = TKR_getOptionalFutureError(create_future);
  if (error)
  {
    tanker_future_destroy(create_future);
    [NSException raise:NSInvalidArgumentException format:@"Could not init Tanker %@", [error localizedDescription]];
  }
  tanker.cTanker = tanker_future_get_voidptr(create_future);
  tanker_future_destroy(create_future);
  return tanker;
}

+ (nonnull NSString*)versionString
{
  return TANKER_IOS_VERSION;
}

+ (nonnull NSString*)nativeVersionString
{
  return [NSString stringWithCString:tanker_version_string() encoding:NSUTF8StringEncoding];
}

+ (nonnull NSString*)prehashPassword:(nonnull NSString*)password
{
  if (!password.length)
    [NSException raise:NSInvalidArgumentException format:@"cannot hash empty password"];

  char const* c_password = [password cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* expected_chashed = tanker_prehash_password(c_password);
  char* c_hashed = (char*)TKR_unwrapAndFreeExpected(expected_chashed);
  NSString* hashed = [NSString stringWithCString:c_hashed encoding:NSUTF8StringEncoding];
  return hashed;
}

+ (void)connectLogHandler:(nonnull TKRLogHandler)handler
{
  globalLogHandler = handler;
}

// MARK: Instance methods

- (void)startWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRStartHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* status, NSError* err) {
    if (err)
      handler(0, err);
    else
      handler(status.unsignedIntegerValue, nil);
  };
  char const* c_identity = [identity cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* start_future = tanker_start((tanker_t*)self.cTanker, c_identity);
  tanker_future_t* resolve_future =
      tanker_future_then(start_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(start_future);
  tanker_future_destroy(resolve_future);
}

- (void)registerIdentityWithVerification:(nonnull TKRVerification*)verification
                       completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRIdentityVerificationHandler thunk = ^(NSString* _token, NSError* err) {
    handler(err);
  };

  [self registerIdentityWithVerification:verification options:[TKRVerificationOptions options] completionHandler:thunk];
}

- (void)registerIdentityWithVerification:(nonnull TKRVerification*)verification
                                 options:(nonnull TKRVerificationOptions*)options
                       completionHandler:(nonnull TKRIdentityVerificationHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* maybeTokenPtr, NSError* err) {
    char* session_token = (char*)TKR_numberToPtr(maybeTokenPtr);
    if (err || !session_token)
      handler(nil, err);
    else
    {
      NSString* ret = [NSString stringWithCString:session_token encoding:NSUTF8StringEncoding];
      tanker_free_buffer(session_token);
      handler(ret, nil);
    }
  };
  tanker_verification_t c_verification = TANKER_VERIFICATION_INIT;

  tanker_verification_options_t coptions = TANKER_VERIFICATION_OPTIONS_INIT;
  coptions.with_session_token = options.withSessionToken;

  verificationToCVerification(verification, &c_verification);
  tanker_future_t* register_future = tanker_register_identity((tanker_t*)self.cTanker, &c_verification, &coptions);
  tanker_future_t* resolve_future =
      tanker_future_then(register_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(register_future);
  tanker_future_destroy(resolve_future);
}

- (void)verificationMethodsWithCompletionHandler:(nonnull TKRVerificationMethodsHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
      handler(nil, err);
    else
    {
      NSMutableArray<TKRVerificationMethod*>* ret = [NSMutableArray array];

      tanker_verification_method_list_t* methods = TKR_numberToPtr(ptrValue);
      for (NSUInteger i = 0; i < methods->count; ++i)
        [ret addObject:cVerificationMethodToVerificationMethod(methods->methods + i)];
      tanker_free_verification_method_list(methods);
      handler(ret, nil);
    }
  };

  tanker_future_t* methods_future = tanker_get_verification_methods((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(methods_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(methods_future);
  tanker_future_destroy(resolve_future);
}

- (void)setVerificationMethod:(nonnull TKRVerification*)verification completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRIdentityVerificationHandler thunk = ^(NSString* _token, NSError* err) {
    handler(err);
  };

  [self setVerificationMethod:verification options:[TKRVerificationOptions options] completionHandler:thunk];
}

- (void)setVerificationMethod:(nonnull TKRVerification*)verification
                      options:(nonnull TKRVerificationOptions*)options
            completionHandler:(nonnull TKRIdentityVerificationHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* maybeTokenPtr, NSError* err) {
    char* session_token = (char*)TKR_numberToPtr(maybeTokenPtr);
    if (err || !session_token)
      handler(nil, err);
    else
    {
      NSString* ret = [NSString stringWithCString:session_token encoding:NSUTF8StringEncoding];
      tanker_free_buffer(session_token);
      handler(ret, nil);
    }
  };
  tanker_verification_t c_verification = TANKER_VERIFICATION_INIT;
  verificationToCVerification(verification, &c_verification);

  tanker_verification_options_t coptions = TANKER_VERIFICATION_OPTIONS_INIT;
  coptions.with_session_token = options.withSessionToken;

  tanker_future_t* set_future = tanker_set_verification_method((tanker_t*)self.cTanker, &c_verification, &coptions);
  tanker_future_t* resolve_future =
      tanker_future_then(set_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(set_future);
  tanker_future_destroy(resolve_future);
}

- (void)verifyIdentityWithVerification:(nonnull TKRVerification*)verification
                     completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRIdentityVerificationHandler thunk = ^(NSString* _token, NSError* err) {
    handler(err);
  };

  [self verifyIdentityWithVerification:verification options:[TKRVerificationOptions options] completionHandler:thunk];
}

- (void)verifyIdentityWithVerification:(nonnull TKRVerification*)verification
                               options:(nonnull TKRVerificationOptions*)options
                     completionHandler:(nonnull TKRIdentityVerificationHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* maybeTokenPtr, NSError* err) {
    char* session_token = (char*)TKR_numberToPtr(maybeTokenPtr);
    if (err || !session_token)
      handler(nil, err);
    else
    {
      NSString* ret = [NSString stringWithCString:session_token encoding:NSUTF8StringEncoding];
      tanker_free_buffer(session_token);
      handler(ret, nil);
    }
  };
  tanker_verification_t c_verification = TANKER_VERIFICATION_INIT;
  verificationToCVerification(verification, &c_verification);

  tanker_verification_options_t coptions = TANKER_VERIFICATION_OPTIONS_INIT;
  coptions.with_session_token = options.withSessionToken;

  tanker_future_t* verify_future = tanker_verify_identity((tanker_t*)self.cTanker, &c_verification, &coptions);
  tanker_future_t* resolve_future =
      tanker_future_then(verify_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(verify_future);
  tanker_future_destroy(resolve_future);
}

- (void)attachProvisionalIdentity:(nonnull NSString*)provisionalIdentity
                completionHandler:(nonnull TKRAttachResultHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
      handler(nil, err);
    else
    {
      tanker_attach_result_t* c_result = TKR_numberToPtr(ptrValue);
      TKRAttachResult* ret = [[TKRAttachResult alloc] init];
      ret.status = c_result->status;
      if (ret.status == TKRStatusIdentityVerificationNeeded)
        ret.method = cVerificationMethodToVerificationMethod(c_result->method);
      else
        ret.method = nil;
      handler(ret, nil);
    }
  };

  char const* c_provisional_identity = [provisionalIdentity cStringUsingEncoding:NSUTF8StringEncoding];

  tanker_future_t* attach_future = tanker_attach_provisional_identity((tanker_t*)self.cTanker, c_provisional_identity);
  tanker_future_t* resolve_future =
      tanker_future_then(attach_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(attach_future);
  tanker_future_destroy(resolve_future);
}

- (void)verifyProvisionalIdentityWithVerification:(TKRVerification*)verification
                                completionHandler:(TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  tanker_verification_t c_verification = TANKER_VERIFICATION_INIT;
  verificationToCVerification(verification, &c_verification);

  tanker_future_t* verify_future = tanker_verify_provisional_identity((tanker_t*)self.cTanker, &c_verification);
  tanker_future_t* resolve_future =
      tanker_future_then(verify_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(verify_future);
  tanker_future_destroy(resolve_future);
}

- (void)deviceIDWithCompletionHandler:(nonnull TKRDeviceIDHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    char* device_id = (char*)TKR_numberToPtr(ptrValue);
    NSString* ret = [NSString stringWithCString:device_id encoding:NSUTF8StringEncoding];
    tanker_free_buffer(device_id);
    handler(ret, nil);
  };
  tanker_future_t* device_id_future = tanker_device_id((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(device_id_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(device_id_future);
  tanker_future_destroy(resolve_future);
}

- (void)createOidcNonceWithCompletionHandler:(nonnull TKRNonceHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    char* nonce = (char*)TKR_numberToPtr(ptrValue);
    NSString* ret = [NSString stringWithCString:nonce encoding:NSUTF8StringEncoding];
    tanker_free_buffer(nonce);
    handler(ret, nil);
  }; 

  tanker_future_t* nonce_future = tanker_create_oidc_nonce((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(nonce_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(nonce_future);
  tanker_future_destroy(resolve_future);
}

- (void)setOidcTestNonce:(nonnull NSString*)nonce completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* c_nonce = [nonce cStringUsingEncoding:NSUTF8StringEncoding];

  tanker_future_t* fut = tanker_set_oidc_test_nonce((tanker_t*)self.cTanker, c_nonce);
  tanker_future_t* resolve_future =
      tanker_future_then(fut, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(fut);
  tanker_future_destroy(resolve_future);
}

- (void)encryptString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptString:clearText options:[TKREncryptionOptions options] completionHandler:handler];
}

- (void)encryptString:(nonnull NSString*)clearText
              options:(nonnull TKREncryptionOptions*)options
    completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  NSError* err = nil;
  NSData* data = TKR_convertStringToData(clearText, &err);

  if (err)
    TKR_runOnMainQueue(^{
      handler(nil, err);
    });
  else
    [self encryptData:data options:options completionHandler:handler];
}

- (void)decryptStringFromData:(nonnull NSData*)encryptedData
            completionHandler:(nonnull TKRDecryptedStringHandler)handler
{
  id adapter = ^(TKRPtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSString* ret = [[NSString alloc] initWithBytesNoCopy:decrypted_buffer
                                                   length:hack.ptrSize
                                                 encoding:NSUTF8StringEncoding
                                             freeWhenDone:YES];
    handler(ret, nil);
  };

  [self decryptDataImpl:encryptedData completionHandler:adapter];
}

- (void)encryptData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptData:clearData options:[TKREncryptionOptions options] completionHandler:handler];
}

- (void)encryptData:(nonnull NSData*)clearData
              options:(nonnull TKREncryptionOptions*)options
    completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  id adapter = ^(TKRPtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* encrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSData* ret = [NSData dataWithBytesNoCopy:encrypted_buffer length:hack.ptrSize freeWhenDone:YES];
    handler(ret, nil);
  };
  [self encryptDataImpl:clearData options:options completionHandler:adapter];
}

- (void)decryptData:(nonnull NSData*)encryptedData completionHandler:(nonnull TKRDecryptedDataHandler)handler
{
  id adapter = ^(TKRPtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSData* ret = [NSData dataWithBytesNoCopy:decrypted_buffer length:hack.ptrSize freeWhenDone:YES];
    handler(ret, nil);
  };
  [self decryptDataImpl:encryptedData completionHandler:adapter];
}

- (nullable NSString*)resourceIDOfEncryptedData:(nonnull NSData*)encryptedData error:(NSError* _Nullable* _Nonnull)error
{
  tanker_expected_t* resource_id_expected =
      tanker_get_resource_id((uint8_t const*)encryptedData.bytes, encryptedData.length);
  *error = TKR_getOptionalFutureError(resource_id_expected);
  if (*error)
  {
    tanker_future_destroy(resource_id_expected);
    return nil;
  }
  char* resource_id = TKR_unwrapAndFreeExpected(resource_id_expected);
  NSString* ret = [NSString stringWithCString:resource_id encoding:NSUTF8StringEncoding];
  tanker_free_buffer(resource_id);
  return ret;
}

- (void)createGroupWithIdentities:(nonnull NSArray<NSString*>*)identities
                completionHandler:(nonnull TKRGroupIDHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    char* group_id = (char*)TKR_numberToPtr(ptrValue);
    NSString* groupId = [NSString stringWithCString:group_id encoding:NSUTF8StringEncoding];
    tanker_free_buffer(group_id);
    handler(groupId, nil);
  };
  NSError* err = nil;
  char** c_identities = TKR_convertStringstoCStrings(identities, &err);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }
  tanker_future_t* future =
      tanker_create_group((tanker_t*)self.cTanker, (char const* const*)c_identities, identities.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  TKR_freeCStringArray(c_identities, identities.count);
}

- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                  usersToAdd:(nonnull NSArray<NSString*>*)usersToAdd
               usersToRemove:(nonnull NSArray<NSString*>*)usersToRemove
           completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* utf8_groupid = [groupId cStringUsingEncoding:NSUTF8StringEncoding];
  NSError* err = nil;
  char** identities_to_add = TKR_convertStringstoCStrings(usersToAdd, &err);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(err);
    });
    return;
  }
  char** identities_to_remove = TKR_convertStringstoCStrings(usersToRemove, &err);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(err);
    });
    TKR_freeCStringArray(identities_to_add, usersToAdd.count);
    return;
  }
  tanker_future_t* future = tanker_update_group_members((tanker_t*)self.cTanker,
                                                        utf8_groupid,
                                                        (char const* const*)identities_to_add,
                                                        usersToAdd.count,
                                                        (char const* const*)identities_to_remove,
                                                        usersToRemove.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  TKR_freeCStringArray(identities_to_add, usersToAdd.count);
  TKR_freeCStringArray(identities_to_remove, usersToRemove.count);
}

- (void)updateMembersOfGroup:(nonnull NSString*)groupId
                  usersToAdd:(nonnull NSArray<NSString*>*)userIdentities
           completionHandler:(nonnull TKRErrorHandler)handler
{
  [self updateMembersOfGroup:groupId usersToAdd:userIdentities usersToRemove:@[] completionHandler:handler];
}

- (void)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                 options:(nonnull TKRSharingOptions*)options
       completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  NSError* err = nil;
  char** resource_ids = TKR_convertStringstoCStrings(resourceIDs, &err);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(err);
    });
    return;
  }

  tanker_sharing_options_t sharing_options = TANKER_SHARING_OPTIONS_INIT;
  err = convertSharingOptions(options, &sharing_options);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(err);
    });
    return;
  }

  tanker_future_t* share_future =
      tanker_share((tanker_t*)self.cTanker, (char const* const*)resource_ids, resourceIDs.count, &sharing_options);

  tanker_future_t* resolve_future =
      tanker_future_then(share_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);

  tanker_future_destroy(share_future);
  tanker_future_destroy(resolve_future);

  TKR_freeCStringArray(resource_ids, resourceIDs.count);
  TKR_freeCStringArray((char**)sharing_options.share_with_users, sharing_options.nb_users);
  TKR_freeCStringArray((char**)sharing_options.share_with_groups, sharing_options.nb_groups);
}

- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler
{
  [self createEncryptionSessionWithCompletionHandler:handler encryptionOptions:[TKREncryptionOptions options]];
}

- (void)createEncryptionSessionWithCompletionHandler:(nonnull TKREncryptionSessionHandler)handler
                                   encryptionOptions:(nonnull TKREncryptionOptions*)encryptionOptions
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    TKREncryptionSession* encSess = [[TKREncryptionSession alloc] init];
    encSess.cSession = TKR_numberToPtr(ptrValue);
    handler(encSess, nil);
  };

  tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;
  NSError* err = convertEncryptionOptions(encryptionOptions, &encryption_options);
  if (err)
  {
    TKR_runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }

  tanker_future_t* sess_future = tanker_encryption_session_open((tanker_t*)self.cTanker, &encryption_options);

  tanker_future_t* resolve_future =
      tanker_future_then(sess_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);

  tanker_future_destroy(sess_future);
  tanker_future_destroy(resolve_future);

  TKR_freeCStringArray((char**)encryption_options.share_with_users, encryption_options.nb_users);
  TKR_freeCStringArray((char**)encryption_options.share_with_groups, encryption_options.nb_groups);
}

- (void)generateVerificationKeyWithCompletionHandler:(TKRVerificationKeyHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    char* verification_key = (char*)TKR_numberToPtr(ptrValue);
    NSString* verificationKey = [NSString stringWithCString:verification_key encoding:NSUTF8StringEncoding];

    TKRVerificationKey* ret = [TKRVerificationKey verificationKeyFromValue:verificationKey];
    tanker_free_buffer(verification_key);
    handler(ret, nil);
  };

  tanker_expected_t* verification_key_fut = tanker_generate_verification_key((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future = tanker_future_then(
      verification_key_fut, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);

  tanker_future_destroy(verification_key_fut);
  tanker_future_destroy(resolve_future);
}

- (void)stopWithCompletionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  tanker_future_t* stop_future = tanker_stop((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(stop_future, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(stop_future);
  tanker_future_destroy(resolve_future);
}

- (void)encryptStream:(nonnull NSInputStream*)clearStream completionHandler:(nonnull TKRInputStreamHandler)handler
{
  [self encryptStream:clearStream options:[TKREncryptionOptions options] completionHandler:handler];
}

- (void)encryptStream:(nonnull NSInputStream*)clearStream
              options:(nonnull TKREncryptionOptions*)opts
    completionHandler:(nonnull TKRInputStreamHandler)handler
{
  if (clearStream.streamStatus != NSStreamStatusNotOpen)
  {
    handler(nil,
            TKR_createNSError(
                TKRErrorDomain, @"Input stream status must be NSStreamStatusNotOpen", TKRErrorInvalidArgument));
    return;
  }

  TKRAsyncStreamReader* reader = [TKRAsyncStreamReader readerWithStream:clearStream];
  clearStream.delegate = reader;
  // The main run loop is the only run loop that runs automatically
  NSRunLoop* runLoop = [NSRunLoop mainRunLoop];
  [clearStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
  [clearStream open];

  tanker_encrypt_options_t encryption_options = TANKER_ENCRYPT_OPTIONS_INIT;
  NSError* err = convertEncryptionOptions(opts, &encryption_options);
  if (err)
  {
    handler(nil, err);
    return;
  }
  tanker_future_t* stream_fut = tanker_stream_encrypt((tanker_t*)self.cTanker,
                                                      (tanker_stream_input_source_t)&readInput,
                                                      (__bridge_retained void*)reader,
                                                      &encryption_options);
  completeStreamEncrypt(reader, stream_fut, handler);
  tanker_future_destroy(stream_fut);
  TKR_freeCStringArray((char**)encryption_options.share_with_users, encryption_options.nb_users);
  TKR_freeCStringArray((char**)encryption_options.share_with_groups, encryption_options.nb_groups);
}

- (void)decryptStream:(nonnull NSInputStream*)encryptedStream completionHandler:(nonnull TKRInputStreamHandler)handler
{
  if (encryptedStream.streamStatus != NSStreamStatusNotOpen)
  {
    handler(nil,
            TKR_createNSError(
                TKRErrorDomain, @"Input stream status must be NSStreamStatusNotOpen", TKRErrorInvalidArgument));
    return;
  }

  TKRAsyncStreamReader* reader = [TKRAsyncStreamReader readerWithStream:encryptedStream];
  encryptedStream.delegate = reader;
  NSRunLoop* runLoop = [NSRunLoop mainRunLoop];
  [encryptedStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
  [encryptedStream open];

  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    tanker_stream_t* stream = TKR_numberToPtr(ptrValue);
    TKRInputStreamDataSource* dataSource = [TKRInputStreamDataSource inputStreamDataSourceWithCStream:stream
                                                                                          asyncReader:reader];
    POSBlobInputStream* decryptionStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];
    handler(decryptionStream, nil);
  };

  tanker_future_t* create_fut = tanker_stream_decrypt(
      (tanker_t*)self.cTanker, (tanker_stream_input_source_t)&readInput, (__bridge_retained void*)reader);
  tanker_future_t* resolve_fut =
      tanker_future_then(create_fut, (tanker_future_then_t)&TKR_resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(resolve_fut);
  tanker_future_destroy(create_fut);
}

- (TKRStatus)status
{
  return (TKRStatus)tanker_status((tanker_t*)self.cTanker);
}

- (void)dealloc
{
  tanker_future_t* destroy_future = tanker_destroy((tanker_t*)self.cTanker);
  tanker_future_wait(destroy_future);
  tanker_future_destroy(destroy_future);
}

@end
