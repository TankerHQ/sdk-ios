#import <Foundation/Foundation.h>

#import "PromiseKit.h"

#import "TKRChunkEncryptor+Private.h"
#import "TKRTanker+Private.h"
#import "TKRTanker.h"
#import "TKRUnlockKey+Private.h"
#import "TKRUtils+Private.h"

#include <assert.h>
#include <string.h>

#include <tanker.h>
#include <tanker/tanker.h>

#define TANKER_IOS_VERSION @"1.9.0"

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

static void convertOptions(TKRTankerOptions const* options, tanker_options_t* cOptions)
{
  cOptions->trustchain_id = [options.trustchainID cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->writable_path = [options.writablePath cStringUsingEncoding:NSUTF8StringEncoding];
  cOptions->trustchain_url = [options.trustchainURL cStringUsingEncoding:NSUTF8StringEncoding];
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

- (nonnull PMKPromise*)openWithUserID:(nonnull NSString*)userID userToken:(nonnull NSString*)userToken
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
    char const* user_token = [userToken cStringUsingEncoding:NSUTF8StringEncoding];

    tanker_future_t* open_future = tanker_open((tanker_t*)self.cTanker, user_id, user_token);
    tanker_future_t* resolve_future =
        tanker_future_then(open_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(open_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise<NSString*>*)deviceID
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
           tanker_future_t* device_id_future = tanker_device_id((tanker_t*)self.cTanker);
           tanker_future_t* resolve_future = tanker_future_then(
               device_id_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
           tanker_future_destroy(device_id_future);
           tanker_future_destroy(resolve_future);
         }]
      .then(^(NSNumber* ptrValue) {
        b64char* device_id = (b64char*)numberToPtr(ptrValue);
        NSString* ret = [NSString stringWithCString:device_id encoding:NSUTF8StringEncoding];
        tanker_free_buffer(device_id);
        return ret;
      });
}

- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptor
{
  return [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self seal:nil options:nil];
}

- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
{
  // TODO harmonize APIs taking defaultOptions vs. nullable.
  return [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self seal:seal options:[TKRDecryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<TKRChunkEncryptor*>*)makeChunkEncryptorFromSeal:(nonnull NSData*)seal
                                                              options:(nonnull TKRDecryptionOptions*)options
{
  return [TKRChunkEncryptor chunkEncryptorWithTKRTanker:self seal:seal options:options];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText
{
  return [self encryptDataFromString:clearText options:[TKREncryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromString:(nonnull NSString*)clearText
                                              options:(nonnull TKREncryptionOptions*)options
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
           resolve(convertStringToData(clearText));
         }]
      .then(^(NSData* clearData) {
        return [self encryptDataFromDataImpl:clearData options:options];
      })
      .then(^(PtrAndSizePair* hack) {
        uint8_t* encrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);
        return [NSData dataWithBytesNoCopy:encrypted_buffer length:hack.ptrSize freeWhenDone:YES];
      });
}

- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText
                                                options:(nonnull TKRDecryptionOptions*)options
{
  return [self decryptDataFromDataImpl:cipherText options:options].then(^(PtrAndSizePair* hack) {
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    return [[NSString alloc] initWithBytesNoCopy:decrypted_buffer
                                          length:hack.ptrSize
                                        encoding:NSUTF8StringEncoding
                                    freeWhenDone:YES];
  });
}

- (nonnull PMKPromise<NSString*>*)decryptStringFromData:(nonnull NSData*)cipherText
{
  return [self decryptStringFromData:cipherText options:[TKRDecryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData
{
  return [self encryptDataFromData:clearData options:[TKREncryptionOptions defaultOptions]];
}

- (nonnull PMKPromise<NSData*>*)encryptDataFromData:(nonnull NSData*)clearData
                                            options:(nonnull TKREncryptionOptions*)options
{
  return [self encryptDataFromDataImpl:clearData options:options].then(^(PtrAndSizePair* hack) {
    uint8_t* encrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    return [NSData dataWithBytesNoCopy:encrypted_buffer length:hack.ptrSize freeWhenDone:YES];
  });
}

- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherData
                                            options:(nonnull TKRDecryptionOptions*)options
{
  return [self decryptDataFromDataImpl:cipherData options:options].then(^(PtrAndSizePair* hack) {
    uint8_t* decrypted_buffer = (uint8_t*)((uintptr_t)hack.ptrValue);

    return [NSData dataWithBytesNoCopy:decrypted_buffer length:hack.ptrSize freeWhenDone:YES];
  });
}

- (nonnull PMKPromise<NSData*>*)decryptDataFromData:(nonnull NSData*)cipherData
{
  return [self decryptDataFromData:cipherData options:[TKRDecryptionOptions defaultOptions]];
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

- (nonnull PMKPromise<NSString*>*)createGroupWithUserIDs:(nonnull NSArray<NSString*>*)userIds
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char** user_ids = convertStringstoCStrings(userIds);

    tanker_future_t* future = tanker_create_group((tanker_t*)self.cTanker, (char const* const*)user_ids, userIds.count);
    tanker_future_t* resolve_future =
        tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(future);
    tanker_future_destroy(resolve_future);
    for (int i = 0; i < userIds.count; ++i)
      free(user_ids[i]);
    free(user_ids);
  }].then(^(NSNumber* ptrValue) {
    b64char* group_id = (b64char*)numberToPtr(ptrValue);
    NSString* groupId = [NSString stringWithCString:group_id encoding:NSUTF8StringEncoding];
    tanker_free_buffer(group_id);
    return groupId;
  });
}

- (nonnull PMKPromise*)updateMembersOfGroup:(NSString*)groupId
                                        add:(NSArray<NSString*>*)usersToAdd
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char const* utf8_groupid = [groupId cStringUsingEncoding:NSUTF8StringEncoding];
    char** users_to_add = convertStringstoCStrings(usersToAdd);

    tanker_future_t* future = tanker_update_group_members((tanker_t*)self.cTanker, utf8_groupid, (char const* const*)users_to_add, usersToAdd.count);
    tanker_future_t* resolve_future =
    tanker_future_then(future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(future);
    tanker_future_destroy(resolve_future);
    for (int i = 0; i < usersToAdd.count; ++i)
      free(users_to_add[i]);
    free(users_to_add);
  }];
}

- (nonnull PMKPromise*)shareResourceIDs:(nonnull NSArray<NSString*>*)resourceIDs
                                options:(nonnull TKRShareOptions*)options
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char** resource_ids = convertStringstoCStrings(resourceIDs);
    char** user_ids = convertStringstoCStrings(options.shareWithUsers);
    char** group_ids = convertStringstoCStrings(options.shareWithGroups);

    tanker_future_t* share_future = tanker_share((tanker_t*)self.cTanker,
                                                 (char const* const*)user_ids,
                                                 options.shareWithUsers.count,
                                                 (char const* const*)group_ids,
                                                 options.shareWithGroups.count,
                                                 (char const* const*)resource_ids,
                                                 resourceIDs.count);

    tanker_future_t* resolve_future =
        tanker_future_then(share_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);

    tanker_future_destroy(share_future);
    tanker_future_destroy(resolve_future);

    // No need to retain anything, tanker_share copies everything.
    for (int i = 0; i < resourceIDs.count; ++i)
      free(resource_ids[i]);
    free(resource_ids);
    for (int i = 0; i < options.shareWithUsers.count; ++i)
      free(user_ids[i]);
    free(user_ids);
    for (int i = 0; i < options.shareWithGroups.count; ++i)
      free(group_ids[i]);
    free(group_ids);
  }];
}

- (nonnull NSNumber*)connectUnlockRequiredHandler:(nonnull TKRUnlockRequiredHandler)handler
{
  NSNumber* evt = [NSNumber numberWithInt:TANKER_EVENT_UNLOCK_REQUIRED];
  NSNumber* callbackPtr = [NSNumber numberWithUnsignedLong:(uintptr_t)&onUnlockRequired];

  // TODO throw TKRException?
  NSError* err = nil;
  NSNumber* ret = [self setEvent:evt
                     callbackPtr:callbackPtr
                         handler:^(id unused) {
                           dispatch_promise(^{
                             handler();
                           });
                           }
                           error:&err];
  return ret;
}

- (nonnull PMKPromise*)registerUnlock:(nonnull TKRUnlockOptions*)options
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char const* utf8_password = options.password ? [options.password cStringUsingEncoding:NSUTF8StringEncoding] : NULL;
    char const* utf8_email = options.email ? [options.email cStringUsingEncoding:NSUTF8StringEncoding] : NULL;
    tanker_future_t* setup_future = tanker_register_unlock((tanker_t*)self.cTanker, utf8_email, utf8_password);
    tanker_future_t* resolve_future =
    tanker_future_then(setup_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(setup_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise*)setupUnlockWithPassword:(nonnull NSString*)password
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char const* utf8_password = [password cStringUsingEncoding:NSUTF8StringEncoding];
    tanker_future_t* setup_future = tanker_setup_unlock((tanker_t*)self.cTanker, NULL, utf8_password);
    tanker_future_t* resolve_future =
        tanker_future_then(setup_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(setup_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise*)updateUnlockPassword:(nonnull NSString*)newPassword
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    char const* utf8_password = [newPassword cStringUsingEncoding:NSUTF8StringEncoding];
    tanker_future_t* update_future = tanker_update_unlock((tanker_t*)self.cTanker, NULL, utf8_password, NULL);
    tanker_future_t* resolve_future =
        tanker_future_then(update_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(update_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise<TKRUnlockKey*>*)generateAndRegisterUnlockKey
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
           tanker_expected_t* unlock_key_fut = tanker_generate_and_register_unlock_key((tanker_t*)self.cTanker);
           tanker_future_t* resolve_future = tanker_future_then(
               unlock_key_fut, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);

           tanker_future_destroy(unlock_key_fut);
           tanker_future_destroy(resolve_future);
         }]
      .then(^(NSNumber* ptrValue) {
        b64char* unlock_key = (b64char*)numberToPtr(ptrValue);
        NSString* unlockKey = [NSString stringWithCString:unlock_key encoding:NSUTF8StringEncoding];

        TKRUnlockKey* ret = [[TKRUnlockKey alloc] init];
        ret.valuePrivate = unlockKey;
        tanker_free_buffer(unlock_key);
        return ret;
      });
}

- (nonnull PMKPromise<NSNumber*>*)isUnlockAlreadySetUp
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    tanker_future_t* already_future = tanker_is_unlock_already_set_up((tanker_t*)self.cTanker);
    tanker_future_t* resolve_future =
        tanker_future_then(already_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(already_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise<NSNumber*>*)hasRegisteredUnlockMethods
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    tanker_future_t* already_future = tanker_has_registered_unlock_methods((tanker_t*)self.cTanker);
    tanker_future_t* resolve_future =
    tanker_future_then(already_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(already_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise<NSNumber*>*)hasRegisteredUnlockMethod:(NSUInteger)method
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    tanker_future_t* already_future = tanker_has_registered_unlock_method((tanker_t*)self.cTanker, (enum tanker_unlock_method)method);
    tanker_future_t* resolve_future =
    tanker_future_then(already_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(already_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise<NSArray*>*)registeredUnlockMethods
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    tanker_future_t* already_future = tanker_registered_unlock_methods((tanker_t*)self.cTanker);
    tanker_future_t* resolve_future =
    tanker_future_then(already_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(already_future);
    tanker_future_destroy(resolve_future);
  }]
  .then(^(NSNumber* methods) {
    long imethods = methods.integerValue;

    NSMutableArray* ret = [[NSMutableArray alloc] init];
    if (imethods & TANKER_UNLOCK_METHOD_EMAIL)
      [ret addObject:[NSNumber numberWithUnsignedInteger:TKRUnlockMethodEmail]];
    if (imethods & TANKER_UNLOCK_METHOD_PASSWORD)
      [ret addObject:[NSNumber numberWithUnsignedInteger:TKRUnlockMethodPassword]];

    return ret;
  });
}

- (nonnull PMKPromise*)unlockCurrentDeviceWithUnlockKey:(nonnull TKRUnlockKey*)unlockKey
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    b64char const* utf8UnlockKey = [unlockKey.value cStringUsingEncoding:NSUTF8StringEncoding];
    // tanker copies the validation code
    tanker_future_t* validate_future =
        tanker_unlock_current_device_with_unlock_key((tanker_t*)self.cTanker, utf8UnlockKey);
    tanker_future_t* resolve_future =
        tanker_future_then(validate_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(validate_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise*)unlockCurrentDeviceWithPassword:(nonnull NSString*)password
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    b64char const* utf8_password = [password cStringUsingEncoding:NSUTF8StringEncoding];
    tanker_future_t* unlock_future = tanker_unlock_current_device_with_password((tanker_t*)self.cTanker, utf8_password);
    tanker_future_t* resolve_future =
        tanker_future_then(unlock_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(unlock_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise*)unlockCurrentDeviceWithVerificationCode:(nonnull NSString*)verificationCode
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    b64char const* utf8_code = [verificationCode cStringUsingEncoding:NSUTF8StringEncoding];
    tanker_future_t* unlock_future = tanker_unlock_current_device_with_verification_code((tanker_t*)self.cTanker, utf8_code);
    tanker_future_t* resolve_future =
    tanker_future_then(unlock_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(unlock_future);
    tanker_future_destroy(resolve_future);
  }];
}

- (nonnull PMKPromise*)close
{
  return [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    tanker_future_t* close_future = tanker_close((tanker_t*)self.cTanker);
    tanker_future_t* resolve_future =
        tanker_future_then(close_future, (tanker_future_then_t)&resolvePromise, (__bridge_retained void*)resolve);
    tanker_future_destroy(close_future);
    tanker_future_destroy(resolve_future);
  }];
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
