#import <Foundation/Foundation.h>

#import "TKRChunkEncryptor+Private.h"
#import "TKRTanker+Private.h"
#import "TKRTankerOptions+Private.h"
#import "TKRUnlockKey+Private.h"
#import "TKRUtils+Private.h"

#include <assert.h>
#include <string.h>

#include "ctanker.h"

#define TANKER_IOS_VERSION @"dev"

static void dispatchInBackground(id block)
{
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

static void logHandler(char const* category, char level, char const* message)
{
  switch (level)
  {
  case 'D':
    break;
  case 'I':
    break;
  case 'E':
    NSLog(@"Tanker Error: [%s] %s", category, message);
    break;
  default:
    NSLog(@"Unknown Tanker log level: %c: [%s] %s", level, category, message);
  }
}

static void onUnlockRequired(void* unused, void* extra_arg)
{
  NSLog(@"onUnlockRequired called");
  assert(!unused);
  assert(extra_arg);

  TKRUnlockRequiredHandler handler = (__bridge_transfer typeof(TKRUnlockRequiredHandler))extra_arg;

  handler();
}

static void onDeviceRevoked(void* unused, void* extra_arg)
{
  NSLog(@"onDeviceRevoked called");
  assert(!unused);
  assert(extra_arg);

  TKRDeviceRevokedHandler handler = (__bridge_transfer typeof(TKRDeviceRevokedHandler))extra_arg;

  handler();
}

static void onDeviceCreated(void* unused, void* extra_arg)
{
  NSLog(@"onDeviceCreated called");
  assert(!unused);
  assert(extra_arg);

  TKRDeviceCreatedHandler handler = (__bridge_transfer typeof(TKRDeviceCreatedHandler))extra_arg;

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

- (nonnull NSString*)statusAsString
{
  switch (self.status)
  {
  case TKRStatusOpen:
    return @"open";
  case TKRStatusClosed:
    return @"closed";
  case TKRStatusClosing:
    return @"closing";
  case TKRStatusUserCreation:
    return @"user creation";
  case TKRStatusDeviceCreation:
    return @"device creation";
  }
}

- (void)openWithUserID:(nonnull NSString*)userID
             userToken:(nonnull NSString*)userToken
     completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* user_token = [userToken cStringUsingEncoding:NSUTF8StringEncoding];

  tanker_future_t* open_future = tanker_open((tanker_t*)self.cTanker, user_id, user_token);
  tanker_future_t* resolve_future =
      tanker_future_then(open_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(open_future);
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

- (void)makeChunkEncryptorWithCompletionHandler:(nonnull TKRChunkEncryptorHandler)handler
{
  [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self seal:nil options:nil completionHandler:handler];
}

- (void)makeChunkEncryptorFromSeal:(nonnull NSData*)seal completionHandler:(nonnull TKRChunkEncryptorHandler)handler
{
  // TODO harmonize APIs taking defaultOptions vs. nullable.
  [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self
                                            seal:seal
                                         options:[TKRDecryptionOptions defaultOptions]
                               completionHandler:handler];
}

- (void)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
                           options:(nonnull TKRDecryptionOptions*)options
                 completionHandler:(nonnull TKRChunkEncryptorHandler)handler
{
  [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self seal:seal options:options completionHandler:handler];
}

- (void)encryptDataFromString:(nonnull NSString*)clearText completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromString:clearText options:[TKREncryptionOptions defaultOptions] completionHandler:handler];
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

- (void)decryptStringFromData:(nonnull NSData*)cipherText
                      options:(nonnull TKRDecryptionOptions*)options
            completionHandler:(nonnull TKRDecryptedStringHandler)handler
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

  [self decryptDataFromDataImpl:cipherText options:options completionHandler:adapter];
}

- (void)decryptStringFromData:(nonnull NSData*)cipherText completionHandler:(nonnull TKRDecryptedStringHandler)handler
{
  [self decryptStringFromData:cipherText options:[TKRDecryptionOptions defaultOptions] completionHandler:handler];
}

- (void)encryptDataFromData:(nonnull NSData*)clearData completionHandler:(nonnull TKREncryptedDataHandler)handler
{
  [self encryptDataFromData:clearData options:[TKREncryptionOptions defaultOptions] completionHandler:handler];
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

- (void)decryptDataFromData:(nonnull NSData*)cipherData
                    options:(nonnull TKRDecryptionOptions*)options
          completionHandler:(nonnull TKRDecryptedDataHandler)handler
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
  [self decryptDataFromDataImpl:cipherData options:options completionHandler:adapter];
}

- (void)decryptDataFromData:(nonnull NSData*)cipherData completionHandler:(nonnull TKRDecryptedDataHandler)handler
{
  [self decryptDataFromData:cipherData options:[TKRDecryptionOptions defaultOptions] completionHandler:handler];
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

- (void)createGroupWithUserIDs:(nonnull NSArray<NSString*>*)userIds completionHandler:(nonnull TKRGroupIDHandler)handler
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
  char** user_ids = convertStringstoCStrings(userIds, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(nil, err);
    });
    return;
  }
  tanker_future_t* future = tanker_create_group((tanker_t*)self.cTanker, (char const* const*)user_ids, userIds.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(user_ids, userIds.count);
}

- (void)updateMembersOfGroup:(NSString*)groupId
                         add:(NSArray<NSString*>*)usersToAdd
           completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* utf8_groupid = [groupId cStringUsingEncoding:NSUTF8StringEncoding];
  NSError* err = nil;
  char** users_to_add = convertStringstoCStrings(usersToAdd, &err);
  if (err)
  {
    runOnMainQueue(^{
      handler(err);
    });
    return;
  }
  tanker_future_t* future = tanker_update_group_members(
      (tanker_t*)self.cTanker, utf8_groupid, (char const* const*)users_to_add, usersToAdd.count);
  tanker_future_t* resolve_future =
      tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(future);
  tanker_future_destroy(resolve_future);
  freeCStringArray(users_to_add, usersToAdd.count);
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

- (nonnull NSNumber*)connectUnlockRequiredHandler:(nonnull TKRUnlockRequiredHandler)handler
{
  NSNumber* evt = [NSNumber numberWithInt:TANKER_EVENT_UNLOCK_REQUIRED];
  NSNumber* callbackPtr = [NSNumber numberWithUnsignedLong:(uintptr_t)&onUnlockRequired];

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

- (nonnull NSNumber*)connectDeviceCreatedHandler:(nonnull TKRDeviceCreatedHandler)handler
{
  NSNumber* evt = [NSNumber numberWithInt:TANKER_EVENT_DEVICE_CREATED];
  NSNumber* callbackPtr = [NSNumber numberWithUnsignedLong:(uintptr_t)&onDeviceCreated];

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

- (void)registerUnlock:(nonnull TKRUnlockOptions*)options completionHandler:(nonnull TKRErrorHandler)handler
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

- (void)setupUnlockWithPassword:(nonnull NSString*)password completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };

  char const* utf8_password = [password cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* setup_future = tanker_setup_unlock((tanker_t*)self.cTanker, NULL, utf8_password);
  tanker_future_t* resolve_future =
      tanker_future_then(setup_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(setup_future);
  tanker_future_destroy(resolve_future);
}

- (void)updateUnlockPassword:(nonnull NSString*)newPassword completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  char const* utf8_password = [newPassword cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* update_future = tanker_update_unlock((tanker_t*)self.cTanker, NULL, utf8_password, NULL);
  tanker_future_t* resolve_future =
      tanker_future_then(update_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(update_future);
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

- (void)unlockCurrentDeviceWithUnlockKey:(nonnull TKRUnlockKey*)unlockKey
                       completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  b64char const* utf8UnlockKey = [unlockKey.value cStringUsingEncoding:NSUTF8StringEncoding];
  // tanker copies the validation code
  tanker_future_t* validate_future =
      tanker_unlock_current_device_with_unlock_key((tanker_t*)self.cTanker, utf8UnlockKey);
  tanker_future_t* resolve_future =
      tanker_future_then(validate_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(validate_future);
  tanker_future_destroy(resolve_future);
}

- (void)unlockCurrentDeviceWithPassword:(nonnull NSString*)password completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  b64char const* utf8_password = [password cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* unlock_future = tanker_unlock_current_device_with_password((tanker_t*)self.cTanker, utf8_password);
  tanker_future_t* resolve_future =
      tanker_future_then(unlock_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(unlock_future);
  tanker_future_destroy(resolve_future);
}

- (void)unlockCurrentDeviceWithVerificationCode:(nonnull NSString*)verificationCode
                              completionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  b64char const* utf8_code = [verificationCode cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_future_t* unlock_future =
      tanker_unlock_current_device_with_verification_code((tanker_t*)self.cTanker, utf8_code);
  tanker_future_t* resolve_future =
      tanker_future_then(unlock_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(unlock_future);
  tanker_future_destroy(resolve_future);
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

- (void)closeWithCompletionHandler:(nonnull TKRErrorHandler)handler
{
  TKRAdapter adapter = ^(NSNumber* unused, NSError* err) {
    handler(err);
  };
  tanker_future_t* close_future = tanker_close((tanker_t*)self.cTanker);
  tanker_future_t* resolve_future =
      tanker_future_then(close_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)adapter);
  tanker_future_destroy(close_future);
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

// MARK: Custom accessors

@synthesize status = _status;

- (TKRStatus)status
{
  return (TKRStatus)tanker_get_status((tanker_t*)self.cTanker);
}

@end
