// https://github.com/Specta/Specta

#import "TKRError.h"
#import "TKRTanker.h"
#import "TKRTankerOptions+Private.h"
#import "TKRUnlockKey.h"

#import "TKRTestConfig.h"

@import Expecta;
@import Specta;
@import PromiseKit;

#include "ctanker.h"
#include "ctanker/user_token.h"

NSError* getOptionalFutureError(tanker_future_t* fut)
{
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

void* unwrapAndFreeExpected(tanker_expected_t* expected)
{
  NSError* optErr = getOptionalFutureError(expected);
  if (optErr)
  {
    tanker_future_destroy(expected);
    @throw optErr;
  }

  void* ptr = tanker_future_get_voidptr(expected);
  tanker_future_destroy(expected);

  return ptr;
}

NSString* createUserToken(NSString* userID, NSString* trustchainID, NSString* trustchainPrivateKey)
{
  char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* trustchain_id = [trustchainID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* trustchain_priv_key = [trustchainPrivateKey cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* user_token_expected = tanker_generate_user_token(trustchain_id, trustchain_priv_key, user_id);
  char* user_token = unwrapAndFreeExpected(user_token_expected);
  assert(user_token);
  return [[NSString alloc] initWithBytesNoCopy:user_token
                                        length:strlen(user_token)
                                      encoding:NSUTF8StringEncoding
                                  freeWhenDone:YES];
}

NSString* createUUID()
{
  return [[NSUUID UUID] UUIDString];
}

NSString* createStorageFullpath()
{
  NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString* path = [[paths objectAtIndex:0] stringByAppendingPathComponent:createUUID()];
  NSError* err;
  BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&err];
  assert(success);
  return path;
}

TKRTankerOptions* createTankerOptions(NSString* url, NSString* trustchainID)
{
  TKRTankerOptions* opts = [TKRTankerOptions options];
  opts.trustchainURL = url;
  opts.trustchainID = trustchainID;
  opts.writablePath = createStorageFullpath();
  opts.sdkType = @"test";
  return opts;
}

id hangWithAdapter(void (^handler)(PMKAdapter))
{
  return [PMKPromise hang:[PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
                       handler(adapter);
                     }]];
}

id hangWithResolver(void (^handler)(PMKResolver))
{
  return [PMKPromise hang:[PMKPromise promiseWithResolver:^(PMKResolver resolve) {
                       handler(resolve);
                     }]];
}

SpecBegin(TankerSpecs)

    describe(@"Tanker Bindings", ^{
      __block tanker_admin_t* admin;
      __block NSString* trustchainURL;
      __block NSString* trustchainID;
      __block NSString* trustchainPrivateKey;

      __block TKRTankerOptions* tankerOptions;
      beforeAll(^{
        NSString* configName = TANKER_CONFIG_NAME;
        NSString* configPath = TANKER_CONFIG_FILEPATH;
        NSLog(@"Reading config from %@", configPath);
        NSData* data = [NSData dataWithContentsOfFile:configPath];
        expect(data).toNot.beNil();
        NSError* error = nil;
        expect(error).to.beNil();
        NSDictionary* dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
        expect(dict).toNot.beNil();
        NSDictionary* config = [dict valueForKey:configName];
        expect(config).toNot.beNil();
        trustchainURL = [config valueForKey:@"url"];
        expect(trustchainURL).toNot.beNil();
        NSString* idToken = [config valueForKey:@"idToken"];
        expect(idToken).toNot.beNil();
        char const* trustchain_url = [trustchainURL cStringUsingEncoding:NSUTF8StringEncoding];
        char const* id_token = [idToken cStringUsingEncoding:NSUTF8StringEncoding];
        tanker_future_t* connect_fut = tanker_admin_connect(trustchain_url, id_token);
        tanker_future_wait(connect_fut);
        NSError* connectError = getOptionalFutureError(connect_fut);
        expect(connectError).to.beNil();
        admin = (tanker_admin_t*)tanker_future_get_voidptr(connect_fut);
        tanker_future_destroy(connect_fut);
        tanker_future_t* trustchain_fut = tanker_admin_create_trustchain(admin, "ios-test");
        tanker_future_wait(trustchain_fut);
        NSError* createError = getOptionalFutureError(trustchain_fut);
        expect(createError).to.beNil();
        tanker_trustchain_descriptor_t* trustchain =
            (tanker_trustchain_descriptor_t*)tanker_future_get_voidptr(trustchain_fut);
        trustchainID = [NSString stringWithCString:trustchain->id encoding:NSUTF8StringEncoding];
        trustchainPrivateKey = [NSString stringWithCString:trustchain->private_key encoding:NSUTF8StringEncoding];
        tanker_future_destroy(trustchain_fut);
        tanker_admin_trustchain_descriptor_free(trustchain);
      });

      afterAll(^{
        tanker_future_t* delete_fut =
            tanker_admin_delete_trustchain(admin, [trustchainID cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(delete_fut);
        NSError* error = getOptionalFutureError(delete_fut);
        expect(error).to.beNil();

        tanker_future_t* admin_destroy_fut = tanker_admin_destroy(admin);
        tanker_future_wait(admin_destroy_fut);
        error = getOptionalFutureError(admin_destroy_fut);
        expect(error).to.beNil();
      });

      beforeEach(^{
        tankerOptions = createTankerOptions(trustchainURL, trustchainID);
      });

      describe(@"init", ^{
        __block TKRTanker* tanker;

        it(@"should return TKRStatusClosed once tanker object is created", ^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];

          expect(tanker.status).to.equal(TKRStatusClosed);
        });

        it(@"should throw when TrustchainID is not base64", ^{
          tankerOptions.trustchainID = @",,";
          expect(^{
            [TKRTanker tankerWithOptions:tankerOptions];
          })
              .to.raise(NSInvalidArgumentException);
        });
      });

      describe(@"open", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
        });

        it(@"should return TKRStatusOpen when open is called", ^{
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          expect(tanker.status).to.equal(TKRStatusOpen);

          hangWithResolver(^(PMKResolver resolve) {
            [tanker closeWithCompletionHandler:resolve];
          });

          expect(tanker.status).to.equal(TKRStatusClosed);
        });

        it(@"should return a valid base64 string when retrieving the current device id", ^{
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          NSString* deviceID = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });
          NSData* b64Data = [[NSData alloc] initWithBase64EncodedString:deviceID options:0];

          expect(b64Data).toNot.beNil();

          hangWithResolver(^(PMKResolver resolve) {
            [tanker closeWithCompletionHandler:resolve];
          });

          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });
          NSLog(@"%@", [err localizedDescription]);
          expect(err.domain).to.equal(TKRErrorDomain);

          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          NSString* deviceIDBis = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });

          expect(deviceIDBis).to.equal(deviceID);
        });

        it(@"should throw when opening with a wrong user ID", ^{
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:@"wrong" userToken:userToken completionHandler:resolve];
          });

          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });
      });

      describe(@"crypto", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(tanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [tanker closeWithCompletionHandler:resolve];
          });
        });

        it(@"should decrypt an encrypted string", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptDataFromString:clearText completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should encrypt an empty string", ^{
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptDataFromString:@"" completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedText).to.equal(@"");
        });

        it(@"should decrypt an encrypted data", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptDataFromData:clearData completionHandler:adapter];
          });
          NSData* decryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptDataFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedData).to.equal(clearData);
        });
      });

      describe(@"groups", ^{
        __block TKRTanker* aliceTanker;
        __block TKRTanker* bobTanker;
        __block NSString* aliceID;
        __block NSString* bobID;

        beforeEach(^{
          aliceTanker = [TKRTanker tankerWithOptions:tankerOptions];
          bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(aliceTanker).toNot.beNil();
          expect(bobTanker).toNot.beNil();

          aliceID = createUUID();
          bobID = createUUID();
          NSString* aliceToken = createUserToken(aliceID, trustchainID, trustchainPrivateKey);
          NSString* bobToken = createUserToken(bobID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker openWithUserID:aliceID userToken:aliceToken completionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker openWithUserID:bobID userToken:bobToken completionHandler:resolve];
          });
          expect(aliceTanker.status).to.equal(TKRStatusOpen);
          expect(bobTanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker closeWithCompletionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker closeWithCompletionHandler:resolve];
          });
        });

        it(@"should create a group with alice and encrypt to her", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[ aliceID ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions defaultOptions];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptDataFromString:clearText options:encryptionOptions completionHandler:adapter];
          });
          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should create a group with alice and share to her", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[ aliceID ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptDataFromString:clearText completionHandler:adapter];
          });

          NSError* err = nil;
          NSString* resourceID = [bobTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithGroups = @[ groupId ];
          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should allow bob to decrypt once he's added to the group", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[ aliceID ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions defaultOptions];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptDataFromString:clearText completionHandler:adapter];
          });

          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId add:@[ bobID ] completionHandler:resolve];
          });

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should error when creating an empty group", ^{
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[] completionHandler:adapter];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidGroupSize);
        });

        it(@"should error when adding 0 members to a group", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[ aliceID ] completionHandler:adapter];
          });

          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId add:@[] completionHandler:resolve];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidGroupSize);
        });

        it(@"should error when adding members to a non-existent group", ^{
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:@"o/Fufh9HZuv5XoZJk5X3ny+4ZeEZegoIEzRjYPP7TX0="
                                          add:@[ bobID ]
                            completionHandler:resolve];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorGroupNotFound);
        });

        it(@"should error when creating a group with non-existing members", ^{
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithUserIDs:@[ @"no no no" ] completionHandler:adapter];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorUserNotFound);
        });
      });

      describe(@"share", ^{
        __block TKRTanker* aliceTanker;
        __block TKRTanker* bobTanker;
        __block TKRTanker* charlieTanker;
        __block NSString* aliceID;
        __block NSString* bobID;
        __block NSString* charlieID;
        __block TKREncryptionOptions* encryptionOptions;

        beforeEach(^{
          aliceTanker = [TKRTanker tankerWithOptions:tankerOptions];
          bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          charlieTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(aliceTanker).toNot.beNil();
          expect(bobTanker).toNot.beNil();
          expect(charlieTanker).toNot.beNil();
          encryptionOptions = [TKREncryptionOptions defaultOptions];

          aliceID = createUUID();
          bobID = createUUID();
          charlieID = createUUID();
          NSString* aliceToken = createUserToken(aliceID, trustchainID, trustchainPrivateKey);
          NSString* bobToken = createUserToken(bobID, trustchainID, trustchainPrivateKey);
          NSString* charlieToken = createUserToken(charlieID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker openWithUserID:aliceID userToken:aliceToken completionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker openWithUserID:bobID userToken:bobToken completionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [charlieTanker openWithUserID:charlieID userToken:charlieToken completionHandler:resolve];
          });
          expect(aliceTanker.status).to.equal(TKRStatusOpen);
          expect(bobTanker.status).to.equal(TKRStatusOpen);
          expect(charlieTanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker closeWithCompletionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker closeWithCompletionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [charlieTanker closeWithCompletionHandler:resolve];
          });
        });

        it(@"should return a valid base64 resourceID", ^{
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromString:@"Rosebud" completionHandler:adapter];
          });
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];

          expect(err).to.beNil();

          NSData* b64Data = [[NSData alloc] initWithBase64EncodedString:resourceID options:0];

          expect(b64Data).toNot.beNil();
        });

        it(@"should return an error when giving a truncated buffer", ^{
          NSError* err = nil;
          NSData* truncatedBuffer = [@"truncated" dataUsingEncoding:NSUTF8StringEncoding];
          [aliceTanker resourceIDOfEncryptedData:truncatedBuffer error:&err];

          expect(err).toNot.beNil();
          expect(err.domain).to.equal(TKRErrorDomain);
        });

        it(@"should share data to Bob who can decrypt it", ^{
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromString:clearText completionHandler:adapter];
          });
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];

          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID ];
          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should share data to multiple users who can decrypt it", ^{
          __block NSString* clearText = @"Rosebud";
          NSArray* encryptPromises = @[
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [aliceTanker encryptDataFromString:clearText completionHandler:adapter];
            }],
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [aliceTanker encryptDataFromString:clearText completionHandler:adapter];
            }]
          ];
          NSArray* encryptedTexts = [PMKPromise hang:[PMKPromise all:encryptPromises]];

          NSError* err = nil;

          NSString* resourceID1 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[0] error:&err];
          expect(err).to.beNil();
          NSString* resourceID2 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[1] error:&err];
          expect(err).to.beNil();

          NSArray* resourceIDs = @[ resourceID1, resourceID2 ];

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID, charlieID ];
          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:resourceIDs options:opts completionHandler:resolve];
          });

          NSArray* decryptPromises = @[
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [bobTanker decryptStringFromData:encryptedTexts[0] completionHandler:adapter];
            }],
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [bobTanker decryptStringFromData:encryptedTexts[1] completionHandler:adapter];
            }],
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [charlieTanker decryptStringFromData:encryptedTexts[0] completionHandler:adapter];
            }],
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [charlieTanker decryptStringFromData:encryptedTexts[1] completionHandler:adapter];
            }]
          ];
          NSArray* decryptedTexts = [PMKPromise hang:[PMKPromise all:decryptPromises]];

          [decryptedTexts enumerateObjectsUsingBlock:^(NSString* decryptedText, NSUInteger index, BOOL* stop) {
            expect(decryptedText).to.equal(clearText);
          }];
        });

        it(@"should have no effect to share to nobody", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromString:clearText completionHandler:adapter];
          });
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });
          expect(err).beNil();
        });

        it(@"should have no effect to share nothing", ^{
          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID, charlieID ];
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[] options:opts completionHandler:resolve];
          });
          expect(err).to.beNil();
        });

        it(@"should share directly when encrypting a string", ^{
          NSString* clearText = @"Rosebud";
          encryptionOptions.shareWithUsers = @[ bobID, charlieID ];

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromString:clearText options:encryptionOptions completionHandler:adapter];
          });

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
          decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [charlieTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should share directly when encrypting data", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          encryptionOptions.shareWithUsers = @[ bobID, charlieID ];
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromData:clearData options:encryptionOptions completionHandler:adapter];
          });

          NSData* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptDataFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearData);
          decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [charlieTanker decryptDataFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearData);
        });

        it(@"should wait for the given timeout", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptDataFromData:clearData completionHandler:adapter];
          });

          TKRDecryptionOptions* opts = [TKRDecryptionOptions defaultOptions];
          opts.timeout = 0;

          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptDataFromData:encryptedData options:opts completionHandler:adapter];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorResourceKeyNotFound);
        });
      });

      describe(@"multi devices", ^{
        __block NSString* userID;
        __block NSString* userToken;
        __block TKRTanker* firstDevice;
        __block TKRTanker* secondDevice;

        beforeEach(^{
          firstDevice = [TKRTanker tankerWithOptions:tankerOptions];
          expect(firstDevice).toNot.beNil();

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(trustchainURL, trustchainID)];
          expect(secondDevice).toNot.beNil();

          userID = createUUID();
          userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(firstDevice.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice closeWithCompletionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice closeWithCompletionHandler:resolve];
          });
        });

        it(@"should indicate when an unlock mechanism was set up", ^{
          NSError* err = nil;
          BOOL wasSetUp = [hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice isUnlockAlreadySetUpWithCompletionHandler:adapter];
          }) boolValue];
          expect(wasSetUp).to.equal(NO);

          wasSetUp = [firstDevice hasRegisteredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(NO);

          wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodPassword error:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(NO);

          wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail error:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(NO);

          NSArray* methods = [firstDevice registeredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(methods.count).to.equal(0);

          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:@"password" completionHandler:resolve];
          });
          // ... racy
          sleep(2);

          wasSetUp = [hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice isUnlockAlreadySetUpWithCompletionHandler:adapter];
          }) boolValue];
          expect(wasSetUp).to.equal(YES);

          wasSetUp = [firstDevice hasRegisteredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(YES);

          wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodPassword error:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(YES);

          wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail error:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(NO);

          methods = [firstDevice registeredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(methods.count).to.equal(1);
          expect([methods objectAtIndex:0]).to.equal(TKRUnlockMethodPassword);
        });

        it(@"should open the second device after a setup unlock", ^{
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:@"password" completionHandler:resolve];
          });
          sleep(1);

          [secondDevice connectUnlockRequiredHandler:^(void) {
            // safe to hang, since this is run on a background queue.
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:@"password" completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should open the second device after a register unlock", ^{
          TKRUnlockOptions* opts = [TKRUnlockOptions defaultOptions];
          opts.password = @"password";
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice registerUnlock:opts completionHandler:resolve];
          });
          sleep(1);

          [secondDevice connectUnlockRequiredHandler:^(void) {
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:@"password" completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should setup unlock with an email", ^{
          NSError* err = nil;
          BOOL wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail error:&err];
          expect(err).to.beNil();
          expect(wasSetUp).to.equal(NO);

          NSArray* methods = [firstDevice registeredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(methods.count).to.equal(0);

          TKRUnlockOptions* opts = [TKRUnlockOptions defaultOptions];
          opts.email = @"bob@alice.dk";
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice registerUnlock:opts completionHandler:resolve];
          });

          wasSetUp = [firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail error:&err];
          expect(err).to.beNil();

          expect(wasSetUp).to.equal(YES);
          methods = [firstDevice registeredUnlockMethodsWithError:&err];
          expect(err).to.beNil();
          expect(methods.count).to.equal(1);
          expect([methods objectAtIndex:0]).to.equal(TKRUnlockMethodEmail);
        });

        it(@"should share encrypted data with every accepted device", ^{
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:@"password" completionHandler:resolve];
          });
          sleep(1);
          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:@"password" completionHandler:resolve];
            });
          }];

          NSString* clearText = @"Rosebud";

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          NSData* encryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice encryptDataFromString:clearText completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice decryptStringFromData:encryptedText completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should accept a device with a previously generated unlock key", ^{
          TKRUnlockKey* unlockKey = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice generateAndRegisterUnlockKeyWithCompletionHandler:adapter];
          });
          expect(unlockKey).toNot.beNil();

          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithUnlockKey:unlockKey completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should accept a device with a previously generated password key", ^{
          NSString* password = @"p4ssw0rd";
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:password completionHandler:resolve];
          });

          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:password completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should error when adding a device with an invalid password key", ^{
          NSString* password = @"p4ssw0rd";
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:password completionHandler:resolve];
          });

          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              [secondDevice unlockCurrentDeviceWithPassword:@"invalid"
                                          completionHandler:^(NSError* e) {
                                            err = e;
                                            done();
                                          }];
            }];
            [secondDevice openWithUserID:userID
                               userToken:userToken
                       completionHandler:^(NSError* unused){
                       }];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockPassword);
        });

        it(@"should error when trying to unlock a device and setup has not been done", ^{
          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              [secondDevice unlockCurrentDeviceWithPassword:@"p4ssw0rd"
                                          completionHandler:^(NSError* e) {
                                            err = e;
                                            done();
                                          }];
            }];
            [secondDevice openWithUserID:userID
                               userToken:userToken
                       completionHandler:^(NSError* unused){
                       }];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should update an unlock password", ^{
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:@"password" completionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice updateUnlockPassword:@"new password" completionHandler:resolve];
          });

          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:@"new password" completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should throw when trying to unlock a device and setup has not been done", ^{
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [firstDevice updateUnlockPassword:@"password" completionHandler:resolve];
          });

          expect(err).toNot.beNil();
          expect(err.domain).to.equal(TKRErrorDomain);
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should throw when accepting a device with an invalid unlock key", ^{
          TKRUnlockKey* unlockKey = [TKRUnlockKey unlockKeyFromValue:@"invalid"];
          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              [secondDevice unlockCurrentDeviceWithUnlockKey:unlockKey
                                           completionHandler:^(NSError* e) {
                                             err = e;
                                             done();
                                           }];
            }];
            [secondDevice openWithUserID:userID
                               userToken:userToken
                       completionHandler:^(NSError* unused){
                       }];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should decrypt old resources on second device", ^{
          NSString* password = @"p4ssw0rd";
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice setupUnlockWithPassword:password completionHandler:resolve];
          });

          NSString* clearText = @"Rosebud";
          NSData* encryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice encryptDataFromString:clearText completionHandler:adapter];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [firstDevice closeWithCompletionHandler:resolve];
          });

          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithPassword:password completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice decryptStringFromData:encryptedText completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });
      });

      describe(@"chunk encryptor", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(tanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [tanker closeWithCompletionHandler:resolve];
          });
        });

        it(@"should create a new TKRChunkEncryptor", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          expect(chunkEncryptor.count).to.equal(0);
        });

        it(@"should append a new encrypted chunk from a string and decrypt it", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromString:clearText completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor decryptStringFromData:encryptedChunk atIndex:0 completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
          expect(chunkEncryptor.count).to.equal(1);
        });

        it(@"should append a new encrypted chunk from data and decrypt it", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromData:clearData completionHandler:adapter];
          });
          NSData* decryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor decryptDataFromData:encryptedChunk atIndex:0 completionHandler:adapter];
          });

          expect(decryptedData).to.equal(clearData);
          expect(chunkEncryptor.count).to.equal(1);
        });

        it(@"should encrypt a string at a given index, filling gaps with holes", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromString:clearText atIndex:2 completionHandler:adapter];
          });
          expect(chunkEncryptor.count).to.equal(3);

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor decryptStringFromData:encryptedChunk atIndex:2 completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should encrypt data at a given index, filling gaps with holes", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromData:clearData atIndex:2 completionHandler:adapter];
          });
          expect(chunkEncryptor.count).to.equal(3);

          NSData* decryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor decryptDataFromData:encryptedChunk atIndex:2 completionHandler:adapter];
          });
          expect(decryptedData).to.equal(clearData);
        });

        it(@"should remove chunks at given indexes", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSString* clearText = @"Rosebud";
          NSMutableArray* encryptedChunks = [NSMutableArray arrayWithCapacity:3];

          for (int i = 0; i < 3; ++i)
            encryptedChunks[i] = hangWithAdapter(^(PMKAdapter adapter) {
              [chunkEncryptor encryptDataFromString:clearText completionHandler:adapter];
            });
          expect(chunkEncryptor.count).to.equal(3);

          NSError* err;
          [chunkEncryptor removeAtIndexes:@[ @2, @0, @2 ] error:&err];

          expect(err).to.beNil();
          expect(chunkEncryptor.count).to.equal(1);

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor decryptStringFromData:encryptedChunks[1] atIndex:0 completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should fail to remove out of bounds indexes", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSError* err;

          [chunkEncryptor removeAtIndexes:@[ @0 ] error:&err];
          expect(err).notTo.beNil();
          expect(err.domain).to.equal(TKRErrorDomain);
          expect(err.code).to.equal(TKRErrorChunkIndexOutOfRange);
        });

        it(@"should seal and be able to open from a seal", ^{
          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSString* clearText = @"Rosebud";

          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromString:clearText completionHandler:adapter];
          });
          expect(chunkEncryptor.count).to.equal(1);

          NSData* seal = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor sealWithCompletionHandler:adapter];
          });

          TKRDecryptionOptions* opts = [TKRDecryptionOptions defaultOptions];
          opts.timeout = 0;
          TKRChunkEncryptor* chunkEncryptorBis = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorFromSeal:seal options:opts completionHandler:adapter];
          });
          expect(chunkEncryptorBis.count).to.equal(1);

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptorBis decryptStringFromData:encryptedChunk atIndex:0 completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should share a seal", ^{
          TKRTanker* bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          NSString* bobID = createUUID();
          NSString* bobToken = createUserToken(bobID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker openWithUserID:bobID userToken:bobToken completionHandler:resolve];
          });
          expect(bobTanker.status).to.equal(TKRStatusOpen);

          TKRChunkEncryptor* chunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker makeChunkEncryptorWithCompletionHandler:adapter];
          });

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor encryptDataFromString:clearText completionHandler:adapter];
          });
          expect(chunkEncryptor.count).to.equal(1);

          TKREncryptionOptions* opts = [TKREncryptionOptions defaultOptions];
          opts.shareWithUsers = @[ bobID ];
          NSData* seal = hangWithAdapter(^(PMKAdapter adapter) {
            [chunkEncryptor sealWithOptions:opts completionHandler:adapter];
          });

          TKRChunkEncryptor* bobChunkEncryptor = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker makeChunkEncryptorFromSeal:seal completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [bobChunkEncryptor decryptStringFromData:encryptedChunk atIndex:0 completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });
      });

      describe(@"revocation", ^{
        __block TKRTanker* tanker;
        __block TKRTanker* secondDevice;
        __block NSString* userID;
        __block NSString* userToken;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          userID = createUUID();
          userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(trustchainURL, trustchainID)];
          expect(secondDevice).toNot.beNil();

          hangWithResolver(^(PMKResolver resolve) {
            [tanker openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(tanker.status).to.equal(TKRStatusOpen);

          TKRUnlockKey* unlockKey = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker generateAndRegisterUnlockKeyWithCompletionHandler:adapter];
          });
          expect(unlockKey).toNot.beNil();

          [secondDevice connectUnlockRequiredHandler:^{
            hangWithResolver(^(PMKResolver resolve) {
              [secondDevice unlockCurrentDeviceWithUnlockKey:unlockKey completionHandler:resolve];
            });
          }];

          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice openWithUserID:userID userToken:userToken completionHandler:resolve];
          });
          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          hangWithResolver(^(PMKResolver resolve) {
            [tanker closeWithCompletionHandler:resolve];
          });
          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice closeWithCompletionHandler:resolve];
          });
        });

        it(@"can self revoke", ^{
          __block bool revoked = false;
          NSString* deviceID = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });
          [tanker connectDeviceRevokedHandler:^(void) {
            revoked = true;
          }];
          hangWithResolver(^(PMKResolver resolve) {
            [tanker revokeDevice:deviceID completionHandler:resolve];
          });
          sleep(1);
          expect(tanker.status).to.equal(TKRStatusClosed);
          expect(revoked).to.equal(true);
        });

        it(@"can revoke another device", ^{
          __block bool revoked = false;

          NSString* deviceID = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });
          [tanker connectDeviceRevokedHandler:^(void) {
            revoked = true;
          }];
          hangWithResolver(^(PMKResolver resolve) {
            [secondDevice revokeDevice:deviceID completionHandler:resolve];
          });
          sleep(1);
          expect(tanker.status).to.equal(TKRStatusClosed);
          expect(revoked).to.equal(true);
        });

        it(@"rejects a revocation of another user's device", ^{
          TKRTanker* bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(bobTanker).toNot.beNil();

          NSString* bobID = createUUID();
          NSString* bobToken = createUserToken(bobID, trustchainID, trustchainPrivateKey);

          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker openWithUserID:bobID userToken:bobToken completionHandler:resolve];
          });
          expect(bobTanker.status).to.equal(TKRStatusOpen);

          __block bool revoked = false;
          NSString* deviceID = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });
          [tanker connectDeviceRevokedHandler:^(void) {
            revoked = true;
          }];
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [bobTanker revokeDevice:deviceID completionHandler:resolve];
          });
          sleep(1);

          expect(err.domain).to.equal(TKRErrorDomain);
          expect(err.code).to.equal(TKRErrorDeviceNotFound);

          expect(tanker.status).to.equal(TKRStatusOpen);
          expect(revoked).to.equal(false);

          hangWithResolver(^(PMKResolver resolve) {
            [bobTanker closeWithCompletionHandler:resolve];
          });
        });
      });
    });

SpecEnd
