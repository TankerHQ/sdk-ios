// https://github.com/Specta/Specta

#import <Tanker/TKRAttachResult.h>
#import <Tanker/TKREncryptionSession.h>
#import <Tanker/TKRError.h>
#import <Tanker/TKRInputStreamDataSource+Private.h>
#import <Tanker/TKRPadding.h>
#import <Tanker/TKRTanker.h>
#import <Tanker/TKRTankerOptions.h>
#import <Tanker/TKRVerification.h>
#import <Tanker/TKRVerificationKey.h>

#import <Tanker/Utils/TKRUtils.h>

#import <Tanker/Storage/TKRDatastore.h>
#import <Tanker/Storage/TKRDatastoreBindings.h>
#import <Tanker/Storage/TKRDatastoreError.h>

#import "TKRCustomDataSource.h"
#import "TKRTestAsyncStreamReader.h"

#import <Expecta/Expecta.h>
#import <POSInputStreamLibrary/POSInputStreamLibrary.h>
#import <PromiseKit/PromiseKit.h>
#import <Specta/Specta.h>

#include "ctanker.h"
#include "ctanker/admin.h"
#include "ctanker/identity.h"
#include "ctanker/private/datastore-tests/test.h"

static NSString* createIdentity(NSString* userID, NSString* appID, NSString* appSecret)
{
  char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* app_id = [appID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* app_secret = [appSecret cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* identity_expected = tanker_create_identity(app_id, app_secret, user_id);
  char* identity = TKR_unwrapAndFreeExpected(identity_expected);
  assert(identity);
  return [[NSString alloc] initWithBytesNoCopy:identity
                                        length:strlen(identity)
                                      encoding:NSUTF8StringEncoding
                                  freeWhenDone:YES];
}

static NSString* createProvisionalIdentity(NSString* appID, NSString* email)
{
  char const* app_id = [appID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* c_email = [email cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* provisional_expected = tanker_create_provisional_identity(app_id, c_email);
  char* identity = TKR_unwrapAndFreeExpected(provisional_expected);
  assert(identity);
  return [[NSString alloc] initWithBytesNoCopy:identity
                                        length:strlen(identity)
                                      encoding:NSUTF8StringEncoding
                                  freeWhenDone:YES];
}

static NSString* getPublicIdentity(NSString* identity)
{
  tanker_expected_t* identity_expected =
      tanker_get_public_identity([identity cStringUsingEncoding:NSUTF8StringEncoding]);

  char* public_identity = TKR_unwrapAndFreeExpected(identity_expected);
  assert(public_identity);
  return [[NSString alloc] initWithBytesNoCopy:public_identity
                                        length:strlen(public_identity)
                                      encoding:NSUTF8StringEncoding
                                  freeWhenDone:YES];
}

static NSString* createUUID()
{
  return [[NSUUID UUID] UUIDString];
}

static NSString* createStorageFullpath(NSSearchPathDirectory dir)
{
  NSArray* paths = NSSearchPathForDirectoriesInDomains(dir, NSUserDomainMask, YES);
  NSString* path = [[paths objectAtIndex:0] stringByAppendingPathComponent:createUUID()];
  NSError* err;
  BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&err];
  assert(success);
  return path;
}

static TKRTankerOptions* createTankerOptions(NSString* url, NSString* appID)
{
  TKRTankerOptions* opts = [TKRTankerOptions options];
  opts.url = url;
  opts.appID = appID;
  opts.persistentPath = createStorageFullpath(NSLibraryDirectory);
  opts.cachePath = createStorageFullpath(NSCachesDirectory);
  opts.sdkType = @"sdk-ios-tests";
  return opts;
}

static void updateAdminApp(tanker_admin_t* admin,
                           NSString* appID,
                           NSString* oidcClientID,
                           NSString* oidcClientProvider,
                           bool* enablePreverifiedVerification)
{
  char const* app_id = [appID cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_app_update_options_t options = TANKER_APP_UPDATE_OPTIONS_INIT;
  options.preverified_verification = enablePreverifiedVerification;
  if (oidcClientID)
    options.oidc_client_id = [oidcClientID cStringUsingEncoding:NSUTF8StringEncoding];
  if (oidcClientProvider)
    options.oidc_client_provider = [oidcClientProvider cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* update_fut = tanker_admin_app_update(admin, app_id, &options);
  tanker_future_wait(update_fut);
  tanker_future_destroy(update_fut);
}

static NSDictionary* sendOidcRequest(NSString* oidcClientId, NSString* oidcClientSecret, NSString* refreshToken)
{
  NSMutableURLRequest* req =
      [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v4/token"]];
  [req setHTTPMethod:@"POST"];
  [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];
  NSDictionary* obj = @{
    @"client_id" : oidcClientId,
    @"client_secret" : oidcClientSecret,
    @"grant_type" : @"refresh_token",
    @"refresh_token" : refreshToken
  };
  req.HTTPBody = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  NSURLSession* session = [NSURLSession sharedSession];
  PMKPromise* prom = [PMKPromise promiseWithResolver:^(PMKResolver resolve) {
    NSURLSessionDataTask* dataTask =
        [session dataTaskWithRequest:req
                   completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                     NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
                     if (httpResponse.statusCode == 200)
                     {
                       NSError* parseError = nil;
                       NSDictionary* responseDictionary = [NSJSONSerialization JSONObjectWithData:data
                                                                                          options:0
                                                                                            error:&parseError];
                       if (parseError)
                         resolve(parseError);
                       else
                         resolve(responseDictionary);
                     }
                   }];
    [dataTask resume];
  }];
  return [PMKPromise hang:prom];
}

static id hangWithAdapter(void (^handler)(PMKAdapter))
{
  return [PMKPromise hang:[PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
                       handler(adapter);
                     }]];
}

static id hangWithResolver(void (^handler)(PMKResolver))
{
  return [PMKPromise hang:[PMKPromise promiseWithResolver:^(PMKResolver resolve) {
                       handler(resolve);
                     }]];
}

static NSData* _Nonnull stringToData(NSString* _Nonnull str)
{
  return [NSData dataWithBytes:str.UTF8String length:str.length];
}

static NSUInteger SIMPLE_ENCRYPTION_OVERHEAD = 17;
static NSUInteger SIMPLE_PADDED_ENCRYPTION_OVERHEAD = SIMPLE_ENCRYPTION_OVERHEAD + 1;
static NSUInteger ENCRYPTION_SESSION_OVERHEAD = 57;
static NSUInteger ENCRYPTION_SESSION_PADDED_OVERHEAD = ENCRYPTION_SESSION_OVERHEAD + 1;

SpecBegin(TankerSpecs)

    describe(@"Tanker Bindings", ^{
      __block tanker_admin_t* admin;
      __block NSString* url;
      __block NSString* trustchaindUrl;
      __block char const* curl;
      __block char const* ctrustchaindurl;
      __block NSString* appID;
      __block NSString* appSecret;
      __block NSDictionary* oidcTestConfig;
      __block NSString* verificationToken;

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
        expect(tanker.status).to.equal(TKRStatusReady);
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
                          expect(tanker.status).to.equal(TKRStatusIdentityRegistrationNeeded);
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
                          expect(tanker.status).to.equal(TKRStatusIdentityRegistrationNeeded);
                          [tanker generateVerificationKeyWithCompletionHandler:adapter];
                        }
                      }];
            });
            expect(verificationKey).toNot.beNil();
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [tanker registerIdentityWithVerification:[TKRVerification verificationFromVerificationKey:verificationKey]
                                     completionHandler:resolver];
            });
            expect(tanker.status).to.equal(TKRStatusReady);
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
                          expect(tanker.status).to.equal(TKRStatusIdentityVerificationNeeded);
                          [tanker verifyIdentityWithVerification:verification completionHandler:resolver];
                        }
                      }];
            });
            expect(err).to.beNil();
          };

      __block void (^stop)(TKRTanker*) = ^(TKRTanker* tanker) {
        NSError* err = hangWithResolver(^(PMKResolver resolve) {
          [tanker stopWithCompletionHandler:resolve];
        });
        expect(err).to.beNil();
        expect(tanker.status).to.equal(TKRStatusStopped);
      };

      __block NSString* (^getEmailVerificationCode)(NSString*) = ^(NSString* email) {
        tanker_future_t* f =
            tanker_get_email_verification_code(ctrustchaindurl,
                                               [appID cStringUsingEncoding:NSUTF8StringEncoding],
                                               [verificationToken cStringUsingEncoding:NSUTF8StringEncoding],
                                               [email cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(f);
        char* code = (char*)tanker_future_get_voidptr(f);
        NSString* ret = [NSString stringWithCString:code encoding:NSUTF8StringEncoding];
        free(code);
        return ret;
      };

      __block NSString* (^getSMSVerificationCode)(NSString*) = ^(NSString* phoneNumber) {
        tanker_future_t* f =
            tanker_get_sms_verification_code(ctrustchaindurl,
                                             [appID cStringUsingEncoding:NSUTF8StringEncoding],
                                             [verificationToken cStringUsingEncoding:NSUTF8StringEncoding],
                                             [phoneNumber cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(f);
        char* code = (char*)tanker_future_get_voidptr(f);
        NSString* ret = [NSString stringWithCString:code encoding:NSUTF8StringEncoding];
        free(code);
        return ret;
      };

      beforeAll(^{
        NSDictionary* env = [[NSProcessInfo processInfo] environment];
        NSString* appManagementToken = env[@"TANKER_MANAGEMENT_API_ACCESS_TOKEN"];
        expect(appManagementToken).toNot.beNil();
        NSString* appManagementUrl = env[@"TANKER_MANAGEMENT_API_URL"];
        expect(appManagementUrl).toNot.beNil();
        NSString* environmentName = env[@"TANKER_MANAGEMENT_API_DEFAULT_ENVIRONMENT_NAME"];
        expect(environmentName).toNot.beNil();
        trustchaindUrl = env[@"TANKER_TRUSTCHAIND_URL"];
        expect(trustchaindUrl).toNot.beNil();
        url = env[@"TANKER_APPD_URL"];
        expect(url).toNot.beNil();
        verificationToken = env[@"TANKER_VERIFICATION_API_TEST_TOKEN"];
        expect(verificationToken).toNot.beNil();

        oidcTestConfig = @{
          @"clientId" : env[@"TANKER_OIDC_CLIENT_ID"],
          @"clientSecret" : env[@"TANKER_OIDC_CLIENT_SECRET"],
          @"provider" : env[@"TANKER_OIDC_PROVIDER"],
          @"users" : @{
            @"martine" : @{
              @"email" : env[@"TANKER_OIDC_MARTINE_EMAIL"],
              @"refreshToken" : env[@"TANKER_OIDC_MARTINE_REFRESH_TOKEN"]
            }
          }
        };

        curl = [url cStringUsingEncoding:NSUTF8StringEncoding];
        ctrustchaindurl = [trustchaindUrl cStringUsingEncoding:NSUTF8StringEncoding];
        char const* cappManagementToken = [appManagementToken cStringUsingEncoding:NSUTF8StringEncoding];
        char const* cappManagementUrl = [appManagementUrl cStringUsingEncoding:NSUTF8StringEncoding];
        char const* cenvironmentName = [environmentName cStringUsingEncoding:NSUTF8StringEncoding];
        tanker_future_t* connect_fut = tanker_admin_connect(cappManagementUrl, cappManagementToken, cenvironmentName);
        tanker_future_wait(connect_fut);
        NSError* connectError = TKR_getOptionalFutureError(connect_fut);
        expect(connectError).to.beNil();
        admin = (tanker_admin_t*)tanker_future_get_voidptr(connect_fut);
        tanker_future_destroy(connect_fut);
        tanker_future_t* app_fut = tanker_admin_create_app(admin, "ios-test");
        tanker_future_wait(app_fut);
        NSError* createError = TKR_getOptionalFutureError(app_fut);
        expect(createError).to.beNil();
        tanker_app_descriptor_t* app = (tanker_app_descriptor_t*)tanker_future_get_voidptr(app_fut);
        appID = [NSString stringWithCString:app->id encoding:NSUTF8StringEncoding];
        appSecret = [NSString stringWithCString:app->private_key encoding:NSUTF8StringEncoding];
        tanker_future_destroy(app_fut);
        tanker_admin_app_descriptor_free(app);
      });

      afterAll(^{
        tanker_future_t* delete_fut = tanker_admin_delete_app(admin, [appID cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(delete_fut);
        NSError* error = TKR_getOptionalFutureError(delete_fut);
        expect(error).to.beNil();

        tanker_future_t* admin_destroy_fut = tanker_admin_destroy(admin);
        tanker_future_wait(admin_destroy_fut);
        error = TKR_getOptionalFutureError(admin_destroy_fut);
        expect(error).to.beNil();
      });

      beforeEach(^{
        tankerOptions = createTankerOptions(url, appID);
      });

      describe(@"prehashPassword", ^{
        it(@"should fail to hash an empty password", ^{
          expect(^{
            [TKRTanker prehashPassword:@""];
          }).to.raise(NSInvalidArgumentException);
        });

        it(@"should hash a test vector 1", ^{
          NSString* input = @"super secretive password";
          NSString* expected = @"UYNRgDLSClFWKsJ7dl9uPJjhpIoEzadksv/Mf44gSHI=";
          NSString* hashed = [TKRTanker prehashPassword:input];
          expect(hashed).to.equal(expected);
        });

        it(@"should hash a test vector 2", ^{
          NSString* input = @"test éå 한국어 😃";
          NSString* expected = @"Pkn/pjub2uwkBDpt2HUieWOXP5xLn0Zlen16ID4C7jI=";
          NSString* hashed = [TKRTanker prehashPassword:input];
          expect(hashed).to.equal(expected);
        });
      });

      describe(@"init", ^{
        it(@"should throw when AppID is not base64", ^{
          tankerOptions.appID = @",,";
          expect(^{
            [TKRTanker tankerWithOptions:tankerOptions];
          }).to.raise(NSInvalidArgumentException);
        });
      });

      describe(@"open", ^{
        __block TKRTanker* tanker;
        __block NSString* identity;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          identity = createIdentity(createUUID(), appID, appSecret);
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

        it(@"should be able to stop tanker while a call is in flight", ^{
          // This test tries to cancel an on-going HTTP request. There is no
          // assertion, it's just a best effort to check that we won't crash
          // because of some use-after-free.

          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          // trigger an encrypt and do not wait
          [tanker encryptString:@"Rosebud"
              completionHandler:^(NSData* _Nullable encryptedData, NSError* _Nullable err){
              }];

          stop(tanker);
        });
      });

      describe(@"http", ^{
        it(@"reports http errors correctly", ^{
          // This error should be reported before any network call
          tankerOptions.url = @"this is not an url at all";
          TKRTanker* tanker = [TKRTanker tankerWithOptions:tankerOptions];
          NSString* identity = createIdentity(createUUID(), appID, appSecret);
          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [tanker startWithIdentity:identity
                    completionHandler:^(TKRStatus status, NSError* err) {
                      resolver(err);
                    }];
          });
          expect(err).notTo.beNil();
          expect(err.code).to.equal(TKRErrorNetworkError);
        });
      });

      describe(@"provisional identity", ^{
        __block TKRTanker* aliceTanker;
        __block NSString* aliceIdentity;
        __block NSString* aliceEmail = @"alice@email.com";
        __block TKRTanker* bobTanker;
        __block NSString* bobIdentity;

        beforeEach(^{
          aliceTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(aliceTanker).toNot.beNil();
          aliceIdentity = createIdentity(createUUID(), appID, appSecret);
          bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(bobTanker).toNot.beNil();
          bobIdentity = createIdentity(createUUID(), appID, appSecret);
        });

        afterEach(^{
          stop(aliceTanker);
          stop(bobTanker);
        });

        it(@"should attach and verify a provisional identity", ^{
          startWithIdentityAndRegister(
              aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          __block NSString* provIdentity = createProvisionalIdentity(appID, aliceEmail);
          TKRAttachResult* result = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          expect(result.status).to.equal(TKRStatusIdentityVerificationNeeded);
          expect(result.method.type).to.equal(TKRVerificationMethodTypeEmail);
          expect(result.method.email).to.equal(aliceEmail);

          TKRVerification* verif = [TKRVerification verificationFromEmail:aliceEmail
                                                         verificationCode:getEmailVerificationCode(aliceEmail)];
          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [aliceTanker verifyProvisionalIdentityWithVerification:verif completionHandler:resolver];
          });
          expect(err).to.beNil();

          result = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          expect(result.status).to.equal(TKRStatusReady);
        });

        it(@"should fail to attach an already attached identity", ^{
          startWithIdentityAndRegister(
              aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          __block NSString* provIdentity = createProvisionalIdentity(appID, aliceEmail);
          hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          TKRVerification* aliceVerif = [TKRVerification verificationFromEmail:aliceEmail
                                                              verificationCode:getEmailVerificationCode(aliceEmail)];
          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [aliceTanker verifyProvisionalIdentityWithVerification:aliceVerif completionHandler:resolver];
          });
          expect(err).to.beNil();

          // try to attach/verify with Bob now
          startWithIdentityAndRegister(
              bobTanker, bobIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          TKRVerification* bobVerif = [TKRVerification verificationFromEmail:aliceEmail
                                                            verificationCode:getEmailVerificationCode(aliceEmail)];
          TKRAttachResult* result = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          expect(result.status).to.equal(TKRStatusIdentityVerificationNeeded);
          err = hangWithResolver(^(PMKResolver resolver) {
            [bobTanker verifyProvisionalIdentityWithVerification:bobVerif completionHandler:resolver];
          });
          expect(err).notTo.beNil();
          expect(err.code).to.equal(TKRErrorIdentityAlreadyAttached);
        });
      });

      describe(@"crypto", ^{
        __block TKRTanker* tanker;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          NSString* identity = createIdentity(createUUID(), appID, appSecret);
          startWithIdentityAndRegister(tanker, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
        });

        afterEach(^{
          stop(tanker);
        });

        it(@"should decrypt an encrypted string", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptString:clearText completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedText).to.equal(clearText);
        });

        it(@"should encrypt an empty string", ^{
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptString:@"" completionHandler:adapter];
          });
          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedText).to.equal(@"");
        });

        it(@"should decrypt an encrypted data", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptData:clearData completionHandler:adapter];
          });
          NSData* decryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker decryptData:encryptedData completionHandler:adapter];
          });

          expect(decryptedData).to.equal(clearData);
        });

        describe(@"padding", ^{
          it(@"should encrypt and decrypt with auto padding by default", ^{
            NSString* clearText = @"my clear data is clear!";
            int lengthWithPadme = 24;

            NSData* encrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptString:clearText completionHandler:adapter];
            });

            expect(encrypted.length - SIMPLE_PADDED_ENCRYPTION_OVERHEAD).to.equal(lengthWithPadme);

            NSString* decrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStringFromData:encrypted completionHandler:adapter];
            });

            expect(decrypted).to.equal(clearText);
          });

          it(@"should encrypt and decrypt with auto padding", ^{
            NSString* clearText = @"my clear data is clear!";
            int lengthWithPadme = 24;

            TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
            encryptionOptions.paddingStep = [TKRPadding automatic];

            NSData* encrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
            });

            expect(encrypted.length - SIMPLE_PADDED_ENCRYPTION_OVERHEAD).to.equal(lengthWithPadme);

            NSString* decrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStringFromData:encrypted completionHandler:adapter];
            });

            expect(decrypted).to.equal(clearText);
          });

          it(@"should encrypt and decrypt with no padding", ^{
            NSString* clearText = @"Rosebud";

            TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
            encryptionOptions.paddingStep = [TKRPadding off];

            NSData* encrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
            });

            expect(encrypted.length - SIMPLE_ENCRYPTION_OVERHEAD).to.equal(clearText.length);

            NSString* decrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStringFromData:encrypted completionHandler:adapter];
            });

            expect(decrypted).to.equal(clearText);
          });

          it(@"should encrypt and decrypt with manual padding", ^{
            NSString* clearText = @"Rosebud";
            NSNumber* paddingStep = @13;

            TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
            encryptionOptions.paddingStep = [TKRPadding step:paddingStep];

            NSData* encrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
            });

            expect((encrypted.length - SIMPLE_PADDED_ENCRYPTION_OVERHEAD) % paddingStep.unsignedIntValue).to.equal(0);

            NSString* decrypted = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStringFromData:encrypted completionHandler:adapter];
            });

            expect(decrypted).to.equal(clearText);
          });

          it(@"should throw when a bad step is given", ^{
            expect(^{
                    [TKRPadding step:@-1];
            }).to.raise(NSInvalidArgumentException);
            expect(^{
                    [TKRPadding step:@0];
            }).to.raise(NSInvalidArgumentException);
            expect(^{
                    [TKRPadding step:@1];
            }).to.raise(NSInvalidArgumentException);
          });
        });

        describe(@"streams", ^{
          __block NSData* clearData;
          __block TKRCustomDataSource* dataSource;
          __block TKRTestAsyncStreamReader* reader;

          beforeEach(^{
            clearData = [NSMutableData dataWithLength:1024 * 1024 * 2 + 4];
            dataSource = [TKRCustomDataSource customDataSourceWithData:clearData];
            reader = [[TKRTestAsyncStreamReader alloc] init];
          });

          it(@"should decrypt an encrypted stream", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];
            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStream:encryptedStream completionHandler:adapter];
            });

            NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];

            expect(decryptedData).to.equal(clearData);
          });

          it(@"should encrypt a stream with padding", ^{
            clearData = [NSMutableData dataWithLength:1024 * 1024 * 3 + 2];
            dataSource = [TKRCustomDataSource customDataSourceWithData:clearData];
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });
            [encryptedStream open];

            NSData* encryptedData = [PMKPromise hang:[reader readAll:encryptedStream]];
            expect(encryptedData.length).to.equal(3211512);
            NSInputStream* encryptedInput = [[POSBlobInputStream alloc] initWithDataSource:encryptedData];

            NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStream:encryptedInput completionHandler:adapter];
            });

            NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];

            expect(decryptedData).to.equal(clearData);
          });

          it(@"should fail to read when maxLength is superior to NSIntegerMax", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            [encryptedStream open];
            NSMutableData* buffer = [NSMutableData dataWithLength:4096];
            NSInteger nbRead = [encryptedStream read:buffer.mutableBytes maxLength:-1];

            expect(nbRead).to.equal(-1);
            expect(encryptedStream.streamError).toNot.beNil();
            NSError* underlyingError = encryptedStream.streamError.userInfo[NSUnderlyingErrorKey];

            expect(underlyingError.code).to.equal(TKRErrorInvalidArgument);
            expect(underlyingError.domain).to.equal(TKRErrorDomain);
          });

          it(@"should read a stream asynchronously", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStream:encryptedStream completionHandler:adapter];
            });

            NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];

            expect(decryptedData).to.equal(clearData);
          });

          it(@"should read a slow stream asynchronously", ^{
            dataSource.isSlow = YES;

            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker decryptStream:encryptedStream completionHandler:adapter];
            });

            TKRTestAsyncStreamReader* reader = [[TKRTestAsyncStreamReader alloc] init];
            NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];

            expect(decryptedData).to.equal(clearData);
          });

          it(@"should err when asynchronously reading a stream fails", ^{
            dataSource.willErr = YES;

            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            TKRTestAsyncStreamReader* reader = [[TKRTestAsyncStreamReader alloc] init];
            NSError* err = [PMKPromise hang:[reader readAll:encryptedStream]];

            expect(err).toNot.beNil();
            expect(err.domain).to.equal(@"com.github.pavelosipov.POSBlobInputStreamErrorDomain");
            NSError* underlyingError = err.userInfo[NSUnderlyingErrorKey];
            NSError* tankerError = underlyingError.userInfo[NSUnderlyingErrorKey];
            expect(underlyingError).to.equal(clearStream.streamError);
            expect(tankerError.domain).to.equal(@"TKRTestErrorDomain");
          });

          it(@"should err when asynchronously reading a slow stream fails", ^{
            dataSource.isSlow = YES;
            dataSource.willErr = YES;

            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            TKRTestAsyncStreamReader* reader = [[TKRTestAsyncStreamReader alloc] init];
            NSError* err = [PMKPromise hang:[reader readAll:encryptedStream]];

            expect(err).toNot.beNil();
            expect(err.domain).to.equal(@"com.github.pavelosipov.POSBlobInputStreamErrorDomain");
            NSError* underlyingError = err.userInfo[NSUnderlyingErrorKey];
            NSError* tankerError = underlyingError.userInfo[NSUnderlyingErrorKey];
            expect(underlyingError).to.equal(clearStream.streamError);
            expect(tankerError.domain).to.equal(@"TKRTestErrorDomain");
          });

          it(@"should return the correct hasBytesAvailable value", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            expect(encryptedStream.hasBytesAvailable).to.equal(NO);
            [encryptedStream open];

            // consume data
            [PMKPromise hang:[reader readAll:encryptedStream]];
            expect(encryptedStream.hasBytesAvailable).to.equal(NO);
          });

          it(@"should fail to process an already open stream", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];
            [clearStream open];
            NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });

            expect(err).toNot.beNil();
            expect(err.domain).to.equal(TKRErrorDomain);
            expect(err.code).to.equal(TKRErrorInvalidArgument);
          });

          it(@"does not support getBuffer function", ^{
            NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];
            NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
              [tanker encryptStream:clearStream completionHandler:adapter];
            });
            uint8_t* buf = nil;
            NSUInteger len = 0;
            BOOL isBufferAvailable = [encryptedStream getBuffer:&buf length:&len];
            expect(isBufferAvailable).to.equal(NO);
          });
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

          aliceIdentity = createIdentity(createUUID(), appID, appSecret);
          bobIdentity = createIdentity(createUUID(), appID, appSecret);
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
            [bobTanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
          });
          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should create a group with alice and share with her", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity ] completionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker encryptString:clearText completionHandler:adapter];
          });

          NSError* err = nil;
          NSString* resourceID = [bobTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRSharingOptions* opts = [TKRSharingOptions options];
          opts.shareWithGroups = @[ groupId ];
          err = hangWithResolver(^(PMKResolver resolve) {
            [bobTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });
          expect(err).to.beNil();

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
            [aliceTanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
          });

          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId usersToAdd:@[ bobPublicIdentity ] completionHandler:resolve];
          });
          expect(err).to.beNil();

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should be able to remove bob from the group", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createGroupWithIdentities:@[ alicePublicIdentity, bobPublicIdentity ]
                                 completionHandler:adapter];
          });

          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker updateMembersOfGroup:groupId
                                   usersToAdd:@[]
                                usersToRemove:@[ bobPublicIdentity ]
                            completionHandler:resolve];
          });
          expect(err).to.beNil();

          NSString* clearText = @"Rosebud";
          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
          encryptionOptions.shareWithGroups = @[ groupId ];
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
          });

          err = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should throw when updating a group without modification", ^{
          NSString* groupId = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker createGroupWithIdentities:@[ bobPublicIdentity ] completionHandler:adapter];
          });

          NSError* err = hangWithResolver(^(PMKResolver resolve) {
            [bobTanker updateMembersOfGroup:groupId usersToAdd:@[] usersToRemove:@[] completionHandler:resolve];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
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

      describe(@"encryptionSession", ^{
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

          aliceIdentity = createIdentity(createUUID(), appID, appSecret);
          bobIdentity = createIdentity(createUUID(), appID, appSecret);
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

        it(@"should be able to share with an encryption session", ^{
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });
          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should be able to share with an encryption session, but not with self", ^{
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          opts.shareWithSelf = false;
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });
          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);

          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should be able to encrypt streams with an encryption session", ^{
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });

          NSData* clearData = [NSMutableData dataWithLength:1024 * 1024 * 2 + 4];
          TKRCustomDataSource* dataSource = [TKRCustomDataSource customDataSourceWithData:clearData];
          TKRTestAsyncStreamReader* reader = [[TKRTestAsyncStreamReader alloc] init];
          NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];

          NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptStream:clearStream completionHandler:adapter];
          });

          NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStream:encryptedStream completionHandler:adapter];
          });
          NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];
          expect(decryptedData).to.equal(clearData);
        });

        it(@"should have a matching resource ID for the session and ciphertexts", ^{
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });

          NSError* err = nil;
          NSString* cipherResourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();
          NSString* sessResourceID = [encSess resourceID];
          expect(sessResourceID).to.equal(cipherResourceID);
        });

        it(@"should encrypt with auto padding by default", ^{
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter];
          });
          NSString* clearText = @"my clear data is clear!";
          int lengthWithPadme = 24;

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });

          expect(encryptedData.length - ENCRYPTION_SESSION_PADDED_OVERHEAD).to.equal(lengthWithPadme);

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should encrypt with auto padding", ^{
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.paddingStep = [TKRPadding automatic];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });
          NSString* clearText = @"my clear data is clear!";
          int lengthWithPadme = 24;

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });

          expect(encryptedData.length - ENCRYPTION_SESSION_PADDED_OVERHEAD).to.equal(lengthWithPadme);

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedString).to.equal(clearText);
        });

        it(@"should encrypt with no padding", ^{
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.paddingStep = [TKRPadding off];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });

          expect(encryptedData.length - ENCRYPTION_SESSION_OVERHEAD).to.equal(clearText.length);

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedString).to.equal(clearText);
        });

        it(@"should encrypt with a padding step", ^{
          NSNumber* paddingStep = @13;
          TKREncryptionOptions* opts = [TKREncryptionOptions options];
          opts.paddingStep = [TKRPadding step:paddingStep];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter encryptionOptions:opts];
          });
          NSString* clearText = @"Rosebud";

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [encSess encryptString:clearText completionHandler:adapter];
          });

          expect((encryptedData.length - ENCRYPTION_SESSION_PADDED_OVERHEAD) % paddingStep.unsignedIntValue).to.equal(0);

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedString).to.equal(clearText);
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

          aliceIdentity = createIdentity(createUUID(), appID, appSecret);
          bobIdentity = createIdentity(createUUID(), appID, appSecret);
          charlieIdentity = createIdentity(createUUID(), appID, appSecret);
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
            [aliceTanker encryptString:@"Rosebud" completionHandler:adapter];
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
            [aliceTanker encryptString:clearText completionHandler:adapter];
          });
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];

          expect(err).to.beNil();

          TKRSharingOptions* opts = [TKRSharingOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });
          expect(err).to.beNil();

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(decryptedString).to.equal(clearText);
        });

        it(@"should share a stream with Bob who can decrypt it", ^{
          NSData* clearData = [@"Rosebud" dataUsingEncoding:NSUTF8StringEncoding];
          TKRCustomDataSource* dataSource = [TKRCustomDataSource customDataSourceWithData:clearData];
          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
          encryptionOptions.shareWithUsers = @[ bobPublicIdentity ];

          NSInputStream* clearStream = [[POSBlobInputStream alloc] initWithDataSource:dataSource];
          NSInputStream* encryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptStream:clearStream options:encryptionOptions completionHandler:adapter];
          });

          NSInputStream* decryptedStream = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStream:encryptedStream completionHandler:adapter];
          });

          TKRTestAsyncStreamReader* reader = [[TKRTestAsyncStreamReader alloc] init];
          NSData* decryptedData = [PMKPromise hang:[reader readAll:decryptedStream]];
          NSString* decryptedString = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];

          expect(decryptedString).to.equal(@"Rosebud");
        });

        it(@"should encrypt a string for Bob, but not for Alice", ^{
          NSString* clearString = @"Rosebud";
          TKREncryptionOptions* encryptionOptions = [TKREncryptionOptions options];
          encryptionOptions.shareWithSelf = false;
          encryptionOptions.shareWithUsers = @[ bobPublicIdentity ];

          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptString:clearString options:encryptionOptions completionHandler:adapter];
          });

          NSString* decryptedString = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });

          expect(decryptedString).to.equal(clearString);

          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker decryptStringFromData:encryptedData completionHandler:adapter];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });

        it(@"should share data to multiple users who can decrypt it", ^{
          __block NSString* clearText = @"Rosebud";
          NSArray* encryptPromises = @[
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [aliceTanker encryptString:clearText completionHandler:adapter];
            }],
            [PMKPromise promiseWithAdapter:^(PMKAdapter adapter) {
              [aliceTanker encryptString:clearText completionHandler:adapter];
            }]
          ];
          NSArray* encryptedTexts = [PMKPromise hang:[PMKPromise all:encryptPromises]];

          NSError* err = nil;

          NSString* resourceID1 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[0] error:&err];
          expect(err).to.beNil();
          NSString* resourceID2 = [aliceTanker resourceIDOfEncryptedData:encryptedTexts[1] error:&err];
          expect(err).to.beNil();

          NSArray* resourceIDs = @[ resourceID1, resourceID2 ];

          TKRSharingOptions* opts = [TKRSharingOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity, charliePublicIdentity ];
          err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:resourceIDs options:opts completionHandler:resolve];
          });
          expect(err).to.beNil();

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

        it(@"should have no effect to share with nobody", ^{
          NSString* clearText = @"Rosebud";
          NSData* encryptedData = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker encryptString:clearText completionHandler:adapter];
          });
          NSError* err = nil;
          NSString* resourceID = [aliceTanker resourceIDOfEncryptedData:encryptedData error:&err];
          expect(err).to.beNil();

          TKRSharingOptions* opts = [TKRSharingOptions options];
          err = hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });
          expect(err).beNil();
        });

        it(@"should have no effect to share nothing", ^{
          TKRSharingOptions* opts = [TKRSharingOptions options];
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
            [aliceTanker encryptString:clearText options:encryptionOptions completionHandler:adapter];
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
            [aliceTanker encryptData:clearData options:encryptionOptions completionHandler:adapter];
          });

          NSData* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [bobTanker decryptData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearData);
          decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [charlieTanker decryptData:encryptedData completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearData);
        });
      });

      describe(@"e2e passphrase", ^{
        __block NSString* identity;
        __block TKRTanker* firstDevice;
        __block TKRTanker* secondDevice;

        beforeEach(^{
          firstDevice = [TKRTanker tankerWithOptions:tankerOptions];
          expect(firstDevice).toNot.beNil();

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
          expect(secondDevice).toNot.beNil();

          identity = createIdentity(createUUID(), appID, appSecret);
        });

        afterEach(^{
          stop(firstDevice);
          stop(secondDevice);
        });

        it(@"should register an e2e passphrase", ^{
          NSString* e2ePassphrase = @"Hear the lament of the damned, cursed to write Objective-C";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromE2ePassphrase:e2ePassphrase]);

          NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice verificationMethodsWithCompletionHandler:adapter];
          });
          expect(methods.count).to.equal(1);
          expect(methods[0].type).to.equal(TKRVerificationMethodTypeE2ePassphrase);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice startWithIdentity:identity
                          completionHandler:^(TKRStatus status, NSError* err) {
                            if (err)
                              resolver(err);
                            else
                            {
                              expect(status).to.equal(TKRStatusIdentityVerificationNeeded);
                              [secondDevice
                                  verifyIdentityWithVerification:[TKRVerification verificationFromE2ePassphrase:e2ePassphrase]
                                               completionHandler:resolver];
                            }
                          }];
          });
          expect(err).to.beNil();
        });

        it(@"should update an e2e passphrase", ^{
          NSString* oldPassphrase = @"Malumosis";
          NSString* newPassphrase = @"Aerugopenia";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromE2ePassphrase:oldPassphrase]);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromE2ePassphrase:newPassphrase]
                             completionHandler:resolver];
          });
          expect(err).to.beNil();

          hangWithResolver(^(PMKResolver resolver) {
            [secondDevice startWithIdentity:identity
                          completionHandler:^(TKRStatus status, NSError* err) {
                            resolver(nil);
                          }];
          });
          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromE2ePassphrase:oldPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidVerification);

          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromE2ePassphrase:newPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).to.beNil();
        });

        it(@"should switch to an e2e passphrase", ^{
          NSString* oldPassphrase = @"Malumosis";
          NSString* newPassphrase = @"Aerugopenia";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromPassphrase:oldPassphrase]);

          TKRVerificationOptions* opts = [TKRVerificationOptions options];
          opts.allowE2eMethodSwitch = true;
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromE2ePassphrase:newPassphrase]
                                       options:opts
                             completionHandler:adapter];
          });
          expect(err).to.beNil();

          hangWithResolver(^(PMKResolver resolver) {
            [secondDevice startWithIdentity:identity
                          completionHandler:^(TKRStatus status, NSError* err) {
                            resolver(nil);
                          }];
          });
          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromPassphrase:oldPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorPreconditionFailed);

          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromE2ePassphrase:newPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).to.beNil();
        });

        it(@"should switch from an e2e passphrase", ^{
          NSString* oldPassphrase = @"Malumosis";
          NSString* newPassphrase = @"Aerugopenia";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromE2ePassphrase:oldPassphrase]);

          TKRVerificationOptions* opts = [TKRVerificationOptions options];
          opts.allowE2eMethodSwitch = true;
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromPassphrase:newPassphrase]
                                       options:opts
                             completionHandler:adapter];
          });
          expect(err).to.beNil();

          hangWithResolver(^(PMKResolver resolver) {
            [secondDevice startWithIdentity:identity
                          completionHandler:^(TKRStatus status, NSError* err) {
                            resolver(nil);
                          }];
          });
          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromE2ePassphrase:oldPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorPreconditionFailed);

          err = hangWithResolver(^(PMKResolver resolver) {
            [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromPassphrase:newPassphrase]
                                       completionHandler:resolver];
          });
          expect(err).to.beNil();
        });

        it(@"cannot switch to an e2e passphrase without allowE2eMethodSwitch flag", ^{
          NSString* oldPassphrase = @"Malumosis";
          NSString* newPassphrase = @"Aerugopenia";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromPassphrase:oldPassphrase]);

          NSError* err = hangWithResolver(^(PMKResolver resolver) {
            [firstDevice setVerificationMethod:[TKRVerification verificationFromE2ePassphrase:newPassphrase]
                             completionHandler:resolver];
          });
          expect(err).toNot.beNil();
          expect(err.code).to.equal(TKRErrorInvalidArgument);
        });
      });

      describe(@"multi devices", ^{
        __block NSString* identity;
        __block TKRTanker* firstDevice;
        __block TKRTanker* secondDevice;

        beforeEach(^{
          firstDevice = [TKRTanker tankerWithOptions:tankerOptions];
          expect(firstDevice).toNot.beNil();

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
          expect(secondDevice).toNot.beNil();

          identity = createIdentity(createUUID(), appID, appSecret);
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
          NSString* email = @"bob.alice@tanker.io";
          startWithIdentityAndRegister(firstDevice,
                                       identity,
                                       [TKRVerification verificationFromEmail:email
                                                             verificationCode:getEmailVerificationCode(email)]);

          NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice verificationMethodsWithCompletionHandler:adapter];
          });
          expect(methods.count).to.equal(1);
          expect(methods[0].type).to.equal(TKRVerificationMethodTypeEmail);
          expect(methods[0].email).to.equal(email);
        });

        it(@"should setup verification with an SMS", ^{
          NSString* phoneNumber = @"+33639982233";
          startWithIdentityAndRegister(
              firstDevice,
              identity,
              [TKRVerification verificationFromPhoneNumber:phoneNumber
                                          verificationCode:getSMSVerificationCode(phoneNumber)]);

          NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
            [firstDevice verificationMethodsWithCompletionHandler:adapter];
          });
          expect(methods.count).to.equal(1);
          expect(methods[0].type).to.equal(TKRVerificationMethodTypePhoneNumber);
          expect(methods[0].phoneNumber).to.equal(phoneNumber);
        });

        it(@"should setup verification with an OIDC ID Token", ^{
          NSString* oidcClientID = oidcTestConfig[@"clientId"];
          NSString* oidcClientSecret = oidcTestConfig[@"clientSecret"];
          NSString* oidcClientProvider = oidcTestConfig[@"provider"];

          NSString* userName = @"martine";
          NSString* email = oidcTestConfig[@"users"][userName][@"email"];
          NSString* refreshToken = oidcTestConfig[@"users"][userName][@"refreshToken"];

          updateAdminApp(admin, appID, oidcClientID, oidcClientProvider, nil);
          TKRTanker* userPhone = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
          NSString* userIdentity = createIdentity(email, appID, appSecret);

          NSDictionary* jsonResponse = sendOidcRequest(oidcClientID, oidcClientSecret, refreshToken);
          NSString* oidcToken = jsonResponse[@"id_token"];
          TKRVerification* oidcVerif = [TKRVerification verificationFromOIDCIDToken:oidcToken];

          NSString* nonce = hangWithAdapter(^(PMKAdapter adapter) {
            [userPhone createOidcNonceWithCompletionHandler:adapter];
          });
          hangWithResolver(^(PMKResolver resolver) {
            [userPhone setOidcTestNonce:nonce completionHandler:resolver];
          });
          startWithIdentityAndRegister(userPhone, userIdentity, oidcVerif);
          stop(userPhone);

          TKRTanker* userLaptop = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
          nonce = hangWithAdapter(^(PMKAdapter adapter) {
            [userLaptop createOidcNonceWithCompletionHandler:adapter];
          });
          hangWithResolver(^(PMKResolver resolver) {
            [userLaptop setOidcTestNonce:nonce completionHandler:resolver];
          });
          startWithIdentityAndVerify(userLaptop, userIdentity, oidcVerif);

          NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
            [userLaptop verificationMethodsWithCompletionHandler:adapter];
          });
          expect(methods.count).to.equal(1);
          expect(methods[0].type).to.equal(TKRVerificationMethodTypeOIDCIDToken);
          stop(userLaptop);
        });

        it(@"should share encrypted data with every accepted device", ^{
          startWithIdentityAndRegister(
              firstDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSString* clearText = @"Rosebud";

          NSData* encryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice encryptString:clearText completionHandler:adapter];
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
            [firstDevice encryptString:clearText completionHandler:adapter];
          });
          stop(firstDevice);
          startWithIdentityAndVerify(
              secondDevice, identity, [TKRVerification verificationFromPassphrase:@"passphrase"]);

          NSString* decryptedText = hangWithAdapter(^(PMKAdapter adapter) {
            [secondDevice decryptStringFromData:encryptedText completionHandler:adapter];
          });
          expect(decryptedText).to.equal(clearText);
        });

        describe(@"Preverified verification methods", ^{
          beforeAll(^{
            bool enablePreverified = true;
            updateAdminApp(admin, appID, nil, nil, &enablePreverified);
          });
          afterAll(^{
            bool enablePreverified = false;
            updateAdminApp(admin, appID, nil, nil, &enablePreverified);
          });

          it(@"should fail to register with a preverified email", ^{
            NSString* email = @"bob.alice@tanker.io";
            TKRVerification* verification = [TKRVerification verificationFromPreverifiedEmail:email];
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [firstDevice startWithIdentity:identity
                           completionHandler:^(TKRStatus status, NSError* err) {
                             if (err)
                               resolver(err);
                             else
                             {
                               [firstDevice registerIdentityWithVerification:verification completionHandler:resolver];
                             }
                           }];
            });
            expect(err).toNot.beNil();
            expect(err.code).to.equal(TKRErrorInvalidArgument);
          });

          it(@"should fail to register with a preverified phone number", ^{
            NSString* phoneNumber = @"+33639982233";
            TKRVerification* verification = [TKRVerification verificationFromPreverifiedPhoneNumber:phoneNumber];
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [firstDevice startWithIdentity:identity
                           completionHandler:^(TKRStatus status, NSError* err) {
                             if (err)
                               resolver(err);
                             else
                             {
                               [firstDevice registerIdentityWithVerification:verification completionHandler:resolver];
                             }
                           }];
            });
            expect(err).toNot.beNil();
            expect(err.code).to.equal(TKRErrorInvalidArgument);
          });

          it(@"should register with an email and fail to verify a preverified email", ^{
            NSString* email = @"bob.alice@tanker.io";
            startWithIdentityAndRegister(firstDevice,
                                         identity,
                                         [TKRVerification verificationFromEmail:email
                                                               verificationCode:getEmailVerificationCode(email)]);
            hangWithResolver(^(PMKResolver resolver) {
              [secondDevice startWithIdentity:identity
                            completionHandler:^(TKRStatus status, NSError* err) {
                              resolver(nil);
                            }];
            });
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [secondDevice verifyIdentityWithVerification:[TKRVerification verificationFromPreverifiedEmail:email]
                                         completionHandler:resolver];
            });
            expect(err).toNot.beNil();
            expect(err.code).to.equal(TKRErrorInvalidArgument);
          });

          it(@"should register with a phone number and fail to verify a preverified phone number", ^{
            NSString* phoneNumber = @"+33639982233";
            startWithIdentityAndRegister(
                firstDevice,
                identity,
                [TKRVerification verificationFromPhoneNumber:phoneNumber
                                            verificationCode:getSMSVerificationCode(phoneNumber)]);
            hangWithResolver(^(PMKResolver resolver) {
              [secondDevice startWithIdentity:identity
                            completionHandler:^(TKRStatus status, NSError* err) {
                              resolver(nil);
                            }];
            });
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [secondDevice
                  verifyIdentityWithVerification:[TKRVerification verificationFromPreverifiedPhoneNumber:phoneNumber]
                               completionHandler:resolver];
            });
            expect(err).toNot.beNil();
            expect(err.code).to.equal(TKRErrorInvalidArgument);
          });

          it(@"should register with a passphrase and set a preverified email method", ^{
            NSString* email = @"bob.alice@tanker.io";
            startWithIdentityAndRegister(
                firstDevice, identity, [TKRVerification verificationFromPassphrase:@"Rosebud"]);
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [firstDevice setVerificationMethod:[TKRVerification verificationFromPreverifiedEmail:email]
                               completionHandler:resolver];
            });
            expect(err).to.beNil();
            NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
              [firstDevice verificationMethodsWithCompletionHandler:adapter];
            });
            expect(methods.count).to.equal(2);

            startWithIdentityAndVerify(secondDevice,
                                       identity,
                                       [TKRVerification verificationFromEmail:email
                                                             verificationCode:getEmailVerificationCode(email)]);
          });

          it(@"should register with a passphrase and set a preverified phone number method", ^{
            NSString* phoneNumber = @"+33639982233";
            startWithIdentityAndRegister(
                firstDevice, identity, [TKRVerification verificationFromPassphrase:@"Rosebud"]);
            NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [firstDevice setVerificationMethod:[TKRVerification verificationFromPreverifiedPhoneNumber:phoneNumber]
                               completionHandler:resolver];
            });
            expect(err).to.beNil();
            NSArray<TKRVerificationMethod*>* methods = hangWithAdapter(^(PMKAdapter adapter) {
              [firstDevice verificationMethodsWithCompletionHandler:adapter];
            });
            expect(methods.count).to.equal(2);

            startWithIdentityAndVerify(
                secondDevice,
                identity,
                [TKRVerification verificationFromPhoneNumber:phoneNumber
                                            verificationCode:getSMSVerificationCode(phoneNumber)]);
          });
        });
      });

      describe(@"session tokens (2FA)", ^{
        __block int expectedTokenLength = 44; // Base64 length of a session token (hash size)
        __block TKRTanker* tanker;
        __block NSString* identity;
        __block TKRVerification* verification;

        beforeEach(^{
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          identity = createIdentity(createUUID(), appID, appSecret);
          verification = [TKRVerification verificationFromPassphrase:@"passphrase"];
        });

        afterEach(^{
          stop(tanker);
        });

        it(@"can get a session token using registerIdentityWithVerification", ^{
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker startWithIdentity:identity
                    completionHandler:^(TKRStatus status, NSError* err) {
                      if (err)
                        adapter(nil, err);
                      else
                      {
                        expect(status).to.equal(TKRStatusIdentityRegistrationNeeded);
                        TKRVerificationOptions* opts = [TKRVerificationOptions options];
                        opts.withSessionToken = true;
                        [tanker registerIdentityWithVerification:verification options:opts completionHandler:adapter];
                      }
                    }];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
        });

        it(@"can get a session token using verifyIdentityWithVerification", ^{
          startWithIdentityAndRegister(tanker, identity, verification);
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            TKRVerificationOptions* opts = [TKRVerificationOptions options];
            opts.withSessionToken = true;
            [tanker verifyIdentityWithVerification:verification options:opts completionHandler:adapter];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
        });

        it(@"can get a session token using setVerificationMethod with passphrase", ^{
          startWithIdentityAndRegister(tanker, identity, verification);
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            TKRVerificationOptions* opts = [TKRVerificationOptions options];
            opts.withSessionToken = true;
            [tanker setVerificationMethod:verification options:opts completionHandler:adapter];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
        });

        it(@"can get a session token using setVerificationMethod with email", ^{
          NSString* email = @"bob.alice@tanker.io";
          startWithIdentityAndRegister(tanker, identity, verification);
          TKRVerification* verif = [TKRVerification verificationFromEmail:email
                                                         verificationCode:getEmailVerificationCode(email)];
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            TKRVerificationOptions* opts = [TKRVerificationOptions options];
            opts.withSessionToken = true;
            [tanker setVerificationMethod:verif options:opts completionHandler:adapter];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
        });

        it(@"can get a session token using setVerificationMethod with phone number", ^{
          NSString* phoneNumber = @"+33639982233";
          startWithIdentityAndRegister(tanker, identity, verification);
          TKRVerification* verif = [TKRVerification verificationFromPhoneNumber:phoneNumber
                                                               verificationCode:getSMSVerificationCode(phoneNumber)];
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            TKRVerificationOptions* opts = [TKRVerificationOptions options];
            opts.withSessionToken = true;
            [tanker setVerificationMethod:verif options:opts completionHandler:adapter];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
        });
      });

      describe(@"Storage", ^{
        __block TKRDatastore* db;

        beforeEach(^{
          NSError* err = nil;
          NSString* storagePath = [createStorageFullpath(NSLibraryDirectory) stringByAppendingPathComponent:@"test"];
          NSString* cachePath = [createStorageFullpath(NSCachesDirectory) stringByAppendingPathComponent:@"test"];

          db = [TKRDatastore datastoreWithPersistentPath:storagePath cachePath:cachePath error:&err];
          expect(err).to.beNil();
        });

        afterEach(^{
          [db close];
        });

        it(@"returns no error when caching empty values", ^{
          NSError* err = [db cacheValues:@{} onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();
        });

        it(@"fails to cache duplicate values when onConflictFail is given", ^{
          NSDictionary* keyValues = @{stringToData(@"key") : stringToData(@"value")};
          NSDictionary* newKeyValues = @{stringToData(@"key") : stringToData(@"newValue")};

          NSError* err = [db cacheValues:keyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();

          err = [db cacheValues:newKeyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).toNot.beNil();
          expect(err.domain).to.equal(TKRDatastoreErrorDomain);
          expect(err.code).to.equal(TKRDatastoreErrorConstraintFailed);
        });

        it(@"does nothing when trying to cache duplicate values when onConflictIgnore is given", ^{
          NSDictionary* keyValues = @{stringToData(@"key") : stringToData(@"value")};
          NSDictionary* newKeyValues = @{stringToData(@"key") : stringToData(@"newValue")};

          NSError* err = [db cacheValues:keyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();

          err = [db cacheValues:newKeyValues onConflict:TKRDatastoreOnConflictIgnore];
          expect(err).to.beNil();

          NSArray<NSData*>* values = [db findCacheValuesWithKeys:@[ stringToData(@"key") ] error:&err];
          expect(err).to.beNil();
          expect(values.count).to.equal(1);
          expect([values[0] isEqualToData:stringToData(@"value")]).to.beTruthy();
        });

        it(@"overwrites the record when trying to cache duplicate values when onConflictReplace is given", ^{
          NSDictionary* keyValues = @{stringToData(@"key") : stringToData(@"value")};
          NSDictionary* newKeyValues = @{stringToData(@"key") : stringToData(@"newValue")};

          NSError* err = [db cacheValues:keyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();

          err = [db cacheValues:newKeyValues onConflict:TKRDatastoreOnConflictReplace];
          expect(err).to.beNil();

          NSArray<NSData*>* values = [db findCacheValuesWithKeys:@[ stringToData(@"key") ] error:&err];
          expect(err).to.beNil();
          expect(values.count).to.equal(1);
          expect([values[0] isEqualToData:stringToData(@"newValue")]).to.beTruthy();
        });

        it(@"returns values in the same order as keys, with null values for not found keys", ^{
          NSData* key1 = stringToData(@"key");
          NSData* key2 = stringToData(@"key2");
          NSData* value = stringToData(@"value");
          NSData* value2 = stringToData(@"value2");

          NSDictionary* keyValues = @{key1 : value, key2 : value2};

          NSError* err = [db cacheValues:keyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();

          NSArray<id>* values = [db findCacheValuesWithKeys:@[ key1, key2, stringToData(@"missingKey"), key2 ]
                                                      error:&err];
          expect(err).to.beNil();

          expect(values.count).to.equal(4);
          expect([values[0] isEqualToData:value]).to.beTruthy();
          expect([values[1] isEqualToData:value2]).to.beTruthy();
          expect(values[2]).to.equal([NSNull null]);
          expect([values[3] isEqualToData:value2]).to.beTruthy();
        });

        it(@"can retrieve and overwrite the serialized device", ^{
          NSData* serialized1 = stringToData(@"device1");
          NSData* serialized2 = stringToData(@"device2");

          NSError* err;
          NSData* serializedDevice = [db serializedDeviceWithError:&err];
          expect(err).to.beNil();
          expect(serializedDevice).to.beNil();

          err = [db setSerializedDevice:serialized1];
          expect(err).to.beNil();

          serializedDevice = [db serializedDeviceWithError:&err];
          expect(err).to.beNil();
          expect(serializedDevice).toNot.beNil();

          expect([serializedDevice isEqualToData:serialized1]).to.beTruthy();

          err = [db setSerializedDevice:serialized2];
          expect(err).to.beNil();

          serializedDevice = [db serializedDeviceWithError:&err];
          expect(err).to.beNil();
          expect(serializedDevice).toNot.beNil();

          expect([serializedDevice isEqualToData:serialized2]).to.beTruthy();
        });

        it(@"wipes everything when calling nuke", ^{
          NSError* err;
          NSDictionary* keyValues = @{stringToData(@"key") : stringToData(@"value")};

          err = [db setSerializedDevice:stringToData(@"device")];
          expect(err).to.beNil();

          err = [db cacheValues:keyValues onConflict:TKRDatastoreOnConflictFail];
          expect(err).to.beNil();

          err = [db nuke];
          expect(err).to.beNil();

          NSData* serializedDevice = [db serializedDeviceWithError:&err];
          expect(err).to.beNil();
          expect(serializedDevice).to.beNil();

          NSArray<NSData*>* values = [db findCacheValuesWithKeys:@[ stringToData(@"key") ] error:&err];
          expect(err).to.beNil();
          expect(values.count).to.equal(1);
          expect(values[0]).to.equal([NSNull null]);
        });

        it(@"runs C datastore-tests", ^{
          tanker_datastore_options_t opts = {.open = TKR_datastore_open,
                                             .close = TKR_datastore_close,
                                             .nuke = TKR_datastore_nuke,
                                             .put_serialized_device = TKR_datastore_put_serialized_device,
                                             .find_serialized_device = TKR_datastore_find_serialized_device,
                                             .put_cache_values = TKR_datastore_put_cache_values,
                                             .find_cache_values = TKR_datastore_find_cache_values};

          NSString* path = createStorageFullpath(NSCachesDirectory);
          int ret = tanker_run_datastore_test(&opts, path.UTF8String);
          expect(ret).to.equal(0);
        });
      });
    });

SpecEnd
