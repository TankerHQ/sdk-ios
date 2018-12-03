// https://github.com/Specta/Specta

#import "TKRError.h"
#import "TKRTanker.h"
#import "TKRUnlockKey+Private.h"

#import "TKRTestConfig.h"

@import Expecta;
@import Specta;
@import PromiseKit;

#include "tanker.h"
#include "tanker/admin.h"
#include "tanker/user_token.h"

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
  return opts;
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
          [PMKPromise hang:[tanker openWithUserID:userID userToken:userToken]];

          expect(tanker.status).to.equal(TKRStatusOpen);

          [PMKPromise hang:[tanker close]];

          expect(tanker.status).to.equal(TKRStatusClosed);
        });

        it(@"should return a valid base64 string when retrieving the current device id", ^{
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          [PMKPromise hang:[tanker openWithUserID:userID userToken:userToken]];

          NSString* deviceID = [PMKPromise hang:[tanker deviceID]];
          NSData* b64Data = [[NSData alloc] initWithBase64EncodedString:deviceID options:0];

          expect(b64Data).toNot.beNil();

          [PMKPromise hang:[tanker close]];

          NSError* err = [PMKPromise hang:[tanker deviceID]];
          expect(err.domain).to.equal(TKRErrorDomain);

          [PMKPromise hang:[tanker openWithUserID:userID userToken:userToken]];

          NSString* deviceIDBis = [PMKPromise hang:[tanker deviceID]];

          expect(deviceIDBis).to.equal(deviceID);
        });

        it(@"should throw when opening with a wrong user ID", ^{
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);
          NSError* err = [PMKPromise hang:[tanker openWithUserID:@"wrong" userToken:userToken]];

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

          [PMKPromise hang:[tanker openWithUserID:userID userToken:userToken]];
          expect(tanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          [PMKPromise hang:[tanker close]];
        });

        it(@"should decrypt an encrypted string", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = [PMKPromise hang:[tanker encryptDataFromString:clearText]];
          NSString* decryptedText = [PMKPromise hang:[tanker decryptStringFromData:encryptedData]];

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should encrypt temporary strings", ^{
          expect([PMKPromise
                     hang:[tanker decryptStringFromData:[PMKPromise hang:[tanker encryptDataFromString:@"Rosebud"]]]])
              .to.equal(@"Rosebud");
        });

        it(@"should encrypt an empty string", ^{
          NSData* encryptedData = [PMKPromise hang:[tanker encryptDataFromString:@""]];
          NSString* decryptedText = [PMKPromise hang:[tanker decryptStringFromData:encryptedData]];

          expect(decryptedText).to.equal(@"");
        });

        it(@"should decrypt an encrypted data", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];

          NSData* encryptedData = [PMKPromise hang:[tanker encryptDataFromData:clearData]];
          NSData* decryptedData = [PMKPromise hang:[tanker decryptDataFromData:encryptedData]];

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

          [PMKPromise hang:[aliceTanker openWithUserID:aliceID userToken:aliceToken]];
          [PMKPromise hang:[bobTanker openWithUserID:bobID userToken:bobToken]];
          expect(aliceTanker.status).to.equal(TKRStatusOpen);
          expect(bobTanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          [PMKPromise hang:[aliceTanker close]];
          [PMKPromise hang:[bobTanker close]];
        });

        it(@"should create a group with alice and encrypt to her", ^{
          NSString* groupId = [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[ aliceID ]]];
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions defaultOptions];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData =
              [PMKPromise hang:[bobTanker encryptDataFromString:clearText options:encryptionOptions]];
          NSString* decryptedString = [PMKPromise hang:[aliceTanker decryptStringFromData:encryptedData]];
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should create a group with alice and share to her", ^{
          NSString* groupId = [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[ aliceID ]]];
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = [PMKPromise hang:[bobTanker encryptDataFromString:clearText]];

          NSError* err = nil;
          NSString* resourceID = [bobTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithGroups = @[ groupId ];
          [PMKPromise hang:[bobTanker shareResourceIDs:@[ resourceID ] options:opts]];

          NSString* decryptedString = [PMKPromise hang:[aliceTanker decryptStringFromData:encryptedData]];
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should allow bob to decrypt once he's added to the group", ^{
          NSString* groupId = [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[ aliceID ]]];
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions defaultOptions];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData =
              [PMKPromise hang:[aliceTanker encryptDataFromString:clearText options:encryptionOptions]];

          [aliceTanker updateMembersOfGroup:groupId add:@[ bobID ]];

          NSString* decryptedString = [PMKPromise hang:[bobTanker decryptStringFromData:encryptedData]];
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should throw when creating an empty group", ^{
          __block NSError* err = nil;
          [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[]].catch(^(NSError* e) {
            err = e;
          })];

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidGroupSize);
        });

        it(@"should throw when adding 0 members to a group", ^{
          NSString* groupId = [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[ aliceID ]]];

          __block NSError* err = nil;
          [PMKPromise hang:[aliceTanker updateMembersOfGroup:groupId add:@[]].catch(^(NSError* e) {
            err = e;
          })];

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidGroupSize);
        });

        it(@"should throw when adding members to a non-existent group", ^{
          __block NSError* err = nil;
          [PMKPromise
              hang:[aliceTanker updateMembersOfGroup:@"o/Fufh9HZuv5XoZJk5X3ny+4ZeEZegoIEzRjYPP7TX0=" add:@[ bobID ]]
                       .catch(^(NSError* e) {
                         err = e;
                       })];

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorGroupNotFound);
        });

        it(@"should throw when creating a group with non-existing members", ^{
          __block NSError* err = nil;
          [PMKPromise hang:[aliceTanker createGroupWithUserIDs:@[ @"no no no" ]].catch(^(NSError* e) {
            err = e;
          })];

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

          [PMKPromise hang:[aliceTanker openWithUserID:aliceID userToken:aliceToken]];
          [PMKPromise hang:[bobTanker openWithUserID:bobID userToken:bobToken]];
          [PMKPromise hang:[charlieTanker openWithUserID:charlieID userToken:charlieToken]];
          expect(aliceTanker.status).to.equal(TKRStatusOpen);
          expect(bobTanker.status).to.equal(TKRStatusOpen);
          expect(charlieTanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          [PMKPromise hang:[aliceTanker close]];
          [PMKPromise hang:[bobTanker close]];
          [PMKPromise hang:[charlieTanker close]];
        });

        it(@"should return a valid base64 resourceID", ^{
          NSData* encryptedData = [PMKPromise hang:[aliceTanker encryptDataFromString:@"Rosebud"]];
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
          NSData* encryptedData = [PMKPromise hang:[aliceTanker encryptDataFromString:clearText]];
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];

          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID ];
          [PMKPromise hang:[aliceTanker shareResourceIDs:@[ resourceID ] options:opts]];

          NSString* decryptedString = [PMKPromise hang:[bobTanker decryptStringFromData:encryptedData]];
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should share data to multiple users who can decrypt it", ^{
          __block NSString* clearText = @"Rosebud";
          NSArray* encryptPromises =
              @[ [aliceTanker encryptDataFromString:clearText], [aliceTanker encryptDataFromString:clearText] ];
          NSArray* encryptedTexts = [PMKPromise hang:[PMKPromise all:encryptPromises]];

          NSError* err = nil;

          NSString* resourceID1 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[0] error:&err];
          expect(err).to.beNil();
          NSString* resourceID2 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[1] error:&err];
          expect(err).to.beNil();

          NSArray* resourceIDs = @[ resourceID1, resourceID2 ];

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID, charlieID ];
          [PMKPromise hang:[aliceTanker shareResourceIDs:resourceIDs options:opts]];

          NSArray* decryptPromises = @[
            [bobTanker decryptStringFromData:encryptedTexts[0]],
            [bobTanker decryptStringFromData:encryptedTexts[1]],
            [charlieTanker decryptStringFromData:encryptedTexts[0]],
            [charlieTanker decryptStringFromData:encryptedTexts[1]]
          ];
          NSArray* decryptedTexts = [PMKPromise hang:[PMKPromise all:decryptPromises]];

          [decryptedTexts enumerateObjectsUsingBlock:^(NSString* decryptedText, NSUInteger index, BOOL* stop) {
            expect(decryptedText).to.equal(clearText);
          }];
        });

        it(@"should have no effect to share to nobody", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = [PMKPromise hang:[aliceTanker encryptDataFromString:clearText]];
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          id value = [PMKPromise hang:[aliceTanker shareResourceIDs:@[ resourceID ] options:opts]];
          expect(value).toNot.beKindOf([NSError class]);
        });

        it(@"should have no effect to share nothing", ^{
          TKRShareOptions* opts = [TKRShareOptions defaultOptions];
          opts.shareWithUsers = @[ bobID, charlieID ];
          id value = [PMKPromise hang:[aliceTanker shareResourceIDs:@[] options:opts]];
          expect(value).toNot.beKindOf([NSError class]);
        });

        it(@"should share directly when encrypting a string", ^{
          NSString* clearText = @"Rosebud";
          encryptionOptions.shareWithUsers = @[ bobID, charlieID ];
          NSData* encryptedData =
              [PMKPromise hang:[aliceTanker encryptDataFromString:clearText options:encryptionOptions]];

          NSString* decryptedText = [PMKPromise hang:[bobTanker decryptStringFromData:encryptedData]];
          expect(decryptedText).to.equal(clearText);
          decryptedText = [PMKPromise hang:[charlieTanker decryptStringFromData:encryptedData]];
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should share directly when encrypting data", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          encryptionOptions.shareWithUsers = @[ bobID, charlieID ];
          NSData* encryptedData =
              [PMKPromise hang:[aliceTanker encryptDataFromData:clearData options:encryptionOptions]];

          NSData* decryptedData = [PMKPromise hang:[bobTanker decryptDataFromData:encryptedData]];
          expect(decryptedData).to.equal(clearData);
          decryptedData = [PMKPromise hang:[charlieTanker decryptDataFromData:encryptedData]];
          expect(decryptedData).to.equal(clearData);
        });

        it(@"should wait for the given timeout", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          NSData* encryptedData = [PMKPromise hang:[aliceTanker encryptDataFromData:clearData]];

          TKRDecryptionOptions* opts = [TKRDecryptionOptions defaultOptions];
          opts.timeout = 0;
          NSError* err = [PMKPromise hang:[bobTanker decryptDataFromData:encryptedData options:opts]];
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorResourceKeyNotFound);

          err = [PMKPromise hang:[bobTanker decryptStringFromData:encryptedData options:opts]];

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
          [PMKPromise hang:[firstDevice openWithUserID:userID userToken:userToken]];
          expect(firstDevice.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          [PMKPromise hang:[firstDevice close]];
          [PMKPromise hang:[secondDevice close]];
        });

        it(@"should indicate when an unlock mechanism was set up", ^{
          NSNumber* wasSetUp = [PMKPromise hang:[firstDevice isUnlockAlreadySetUp]];
          expect(wasSetUp).to.equal(@NO);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethods]];
          expect(wasSetUp).to.equal(@NO);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodPassword]];
          expect(wasSetUp).to.equal(@NO);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail]];
          expect(wasSetUp).to.equal(@NO);
          NSArray* methods = [PMKPromise hang:[firstDevice registeredUnlockMethods]];
          expect([methods count]).to.equal(0);

          [PMKPromise hang:[firstDevice setupUnlockWithPassword:@"password"]];
          // ... racy
          sleep(2);

          wasSetUp = [PMKPromise hang:[firstDevice isUnlockAlreadySetUp]];
          expect(wasSetUp).to.equal(@YES);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethods]];
          expect(wasSetUp).to.equal(@YES);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodPassword]];
          expect(wasSetUp).to.equal(@YES);
          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail]];
          expect(wasSetUp).to.equal(@NO);
          methods = [PMKPromise hang:[firstDevice registeredUnlockMethods]];
          expect([methods count]).to.equal(1);
          expect([methods objectAtIndex:0]).to.equal(TKRUnlockMethodPassword);
        });

        it(@"should open the second device after a setup unlock", ^{
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:@"password"]];
          sleep(1);

          [secondDevice connectUnlockRequiredHandler:^(void) {
            // safe to hang, since this is run on a background queue.
            [PMKPromise hang:[secondDevice unlockCurrentDeviceWithPassword:@"password"]];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];
          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should open the second device after a register unlock", ^{
          TKRUnlockOptions* opts = [TKRUnlockOptions defaultOptions];
          opts.password = @"password";
          [PMKPromise hang:[firstDevice registerUnlock:opts]];
          sleep(1);

          [secondDevice connectUnlockRequiredHandler:^(void) {
            // must not hang here, it would block tconcurrent's thread
            [secondDevice unlockCurrentDeviceWithPassword:@"password"];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];
          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should setup unlock with an email", ^{
          NSNumber* wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail]];
          expect(wasSetUp).to.equal(@NO);
          NSArray* methods = [PMKPromise hang:[firstDevice registeredUnlockMethods]];
          expect([methods count]).to.equal(0);

          TKRUnlockOptions* opts = [TKRUnlockOptions defaultOptions];
          opts.email = @"bob@alice.dk";
          [PMKPromise hang:[firstDevice registerUnlock:opts]];

          wasSetUp = [PMKPromise hang:[firstDevice hasRegisteredUnlockMethod:TKRUnlockMethodEmail]];
          expect(wasSetUp).to.equal(@YES);
          methods = [PMKPromise hang:[firstDevice registeredUnlockMethods]];
          expect([methods count]).to.equal(1);
          expect([methods objectAtIndex:0]).to.equal(TKRUnlockMethodEmail);
        });

        it(@"should share encrypted data with every accepted device", ^{
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:@"password"]];
          sleep(1);
          [secondDevice connectUnlockRequiredHandler:^{
            [secondDevice unlockCurrentDeviceWithPassword:@"password"];
          }];

          NSString* clearText = @"Rosebud";

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];
          NSData* encryptedText = [PMKPromise hang:[secondDevice encryptDataFromString:clearText]];

          NSString* decryptedText = [PMKPromise hang:[firstDevice decryptStringFromData:encryptedText]];
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should accept a device with a previously generated unlock key", ^{
          TKRUnlockKey* unlockKey = [PMKPromise hang:[firstDevice generateAndRegisterUnlockKey]];
          expect(unlockKey).toNot.beNil();

          [secondDevice connectUnlockRequiredHandler:^{
            [secondDevice unlockCurrentDeviceWithUnlockKey:unlockKey];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should accept a device with a previously generated password key", ^{
          NSString* password = @"p4ssw0rd";
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:password]];

          [secondDevice connectUnlockRequiredHandler:^{
            [secondDevice unlockCurrentDeviceWithPassword:password];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should throw when adding a device with an invalid password key", ^{
          NSString* password = @"p4ssw0rd";
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:password]];

          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              NSString* invalidPassword = @"invalid";
              [secondDevice unlockCurrentDeviceWithPassword:invalidPassword].catch(^(NSError* e) {
                err = e;
                done();
              });
            }];
            [secondDevice openWithUserID:userID userToken:userToken];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockPassword);
        });

        it(@"should throw when trying to unlock a device and setup has not been done", ^{
          NSString* password = @"p4ssw0rd";

          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              [secondDevice unlockCurrentDeviceWithPassword:password].catch(^(NSError* e) {
                err = e;
                done();
              });
            }];
            [secondDevice openWithUserID:userID userToken:userToken];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should update an unlock password", ^{
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:@"password"]];

          [PMKPromise hang:[firstDevice updateUnlockPassword:@"new password"]];

          [secondDevice connectUnlockRequiredHandler:^{
            [secondDevice unlockCurrentDeviceWithPassword:@"new password"];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];

          expect(secondDevice.status).to.equal(TKRStatusOpen);
        });

        it(@"should throw when trying to unlock a device and setup has not been done", ^{
          NSError* err = [PMKPromise hang:[firstDevice updateUnlockPassword:@"password"]];

          expect(err).toNot.beNil();
          expect(err.domain).to.equal(TKRErrorDomain);
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should throw when accepting a device with an invalid unlock key", ^{
          TKRUnlockKey* unlockKey = [TKRUnlockKey unlockKeyFromValue:@"invalid"];
          __block NSError* err = nil;
          waitUntil(^(DoneCallback done) {
            [secondDevice connectUnlockRequiredHandler:^{
              [secondDevice unlockCurrentDeviceWithUnlockKey:unlockKey].catch(^(NSError* e) {
                err = e;
                done();
              });
            }];
            [secondDevice openWithUserID:userID userToken:userToken];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidUnlockKey);
        });

        it(@"should decrypt old resources on second device", ^{
          NSString* password = @"p4ssw0rd";
          [PMKPromise hang:[firstDevice setupUnlockWithPassword:password]];

          NSString* clearText = @"Rosebud";
          NSData* encryptedData = [PMKPromise hang:[firstDevice encryptDataFromString:clearText]];
          [PMKPromise hang:[firstDevice close]];

          [secondDevice connectUnlockRequiredHandler:^{
            [secondDevice unlockCurrentDeviceWithPassword:password];
          }];

          [PMKPromise hang:[secondDevice openWithUserID:userID userToken:userToken]];
          NSString* decryptedText = [PMKPromise hang:[secondDevice decryptStringFromData:encryptedData]];
          expect(decryptedText).to.equal(clearText);
        });
      });

      describe(@"chunk encryptor", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          NSString* userID = createUUID();
          NSString* userToken = createUserToken(userID, trustchainID, trustchainPrivateKey);

          [PMKPromise hang:[tanker openWithUserID:userID userToken:userToken]];
          expect(tanker.status).to.equal(TKRStatusOpen);
        });

        afterEach(^{
          [PMKPromise hang:[tanker close]];
        });

        it(@"should create a new TKRChunkEncryptor", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          expect(chunkEncryptor.count).to.equal(0);
        });

        it(@"should append a new encrypted chunk from a string and decrypt it", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromString:clearText]];
          NSString* decryptedText = [PMKPromise hang:[chunkEncryptor decryptStringFromData:encryptedChunk atIndex:0]];

          expect(decryptedText).to.equal(clearText);
          expect(chunkEncryptor.count).to.equal(1);
        });

        it(@"should append a new encrypted chunk from data and decrypt it", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromData:clearData]];
          NSData* decryptedData = [PMKPromise hang:[chunkEncryptor decryptDataFromData:encryptedChunk atIndex:0]];

          expect(decryptedData).to.equal(clearData);
          expect(chunkEncryptor.count).to.equal(1);
        });

        it(@"should encrypt a string at a given index, filling gaps with holes", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromString:clearText atIndex:2]];
          expect(chunkEncryptor.count).to.equal(3);

          NSString* decryptedText = [PMKPromise hang:[chunkEncryptor decryptStringFromData:encryptedChunk atIndex:2]];
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should encrypt data at a given index, filling gaps with holes", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromData:clearData atIndex:2]];
          expect(chunkEncryptor.count).to.equal(3);

          NSData* decryptedData = [PMKPromise hang:[chunkEncryptor decryptDataFromData:encryptedChunk atIndex:2]];
          expect(decryptedData).to.equal(clearData);
        });

        it(@"should remove chunks at given indexes", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSString* clearText = @"Rosebud";
          NSMutableArray* encryptedChunks = [NSMutableArray arrayWithCapacity:3];

          for (int i = 0; i < 3; ++i)
            encryptedChunks[i] = [PMKPromise hang:[chunkEncryptor encryptDataFromString:clearText]];
          expect(chunkEncryptor.count).to.equal(3);

          [PMKPromise hang:[chunkEncryptor removeAtIndexes:@[ @2, @0, @2 ]]];

          expect(chunkEncryptor.count).to.equal(1);

          NSString* decryptedText =
              [PMKPromise hang:[chunkEncryptor decryptStringFromData:encryptedChunks[1] atIndex:0]];
          expect(decryptedText).to.equal(clearText);
        });

        it(@"should fail to remove out of bounds indexes", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSError* err = [PMKPromise hang:[chunkEncryptor removeAtIndexes:@[ @0 ]]];

          expect(err.domain).to.equal(TKRErrorDomain);
          expect(err.code).to.equal(TKRErrorChunkIndexOutOfRange);
        });

        it(@"should seal and be able to open from a seal", ^{
          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromString:clearText]];
          expect(chunkEncryptor.count).to.equal(1);

          NSData* seal = [PMKPromise hang:[chunkEncryptor seal]];

          TKRDecryptionOptions* opts = [TKRDecryptionOptions defaultOptions];
          opts.timeout = 0;
          TKRChunkEncryptor* chunkEncryptorBis =
              [PMKPromise hang:[tanker makeChunkEncryptorFromSeal:seal options:opts]];
          expect(chunkEncryptorBis.count).to.equal(1);

          NSString* decryptedText =
              [PMKPromise hang:[chunkEncryptorBis decryptStringFromData:encryptedChunk atIndex:0]];

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should share a seal", ^{
          TKRTanker* bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          NSString* bobID = createUUID();
          NSString* bobToken = createUserToken(bobID, trustchainID, trustchainPrivateKey);

          [PMKPromise hang:[bobTanker openWithUserID:bobID userToken:bobToken]];
          expect(bobTanker.status).to.equal(TKRStatusOpen);

          TKRChunkEncryptor* chunkEncryptor = [PMKPromise hang:[tanker makeChunkEncryptor]];

          NSString* clearText = @"Rosebud";
          NSData* encryptedChunk = [PMKPromise hang:[chunkEncryptor encryptDataFromString:clearText]];
          expect(chunkEncryptor.count).to.equal(1);

          TKREncryptionOptions* opts = [TKREncryptionOptions defaultOptions];
          opts.shareWithUsers = @[ bobID ];
          NSData* seal = [PMKPromise hang:[chunkEncryptor sealWithOptions:opts]];

          TKRChunkEncryptor* bobChunkEncryptor = [PMKPromise hang:[bobTanker makeChunkEncryptorFromSeal:seal]];
          NSString* decryptedText =
              [PMKPromise hang:[bobChunkEncryptor decryptStringFromData:encryptedChunk atIndex:0]];

          expect(decryptedText).to.equal(clearText);
        });
      });
    });

SpecEnd
