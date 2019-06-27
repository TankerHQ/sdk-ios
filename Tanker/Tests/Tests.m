// https://github.com/Specta/Specta

#import "TKRError.h"
#import "TKRTanker.h"
#import "TKRTankerOptions+Private.h"
#import "TKRVerification.h"
#import "TKRVerificationKey.h"

#import "TKRTestConfig.h"

@import Expecta;
@import Specta;
@import PromiseKit;

#include "ctanker.h"
#include "ctanker/admin.h"
#include "ctanker/identity.h"

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

NSString* createIdentity(NSString* userID, NSString* trustchainID, NSString* trustchainPrivateKey)
{
  char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* trustchain_id = [trustchainID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* trustchain_priv_key = [trustchainPrivateKey cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* identity_expected = tanker_create_identity(trustchain_id, trustchain_priv_key, user_id);
  char* identity = unwrapAndFreeExpected(identity_expected);
  assert(identity);
  return [[NSString alloc] initWithBytesNoCopy:identity
                                        length:strlen(identity)
                                      encoding:NSUTF8StringEncoding
                                  freeWhenDone:YES];
}

NSString* getPublicIdentity(NSString* identity)
{
  tanker_expected_t* identity_expected =
      tanker_get_public_identity([identity cStringUsingEncoding:NSUTF8StringEncoding]);

  char* public_identity = unwrapAndFreeExpected(identity_expected);
  assert(public_identity);
  return [[NSString alloc] initWithBytesNoCopy:public_identity
                                        length:strlen(public_identity)
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

      __block void (^startWithIdentity)(TKRTanker*, NSString*) = ^(TKRTanker* tanker, NSString* identity) {
        NSError* err = hangWithResolver(^(PMKResolver resolver) {
          [tanker startWithIdentity:identity
                  completionHandler:^(TKRStatus status, NSError* err) {
                    if (!err)
                      expect(status).to.equal(TKRStatusReady);
                    resolver(err);
                  }];
        });
        expect(err).to.beNil();
      };

      __block void (^startWithIdentityAndRegister)(TKRTanker*, NSString*, TKRVerification*) =
          ^(TKRTanker* tanker, NSString* identity, TKRVerification* verification) {
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [tanker startWithIdentity:identity
                      completionHandler:^(TKRStatus status, NSError* err) {
                        if (err)
                          resolver(err);
                        else
                        {
                          expect(status).to.equal(TKRStatusIdentityRegistrationNeeded);
                          [tanker registerIdentityWithVerification:verification completionHandler:resolver];
                        }
                      }];
            });
            expect(err).to.beNil();
          };

      __block TKRVerificationKey* (^startWithIdentityAndRegisterVerificationKey)(TKRTanker*, NSString*) =
          ^(TKRTanker* tanker, NSString* identity) {
            TKRVerificationKey* verificationKey = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker startWithIdentity:identity
                      completionHandler:^(TKRStatus status, NSError* err) {
                        if (err)
                          adapter(nil, err);
                        else
                        {
                          expect(status).to.equal(TKRStatusIdentityRegistrationNeeded);
                          [tanker generateVerificationKeyWithCompletionHandler:adapter];
                        }
                      }];
            });
            expect(verificationKey).toNot.beNil();
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [tanker registerIdentityWithVerification:[TKRVerification verificationFromVerificationKey:verificationKey]
                                     completionHandler:resolver];
            });
            expect(err).to.beNil();
            return verificationKey;
          };

      __block void (^startWithIdentityAndVerify)(TKRTanker*, NSString*, TKRVerification*) =
          ^(TKRTanker* tanker, NSString* identity, TKRVerification* verification) {
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [tanker startWithIdentity:identity
                      completionHandler:^(TKRStatus status, NSError* err) {
                        if (err)
                          resolver(err);
                        else
                        {
                          expect(status).to.equal(TKRStatusIdentityVerificationNeeded);
                          [tanker verifyIdentityWithVerification:verification completionHandler:resolver];
                        }
                      }];
            });
            expect(err).to.beNil();
          };

      __block void (^stop)(TKRTanker*) = ^(TKRTanker* tanker) {
        hangWithResolver(^(PMKResolver resolve) {
          [tanker stopWithCompletionHandler:resolve];
        });
      };

      __block NSString* (^getVerificationCode)(NSString*) = ^(NSString* email) {
        tanker_future_t* f =
            tanker_admin_get_verification_code(admin,
                                               [trustchainID cStringUsingEncoding:NSUTF8StringEncoding],
                                               [email cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(f);
        char* code = (char*)tanker_future_get_voidptr(f);
        NSString* ret = [NSString stringWithCString:code encoding:NSUTF8StringEncoding];
        free(code);
        return ret;
      };

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
        __block NSString* identity;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          identity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
        });

        it(@"should return TKRStatusIdentityRegistrationNeeded when start is called for the first time", ^{
          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          stop(tanker);
        });

        it(@"should return TKRStatusReady when start is called after identity has been registered", ^{
          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          stop(tanker);
          startWithIdentity(tanker, identity);
          stop(tanker);
        });

        it(@"should return a valid base64 string when retrieving the current device id", ^{
          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          NSString* deviceID = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker deviceIDWithCompletionHandler:adapter];
          });

          NSData* b64Data = [[NSData alloc] initWithBase64EncodedString:deviceID options:0];
          expect(b64Data).toNot.beNil();

          stop(tanker);
        });
      });

      describe(@"crypto", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          NSString* identity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        afterEach(^{
          stop(tanker);
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
        __block NSString* aliceIdentity;
        __block NSString* alicePublicIdentity;
        __block NSString* bobIdentity;
        __block NSString* bobPublicIdentity;

        beforeEach(^{
          aliceTanker = [TKRTanker tankerWithOptions:tankerOptions];
          bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(aliceTanker).toNot.beNil();
          expect(bobTanker).toNot.beNil();

          aliceIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          bobIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          alicePublicIdentity = getPublicIdentity(aliceIdentity);
          bobPublicIdentity = getPublicIdentity(bobIdentity);

          startWithIdentityAndRegister(
              aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndRegister(
              bobTanker, bobIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        afterEach(^{
          stop(aliceTanker);
          stop(bobTanker);
        });

        it(@"should create a group with alice and encrypt to her", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
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
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptDataFromString:clearText completionHandler:adapter];
          });

          NSError* err = nil;
          NSString* resourceID = [bobTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRShareOptions* opts = [TKRShareOptions options];
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
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptDataFromString:clearText completionHandler:adapter];
          });

          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId usersToAdd:@[ bobIdentity ] completionHandler:resolve];
          });

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should error when creating an empty group", ^{
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[] completionHandler:adapter];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should error when adding 0 members to a group", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity ] completionHandler:adapter];
          });

          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId usersToAdd:@[] completionHandler:resolve];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should error when adding members to a non-existent group", ^{
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:@"o/Fufh9HZuv5XoZJk5X3ny+4ZeEZegoIEzRjYPP7TX0="
                                   usersToAdd:@[ bobPublicIdentity ]
                            completionHandler:resolve];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should error when creating a group with non-existing members", ^{
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[ @"no no no" ] completionHandler:adapter];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });
      });

      describe(@"share", ^{
        __block TKRTanker* aliceTanker;
        __block TKRTanker* bobTanker;
        __block TKRTanker* charlieTanker;
        __block NSString* aliceIdentity;
        __block NSString* bobIdentity;
        __block NSString* charlieIdentity;
        __block NSString* alicePublicIdentity;
        __block NSString* bobPublicIdentity;
        __block NSString* charliePublicIdentity;
        __block TKREncryptionOptions* encryptionOptions;

        beforeEach(^{
          aliceTanker = [TKRTanker tankerWithOptions:tankerOptions];
          bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          charlieTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(aliceTanker).toNot.beNil();
          expect(bobTanker).toNot.beNil();
          expect(charlieTanker).toNot.beNil();
          encryptionOptions = [TKREncryptionOptions options];

          aliceIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          bobIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          charlieIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          alicePublicIdentity = getPublicIdentity(aliceIdentity);
          bobPublicIdentity = getPublicIdentity(bobIdentity);
          charliePublicIdentity = getPublicIdentity(charlieIdentity);

          startWithIdentityAndRegister(
              aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndRegister(
              bobTanker, bobIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndRegister(
              charlieTanker, charlieIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        afterEach(^{
          stop(aliceTanker);
          stop(bobTanker);
          stop(charlieTanker);
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

          TKRShareOptions* opts = [TKRShareOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
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

          TKRShareOptions* opts = [TKRShareOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity, charliePublicIdentity ];
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

          TKRShareOptions* opts = [TKRShareOptions options];
          err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });
          expect(err).beNil();
        });

        it(@"should have no effect to share nothing", ^{
          TKRShareOptions* opts = [TKRShareOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity, charliePublicIdentity ];
          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[] options:opts completionHandler:resolve];
          });
          expect(err).to.beNil();
        });

        it(@"should share directly when encrypting a string", ^{
          NSString* clearText = @"Rosebud";
          encryptionOptions.shareWithUsers = @[ bobPublicIdentity, charliePublicIdentity ];

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
          encryptionOptions.shareWithUsers = @[ bobPublicIdentity, charliePublicIdentity ];
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
      });

      describe(@"multi devices", ^{
        __block NSString* identity;
        __block TKRTanker* firstDevice;
        __block TKRTanker* secondDevice;

        beforeEach(^{
          firstDevice = [TKRTanker tankerWithOptions:tankerOptions];
          expect(firstDevice).toNot.beNil();

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(trustchainURL, trustchainID)];
          expect(secondDevice).toNot.beNil();

          identity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
        });

        afterEach(^{
          stop(firstDevice);
          stop(secondDevice);
        });

        it(@"should return TKRStatusIdentityVerificationNeeded when starting on a new device", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        it(@"should setup verification with an email", ^{
          NSString* email = @"bob@alice.dk";
          startWithIdentityAndRegister(
              firstDevice,
              identity,
              [TKRVerification verificationFromEmail:email verificationCode:getVerificationCode(email)]);

          NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice verificationMethodsWithCompletionHandler:adapter];
          });
          expect(methods.count).to.equal(1);
          expect(methods[0].type).to.equal(TKRVerificationMethodTypeEmail);
          expect(methods[0].email).to.equal(email);
        });

        it(@"should share encrypted data with every accepted device", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSString* clearText = @"Rosebud";

          NSData* encryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice encryptDataFromString:clearText completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice decryptStringFromData:encryptedText completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should fail to generate a verification key when a previous verification method was set", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice generateVerificationKeyWithCompletionHandler:adapter];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorPreconditionFailed);
        });

        it(@"should accept a device with a previously generated verification key", ^{
          TKRVerificationKey* verificationKey = startWithIdentityAndRegisterVerificationKey(firstDevice, identity);

          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromVerificationKey:verificationKey]);
        });

        it(@"should fail to set a verification method if a verification key was generated", ^{
          startWithIdentityAndRegisterVerificationKey(firstDevice, identity);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromPassphrase:@"fail"]
                             completionHandler:resolver];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorPreconditionFailed);
        });

        it(@"should error when adding a device with an invalid passphrase", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice startWithIdentity:identity
                          completionHandler:^(TKRStatus status, NSError* err) {
                            if (err)
                              resolver(err);
                            else
                            {
                              expect(status).to.equal(TKRStatusIdentityVerificationNeeded);
                              [secondDevice
                                  verifyIdentityWithVerification:[TKRVerification verificationFromPassphrase:@"fail"]
                                               completionHandler:resolver];
                            }
                          }];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidVerification);
        });

        it(@"should update a verification passphrase", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromPassphrase:@"new passphrase"]
                             completionHandler:resolver];
          });
          expect(err).to.beNil();

          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"new passphrase"]);
        });

        it(@"should throw when verifying an identity with an invalid verification key", ^{
          startWithIdentityAndRegisterVerificationKey(firstDevice, identity);
          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice
                startWithIdentity:identity
                completionHandler:^(TKRStatus status, NSError* err) {
                  if (err)
                    resolver(err);
                  else
                  {
                    expect(status).to.equal(TKRStatusIdentityVerificationNeeded);
                    [secondDevice
                        verifyIdentityWithVerification:
                            [TKRVerification
                                verificationFromVerificationKey:[TKRVerificationKey verificationKeyFromValue:@"fail"]]
                                     completionHandler:resolver];
                  }
                }];
          });

          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidVerification);
        });

        it(@"should decrypt old resources on second device", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSString* clearText = @"Rosebud";
          NSData* encryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice encryptDataFromString:clearText completionHandler:adapter];
          });
          stop(firstDevice);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice decryptStringFromData:encryptedText completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });
      });

      describe(@"revocation", ^{
        __block TKRTanker* tanker;
        __block TKRTanker* secondDevice;
        __block NSString* userID;
        __block NSString* identity;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          userID = createUUID();
          identity = createIdentity(userID, trustchainID, trustchainPrivateKey);

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(trustchainURL, trustchainID)];
          expect(secondDevice).toNot.beNil();

          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        afterEach(^{
          stop(tanker);
          stop(secondDevice);
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
          expect(revoked).to.equal(true);
        });

        it(@"rejects a revocation of another user's device", ^{
          TKRTanker* bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(bobTanker).toNot.beNil();

          NSString* bobIdentity = createIdentity(createUUID(), trustchainID, trustchainPrivateKey);
          startWithIdentityAndRegister(
              bobTanker, bobIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

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
          expect(err.code).to.equal(TKRErrorInvalidArgument);
          expect(revoked).to.equal(false);

          stop(bobTanker);
        });
      });
    });

SpecEnd
