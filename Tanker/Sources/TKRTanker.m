#import <Foundation/Foundation.h>

#import "TKRTanker+Private.h"
#import "TKRTankerOptions+Private.h"
#import "TKRUnlockKey+Private.h"
#import "TKRUtils+Private.h"

#include <assert.h>
#include <string.h>

#include "ctanker.h"

#define TANKER_IOS_VERSION @"9999"

static void dispatchInBackground(id block)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

static void logHandler(tanker_log_record_t const* record)
{
  switch (record->level)
  {
  case TANKER_LOG_DEBUG:
    break;
  case TANKER_LOG_INFO:
    break;
  case TANKER_LOG_WARNING:
    break;
  case TANKER_LOG_ERROR:
    NSLog(@"Tanker Error: [%s] %s", record->category, record->message);
    break;
  default:
    NSLog(@"Unknown Tanker log level: %c: [%s] %s", record->level, record->category, record->message);
  }
}

static void onDeviceRevoked(void* unused, void* extra_arg)
{
  NSLog(@"onDeviceRevoked called");
  assert(!unused);
  assert(extra_arg);

  TKRDeviceRevokedHandler handler = (__bridge typeof(TKRDeviceRevokedHandler))extra_arg;

  handler();
}

static void convertOptions(TKRTankerOptions const* options, tanker_options_t* cOptions)
{
  cOptions->trustchain_id = [options.trustchainID cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->writable_path = [options.writablePath cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->trustchain_url = [options.trustchainURL cStringUsingEncoding:NSUTF8StringEncoding];
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
  tanker.options = options;
  tanker.events = [NSMutableArray array];
  tanker_set_log_handler(&logHandler);

  tanker_options_t cOptions = TANKER_OPTIONS_INIT;
  convertOptions(options, &cOptions);

  tanker_future_t* create_future = tanker_create(&cOptions);
  tanker_future_wait(create_future);
  NSError* error = getOptionalFutureError(create_future);
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
// MARK: Instance methods

- (void)signUpWithIdentity:(nonnull NSString*)identity
     authenticationMethods:(nonnull TKRAuthenticationMethods*)methods
         completionHandler:(nonnull TKRSignUpHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    handler(ptrValue, err);
  };

  char const* c_identity = [identity cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_authentication_methods_t c_methods = TANKER_AUTHENTICATION_METHODS_INIT;
  if (methods.email != nil)
    c_methods.email = [methods.email cStringUsingEncoding:NSUTF8StringEncoding];
  if (methods.password != nil)
    c_methods.password = [methods.password cStringUsingEncoding:NSUTF8StringEncoding];

  tanker_future_t* sign_up_future = tanker_sign_up((tanker_t*)self.cTanker, c_identity, &c_methods);
  tanker_future_t* resolve_future =
      tanker_future_then(sign_up_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(sign_up_future);
  tanker_future_destroy(resolve_future);
}

- (void)signUpWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRSignUpHandler)handler
{
  return [self signUpWithIdentity:identity
            authenticationMethods:[TKRAuthenticationMethods methods]
                completionHandler:handler];
}

- (void)signInWithIdentity:(nonnull NSString*)identity
                   options:(nonnull TKRSignInOptions*)options
         completionHandler:(nonnull TKRSignInHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    handler(ptrValue, err);
  };

  char const* c_identity = [identity cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_sign_in_options_t c_options = TANKER_SIGN_IN_OPTIONS_INIT;
  if (options.verificationCode != nil)
    c_options.verification_code = [options.verificationCode cStringUsingEncoding:NSUTF8StringEncoding];
  if (options.password != nil)
    c_options.password = [options.password cStringUsingEncoding:NSUTF8StringEncoding];
  if (options.unlockKey != nil)
    c_options.unlock_key = [options.unlockKey.value cStringUsingEncoding:NSUTF8StringEncoding];

  tanker_future_t* sign_in_future = tanker_sign_in((tanker_t*)self.cTanker, c_identity, &c_options);
  tanker_future_t* resolve_future =
      tanker_future_then(sign_in_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(sign_in_future);
  tanker_future_destroy(resolve_future);
}

- (void)signInWithIdentity:(nonnull NSString*)identity completionHandler:(nonnull TKRSignInHandler)handler
{
  [self signInWithIdentity:identity options:[TKRSignInOptions options] completionHandler:handler];
}

- (BOOL)isOpen
{
  return tanker_is_open((tanker_t*)self.cTanker);
}

- (void)deviceIDWithCompletionHandler:(nonnull TKRDeviceIDHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    b64char* device_id = (b64char*)numberToPtr(ptrValue);
    NSString* ret = [NSString stringWithCString:device_id encoding:NSUTF8StringEncoding];
    tanker_free_buffer(device_id);
    handler(ret, nil);
  };
  tanker_future_t* device_id_future = tanker_device_id((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(device_id_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(device_id_future);
  tanker_future_destroy(resolve_future);
}

- (void)encryptDataFromString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromString:clearText options:[TKREncryptionOptions options] completionHandler:handler];
}

- (void)encryptDataFromString:(nonnull NSString*)clearText
                      options:(nonnull TKREncryptionOptions*)options
            completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  NSError* err = nil;
  NSData* data = convertStringToData(clearText, &err);

  if (err)
    runOnMainQueue(^{
      handler(nil, err);
    });
  else
    [self encryptDataFromData:data options:options completionHandler:handler];
}

- (void)decryptStringFromData:(nonnull NSData*)cipherText completionHandler:(nonnull TKRDecryptedStringHandler)handler
{
  id adapter = ^(PtrAndSizePair* hack, NSError* err) {
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

  [self decryptDataFromDataImpl:cipherText completionHandler:adapter];
}

- (void)encryptDataFromData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromData:clearData options:[TKREncryptionOptions options] completionHandler:handler];
}

- (void)encryptDataFromData:(nonnull NSData*)clearData
                    options:(nonnull TKREncryptionOptions*)options
          completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  id adapter = ^(PtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* encrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSData* ret = [NSData dataWithBytesNoCopy:encrypted_buffer length:hack.ptrSize freeWhenDone:YES];
    handler(ret, nil);
  };
  [self encryptDataFromDataImpl:clearData options:options completionHandler:adapter];
}

- (void)decryptDataFromData:(nonnull NSData*)cipherData completionHandler:(nonnull TKRDecryptedDataHandler)handler
{
  id adapter = ^(PtrAndSizePair* hack, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    NSData* ret = [NSData dataWithBytesNoCopy:decrypted_buffer length:hack.ptrSize freeWhenDone:YES];
    handler(ret, nil);
  };
  [self decryptDataFromDataImpl:cipherData completionHandler:adapter];
}

- (nullable NSString*)resourceIDOfEncryptedData:(nonnull NSData*)cipherData error:(NSError* _Nullable* _Nonnull)error
{
  tanker_expected_t* resource_id_expected = tanker_get_resource_id((uint8_t const*)cipherData.bytes, cipherData.length);
  *error = getOptionalFutureError(resource_id_expected);
  if (*error)
    return nil;
  char* resource_id = unwrapAndFreeExpected(resource_id_expected);
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
    b64char* group_id = (b64char*)numberToPtr(ptrValue);
    NSString* groupId = [NSString stringWithCString:group_id encoding:NSUTF8StringEncoding];
    tanker_free_buffer(group_id);
    handler(groupId, nil);
  };
  NSError* err = nil;
  char** c_identities = convertStringstoCStrings(identities, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }
  tanker_future_t* future =
      tanker_create_group((tanker_t*)self.cTanker, (char const* const*)c_identities, identities.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(c_identities, identities.count);
}

- (void)updateMembersOfGroup:(nonnull NSString*)groupId
             identitiesToAdd:(nonnull NSArray<NSString*>*)identities
           completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* utf8_groupid = [groupId cStringUsingEncoding:NSUTF8StringEncoding];
  NSError* err = nil;
  char** identities_to_add = convertStringstoCStrings(identities, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(err);
    });
    return;
  }
  tanker_future_t* future = tanker_update_group_members(
      (tanker_t*)self.cTanker, utf8_groupid, (char const* const*)identities_to_add, identities.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(identities_to_add, identities.count);
}

- (void)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                 options:(nonnull TKRShareOptions*)options
       completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  NSError* err = nil;
  char** resource_ids = convertStringstoCStrings(resourceIDs, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(err);
    });
    return;
  }
  char** user_ids = convertStringstoCStrings(options.shareWithUsers, &err);
  if (err)
  {
    freeCStringArray(resource_ids, resourceIDs.count);
    runOnMainQueue(^{
      handler(err);
    });
    return;
  }
  char** group_ids = convertStringstoCStrings(options.shareWithGroups, &err);
  if (err)
  {
    freeCStringArray(resource_ids, resourceIDs.count);
    freeCStringArray(user_ids, options.shareWithUsers.count);
    runOnMainQueue(^{
      handler(err);
    });
    return;
  }

  tanker_future_t* share_future = tanker_share((tanker_t*)self.cTanker,
                                               (char const* const*)user_ids,
                                               options.shareWithUsers.count,
                                               (char const* const*)group_ids,
                                               options.shareWithGroups.count,
                                               (char const* const*)resource_ids,
                                               resourceIDs.count);

  tanker_future_t* resolve_future =
      tanker_future_then(share_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);

  tanker_future_destroy(share_future);
  tanker_future_destroy(resolve_future);

  freeCStringArray(resource_ids, resourceIDs.count);
  freeCStringArray(user_ids, options.shareWithUsers.count);
  freeCStringArray(group_ids, options.shareWithGroups.count);
}

- (nonnull NSNumber*)connectDeviceRevokedHandler:(nonnull TKRDeviceRevokedHandler)handler
{
  NSNumber* evt = [NSNumber numberWithInt:TANKER_EVENT_DEVICE_REVOKED];
  NSNumber* callbackPtr = [NSNumber numberWithUnsignedLong:(uintptr_t)&onDeviceRevoked];

  NSError* err = nil;
  NSNumber* ret = [self setEvent:evt
                     callbackPtr:callbackPtr
                         handler:^(void* unused) {
                           dispatchInBackground(handler);
                         }
                           error:&err];
  // Err cannot fail as the event is a valid tanker event
  assert(!err);
  return ret;
}

- (void)registerUnlockWithOptions:(nonnull TKRUnlockOptions*)options completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* utf8_password = options.password ? [options.password cStringUsingEncoding:NSUTF8StringEncoding] : NULL;
  char const* utf8_email = options.email ? [options.email cStringUsingEncoding:NSUTF8StringEncoding] : NULL;
  tanker_future_t* setup_future = tanker_register_unlock((tanker_t*)self.cTanker, utf8_email, utf8_password);
  tanker_future_t* resolve_future =
      tanker_future_then(setup_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(setup_future);
  tanker_future_destroy(resolve_future);
}

- (void)generateAndRegisterUnlockKeyWithCompletionHandler:(nonnull TKRUnlockKeyHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* ptrValue, NSError* err) {
    if (err)
    {
      handler(nil, err);
      return;
    }
    b64char* unlock_key = (b64char*)numberToPtr(ptrValue);
    NSString* unlockKey = [NSString stringWithCString:unlock_key encoding:NSUTF8StringEncoding];

    TKRUnlockKey* ret = [[TKRUnlockKey alloc] init];
    ret.valuePrivate = unlockKey;
    tanker_free_buffer(unlock_key);
    handler(ret, nil);
  };

  tanker_expected_t* unlock_key_fut = tanker_generate_and_register_unlock_key((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(unlock_key_fut, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);

  tanker_future_destroy(unlock_key_fut);
  tanker_future_destroy(resolve_future);
}

- (void)isUnlockAlreadySetUpWithCompletionHandler:(nonnull TKRBooleanHandler)handler
{
  tanker_future_t* already_future = tanker_is_unlock_already_set_up((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(already_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)handler);
  tanker_future_destroy(already_future);
  tanker_future_destroy(resolve_future);
}

- (BOOL)hasRegisteredUnlockMethodsWithError:(NSError* _Nullable* _Nonnull)err
{
  tanker_expected_t* exp = tanker_has_registered_unlock_methods((tanker_t*)self.cTanker);

  *err = getOptionalFutureError(exp);
  if (*err)
    return NO;
  return (BOOL)unwrapAndFreeExpected(exp);
}

- (BOOL)hasRegisteredUnlockMethod:(TKRUnlockMethods)method error:(NSError* _Nullable* _Nonnull)err
{
  tanker_expected_t* exp =
      tanker_has_registered_unlock_method((tanker_t*)self.cTanker, (enum tanker_unlock_method)method);

  *err = getOptionalFutureError(exp);
  if (*err)
    return NO;
  return (BOOL)unwrapAndFreeExpected(exp);
}

- (nullable NSArray<NSNumber*>*)registeredUnlockMethodsWithError:(NSError* _Nullable* _Nonnull)err
{
  tanker_expected_t* exp = tanker_registered_unlock_methods((tanker_t*)self.cTanker);

  *err = getOptionalFutureError(exp);
  if (*err)
    return nil;
  uintptr_t imethods = (uintptr_t)unwrapAndFreeExpected(exp);

  NSMutableArray* ret = [[NSMutableArray alloc] init];
  if (imethods & TANKER_UNLOCK_METHOD_EMAIL)
    [ret addObject:[NSNumber numberWithUnsignedInteger:TKRUnlockMethodEmail]];
  if (imethods & TANKER_UNLOCK_METHOD_PASSWORD)
    [ret addObject:[NSNumber numberWithUnsignedInteger:TKRUnlockMethodPassword]];
  return ret;
}

- (void)revokeDevice:(nonnull NSString*)deviceId completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  char const* device_id = [deviceId cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* revoke_future = tanker_revoke_device((tanker_t*)self.cTanker, device_id);
  tanker_future_t* resolve_future =
      tanker_future_then(revoke_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(revoke_future);
  tanker_future_destroy(resolve_future);
}

- (void)signOutWithCompletionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  tanker_future_t* sign_out_future = tanker_sign_out((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(sign_out_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(sign_out_future);
  tanker_future_destroy(resolve_future);
}

- (void)dealloc
{
  for (NSNumber* value in self.events)
    [self disconnectEventConnection:value];

  tanker_future_t* destroy_future = tanker_destroy((tanker_t*)self.cTanker);
  tanker_future_wait(destroy_future);
  tanker_future_destroy(destroy_future);
}

@end
