// https://github.com/Specta/Specta

#import "TKREncryptionSession.h"
#import "TKRError.h"
#import "TKRInputStreamDataSource+Private.h"
#import "TKRTanker.h"
#import "TKRTankerOptions.h"
#import "TKRVerification.h"
#import "TKRAttachResult.h"
#import "TKRVerificationKey.h"

#import "TKRCustomDataSource.h"
#import "TKRTestAsyncStreamReader.h"

#import <POSInputStreamLibrary/POSInputStreamLibrary.h>
#import <Expecta/Expecta.h>
#import <Specta/Specta.h>
#import <PromiseKit/PromiseKit.h>

#include "ctanker.h"
#include "ctanker/admin.h"
#include "ctanker/identity.h"

static NSError* getOptionalFutureError(tanker_future_t* fut)
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

static void* unwrapAndFreeExpected(tanker_expected_t* expected)
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

static NSString* createIdentity(NSString* userID, NSString* appID, NSString* appSecret)
{
  char const* user_id = [userID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* app_id = [appID cStringUsingEncoding:NSUTF8StringEncoding];
  char const* app_secret = [appSecret cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_expected_t* identity_expected = tanker_create_identity(app_id, app_secret, user_id);
  char* identity = unwrapAndFreeExpected(identity_expected);
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
  char* identity = unwrapAndFreeExpected(provisional_expected);
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

  char* public_identity = unwrapAndFreeExpected(identity_expected);
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

static NSString* createStorageFullpath()
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

static TKRTankerOptions* createTankerOptions(NSString* url, NSString* appID)
{
  TKRTankerOptions* opts = [TKRTankerOptions options];
  opts.url = url;
  opts.appID = appID;
  opts.writablePath = createStorageFullpath();
  opts.sdkType = @"sdk-ios-tests";
  return opts;
}

static void updateAdminApp(
    tanker_admin_t* admin, NSString* appID, NSString* oidcClientID, NSString* oidcClientProvider, bool* enable2FA)
{
  char const* app_id = [appID cStringUsingEncoding:NSUTF8StringEncoding];
  tanker_app_update_options_t options = TANKER_APP_UPDATE_OPTIONS_INIT;
  options.session_certificates = enable2FA;
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
                       NSDictionary* responseDictionary =
                           [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
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

SpecBegin(TankerSpecs)

    describe(@"Tanker Bindings", ^{
      __block tanker_admin_t* admin;
      __block NSString* url;
      __block NSString* trustchaindUrl;
      __block char const* curl;
      __block char const* ctrustchaindurl;
      __block NSString* appID;
      __block NSString* appSecret;
      __block NSString* authToken;
      __block NSDictionary* oidcTestConfig;

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
        hangWithResolver(^(PMKResolver resolve) {
          [tanker stopWithCompletionHandler:resolve];
        });
        expect(tanker.status).to.equal(TKRStatusStopped);
      };

      __block NSString* (^getVerificationCode)(NSString*) = ^(NSString* email) {
        tanker_future_t* f = tanker_get_verification_code(ctrustchaindurl,
                                                          [appID cStringUsingEncoding:NSUTF8StringEncoding],
                                                          [authToken cStringUsingEncoding:NSUTF8StringEncoding],
                                                          [email cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(f);
        char* code = (char*)tanker_future_get_voidptr(f);
        NSString* ret = [NSString stringWithCString:code encoding:NSUTF8StringEncoding];
        free(code);
        return ret;
      };

      beforeAll(^{
        NSDictionary* env = [[NSProcessInfo processInfo] environment];
        url = env[@"TANKER_APPD_URL"];
        trustchaindUrl = env[@"TANKER_TRUSTCHAIND_URL"];
        NSString* adminUrl = env[@"TANKER_ADMIND_URL"];
        expect(url).toNot.beNil();
        expect(adminUrl).toNot.beNil();
        NSString* idToken = env[@"TANKER_ID_TOKEN"];
        expect(idToken).toNot.beNil();

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
        char const* cadminUrl = [adminUrl cStringUsingEncoding:NSUTF8StringEncoding];
        char const* id_token = [idToken cStringUsingEncoding:NSUTF8StringEncoding];
        tanker_future_t* connect_fut = tanker_admin_connect(cadminUrl, id_token);
        tanker_future_wait(connect_fut);
        NSError* connectError = getOptionalFutureError(connect_fut);
        expect(connectError).to.beNil();
        admin = (tanker_admin_t*)tanker_future_get_voidptr(connect_fut);
        tanker_future_destroy(connect_fut);
        tanker_future_t* app_fut = tanker_admin_create_app(admin, "ios-test");
        tanker_future_wait(app_fut);
        NSError* createError = getOptionalFutureError(app_fut);
        expect(createError).to.beNil();
        tanker_app_descriptor_t* app = (tanker_app_descriptor_t*)tanker_future_get_voidptr(app_fut);
        appID = [NSString stringWithCString:app->id encoding:NSUTF8StringEncoding];
        appSecret = [NSString stringWithCString:app->private_key encoding:NSUTF8StringEncoding];
        authToken = [NSString stringWithCString:app->auth_token encoding:NSUTF8StringEncoding];
        tanker_future_destroy(app_fut);
        tanker_admin_app_descriptor_free(app);
      });

      afterAll(^{
        tanker_future_t* delete_fut = tanker_admin_delete_app(admin, [appID cStringUsingEncoding:NSUTF8StringEncoding]);
        tanker_future_wait(delete_fut);
        NSError* error = getOptionalFutureError(delete_fut);
        expect(error).to.beNil();

        tanker_future_t* admin_destroy_fut = tanker_admin_destroy(admin);
        tanker_future_wait(admin_destroy_fut);
        error = getOptionalFutureError(admin_destroy_fut);
        expect(error).to.beNil();
      });

      beforeEach(^{
        tankerOptions = createTankerOptions(url, appID);
      });

      describe(@"prehashPassword", ^{
        it(@"should fail to hash an empty password", ^{
          expect(^{
            [TKRTanker prehashPassword:@""];
          })
              .to.raise(NSInvalidArgumentException);
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
          startWithIdentityAndRegister(aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          __block NSString* provIdentity = createProvisionalIdentity(appID, aliceEmail);
          TKRAttachResult* result = hangWithAdapter(^(PMKAdapter adapter) {
              [aliceTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          expect(result.status).to.equal(TKRStatusIdentityVerificationNeeded);
          expect(result.method.type).to.equal(TKRVerificationMethodTypeEmail);
          expect(result.method.email).to.equal(aliceEmail);

          TKRVerification* verif = [TKRVerification verificationFromEmail:aliceEmail verificationCode:getVerificationCode(aliceEmail)];
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
          startWithIdentityAndRegister(aliceTanker, aliceIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          __block NSString* provIdentity = createProvisionalIdentity(appID, aliceEmail);
          hangWithAdapter(^(PMKAdapter adapter) {
              [aliceTanker attachProvisionalIdentity:provIdentity completionHandler:adapter];
          });
          TKRVerification* aliceVerif = [TKRVerification verificationFromEmail:aliceEmail verificationCode:getVerificationCode(aliceEmail)];
          NSError* err = hangWithResolver(^(PMKResolver resolver) {
              [aliceTanker verifyProvisionalIdentityWithVerification:aliceVerif completionHandler:resolver];
          });
          expect(err).to.beNil();

          // try to attach/verify with Bob now
          startWithIdentityAndRegister(bobTanker, bobIdentity, [TKRVerification verificationFromPassphrase:@"passphrase"]);
          TKRVerification* bobVerif = [TKRVerification verificationFromEmail:aliceEmail verificationCode:getVerificationCode(aliceEmail)];
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
            [bobTanker decryptStringFromData:encryptedData completionHandler:adapter];
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
            [bobTanker encryptString:clearText completionHandler:adapter];
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
          TKRSharingOptions* opts = [TKRSharingOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter sharingOptions:opts];
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
          TKRSharingOptions* opts = [TKRSharingOptions options];
          opts.shareWithUsers = @[ bobPublicIdentity ];
          TKREncryptionSession* encSess = hangWithAdapter(^(PMKAdapter adapter) {
            [aliceTanker createEncryptionSessionWithCompletionHandler:adapter sharingOptions:opts];
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
          hangWithResolver(^(PMKResolver resolve) {
            [aliceTanker shareResourceIDs:@[ resourceID ] options:opts completionHandler:resolve];
          });

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

          startWithIdentityAndRegister(userPhone, userIdentity, oidcVerif);
          stop(userPhone);

          TKRTanker* userLaptop = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
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
      });

      describe(@"session tokens (2FA)", ^{
        __block int expectedTokenLength;
        __block TKRTanker* tanker;
        __block NSString* identity;
        __block TKRVerification* verification;

        beforeEach(^{
          expectedTokenLength = 44; // Base64 length of a session token (hash size)
          tanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(tanker).toNot.beNil();
          identity = createIdentity(createUUID(), appID, appSecret);
          verification = [TKRVerification verificationFromPassphrase:@"passphrase"];
          bool enable2FA = true;
          updateAdminApp(admin, appID, nil, nil, &enable2FA);
        });

        afterEach(^{
          bool enable2FA = false;
          updateAdminApp(admin, appID, nil, nil, &enable2FA);
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
                        expect(tanker.status).to.equal(TKRStatusIdentityRegistrationNeeded);
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

        it(@"can get a session token using setVerificationMethod", ^{
          startWithIdentityAndRegister(tanker, identity, verification);
          NSString* token = hangWithAdapter(^(PMKAdapter adapter) {
            TKRVerificationOptions* opts = [TKRVerificationOptions options];
            opts.withSessionToken = true;
            [tanker setVerificationMethod:verification options:opts completionHandler:adapter];
          });
          expect(token).toNot.beNil();
          expect(token.length).to.equal(expectedTokenLength);
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
          identity = createIdentity(userID, appID, appSecret);

          secondDevice = [TKRTanker tankerWithOptions:createTankerOptions(url, appID)];
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
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptString:@"text" completionHandler:adapter];
          });
          expect(revoked).to.equal(true);
          expect(err.code).to.equal(TKRErrorDeviceRevoked);
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
          NSError* err = hangWithAdapter(^(PMKAdapter adapter) {
            [tanker encryptString:@"text" completionHandler:adapter];
          });
          expect(revoked).to.equal(true);
          expect(err.code).to.equal(TKRErrorDeviceRevoked);
        });

        it(@"rejects a revocation of another user's device", ^{
          TKRTanker* bobTanker = [TKRTanker tankerWithOptions:tankerOptions];
          expect(bobTanker).toNot.beNil();

          NSString* bobIdentity = createIdentity(createUUID(), appID, appSecret);
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
