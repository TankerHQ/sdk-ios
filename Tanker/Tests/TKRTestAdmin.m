#import "TKRTestAdmin.h"

#import <PromiseKit/PromiseKit.h>

@interface TKRTestAdmin ()

@property NSString* appManagementUrl;
@property NSString* appManagementToken;
@property NSString* environmentName;
@property NSURLSession* session;

@end

@implementation TKRTestAdmin

// MARK: Class methods

+ (nonnull TKRTestAdmin*)adminWithUrl:(nonnull NSString*)appManagementUrl
                   appManagementToken:(nonnull NSString*)appManagementToken
                      environmentName:(nonnull NSString*)environmentName
{
  __block TKRTestAdmin* admin = [[[self class] alloc] init];
  admin.appManagementUrl = appManagementUrl;
  admin.appManagementToken = appManagementToken;
  admin.environmentName = environmentName;

  NSString* bearer = [NSString stringWithFormat:@"Bearer %@", appManagementToken];
  NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
  sessionConfiguration.HTTPAdditionalHeaders = @{@"Authorization" : bearer};
  admin.session = [NSURLSession sessionWithConfiguration:sessionConfiguration];

  return admin;
}

+ (BOOL)logHttpErrorFor:(nonnull NSString*)description
                  error:(NSError* _Nullable)error
               response:(NSURLResponse* _Nullable)response
{
  if (error)
  {
    NSLog(@"%@ http error : %@", description, error.description);
    return YES;
  }

  NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
  if ([httpResponse statusCode] >= 400)
  {
    NSLog(@"%@ request returned status %d", description, (int)[httpResponse statusCode]);
    return YES;
  }

  return NO;
}

+ (NSString* _Nullable)getEmailVerificationCodeForApp:(nonnull NSString*)appID
                                       trustchaindUrl:(nonnull NSString*)trustchaindUrl
                                    verificationToken:(nonnull NSString*)verificationToken
                                                email:(nonnull NSString*)email
{
  NSString* url = [NSString stringWithFormat:@"%@/verification/email/code", trustchaindUrl];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  [request setHTTPMethod:@"POST"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  NSMutableDictionary* bodyDictionary = [[NSMutableDictionary alloc] init];
  [bodyDictionary setValue:appID forKey:@"app_id"];
  [bodyDictionary setValue:email forKey:@"email"];
  [bodyDictionary setValue:verificationToken forKey:@"auth_token"];

  NSData* bodyData = [NSJSONSerialization dataWithJSONObject:bodyDictionary
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
  NSString* body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
  [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

  NSURLResponse* response = nil;
  NSError* error = nil;
  NSDictionary* result = [TKRTestAdmin sendRequestSyncWithSession:[NSURLSession sharedSession]
                                                          request:request
                                                         errorPtr:&error
                                                      responsePtr:&response];
  if ([TKRTestAdmin logHttpErrorFor:@"getEmailVerificationCodeForApp" error:error response:response])
    return nil;

  return result[@"verification_code"];
}

+ (NSString* _Nullable)getSmsVerificationCodeForApp:(nonnull NSString*)appID
                                     trustchaindUrl:(nonnull NSString*)trustchaindUrl
                                  verificationToken:(nonnull NSString*)verificationToken
                                        phoneNumber:(nonnull NSString*)phoneNumber
{
  NSString* url = [NSString stringWithFormat:@"%@/verification/sms/code", trustchaindUrl];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  [request setHTTPMethod:@"POST"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  NSMutableDictionary* bodyDictionary = [[NSMutableDictionary alloc] init];
  [bodyDictionary setValue:appID forKey:@"app_id"];
  [bodyDictionary setValue:phoneNumber forKey:@"phone_number"];
  [bodyDictionary setValue:verificationToken forKey:@"auth_token"];

  NSData* bodyData = [NSJSONSerialization dataWithJSONObject:bodyDictionary
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:nil];
  NSString* body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
  [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];

  NSURLResponse* response = nil;
  NSError* error = nil;
  NSDictionary* result = [TKRTestAdmin sendRequestSyncWithSession:[NSURLSession sharedSession]
                                                          request:request
                                                         errorPtr:&error
                                                      responsePtr:&response];
  if ([TKRTestAdmin logHttpErrorFor:@"getSmsVerificationCodeForApp" error:error response:response])
    return nil;

  return result[@"verification_code"];
}

+ (NSDictionary*)sendRequestSyncWithSession:(nonnull NSURLSession*)session
                                    request:(nonnull NSMutableURLRequest*)request
                                   errorPtr:(__autoreleasing NSError**)errorPtr
                                responsePtr:(__autoreleasing NSURLResponse**)responsePtr
{
  __block NSData* result = nil;
  dispatch_semaphore_t sem;
  sem = dispatch_semaphore_create(0);
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                if (errorPtr)
                  *errorPtr = err;
                if (responsePtr)
                  *responsePtr = resp;
                if (err == nil)
                {
                  result = data;
                }
                dispatch_semaphore_signal(sem);
              }] resume];
  dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

  if (result == nil)
    return nil;

  return [NSJSONSerialization JSONObjectWithData:result options:0 error:errorPtr];
}

// MARK: Instance methods

- (NSDictionary*)sendRequestSync:(nonnull NSMutableURLRequest*)request
                        errorPtr:(__autoreleasing NSError**)errorPtr
                     responsePtr:(__autoreleasing NSURLResponse**)responsePtr
{
  return [TKRTestAdmin sendRequestSyncWithSession:self.session
                                          request:request
                                         errorPtr:errorPtr
                                      responsePtr:responsePtr];
}

- (NSMutableURLRequest*)createRequestForId:(nonnull NSString*)id method:(nonnull NSString*)method body:(NSString*)body
{
  NSString* b64UrlId = id;
  if (id.length != 0)
  {
    NSData* decoded = [[NSData alloc] initWithBase64EncodedString:id options:0];
    b64UrlId = [decoded base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    b64UrlId = [b64UrlId stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    b64UrlId = [b64UrlId stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    b64UrlId = [b64UrlId stringByReplacingOccurrencesOfString:@"=" withString:@""];
  }
  NSString* url = [NSString stringWithFormat:@"%@/v1/apps/%@", self.appManagementUrl, b64UrlId];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];

  [request setHTTPMethod:method];
  if (body)
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  return request;
}

- (NSDictionary* _Nullable)createAppWithName:(nonnull NSString*)name
{
  NSMutableDictionary* contentDictionary = [[NSMutableDictionary alloc] init];
  [contentDictionary setValue:name forKey:@"name"];
  [contentDictionary setValue:self.environmentName forKey:@"environment_name"];

  NSData* data = [NSJSONSerialization dataWithJSONObject:contentDictionary
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:nil];
  NSString* jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSMutableURLRequest* request = [self createRequestForId:@"" method:@"POST" body:jsonStr];

  NSError* __block error = nil;
  NSURLResponse* __block response = nil;
  NSDictionary* __block result = [self sendRequestSync:request errorPtr:&error responsePtr:&response];

  if ([TKRTestAdmin logHttpErrorFor:@"createAppWithName" error:error response:response])
    return nil;
  return result;
}

- (void)deleteApp:(nonnull NSString*)id
{
  NSMutableURLRequest* request = [self createRequestForId:id method:@"DELETE" body:nil];

  NSError* __block error = nil;
  NSURLResponse* __block response = nil;
  [self sendRequestSync:request errorPtr:&error responsePtr:&response];

  [TKRTestAdmin logHttpErrorFor:@"deleteApp" error:error response:response];
}

- (NSError* _Nullable)updateApp:(NSString* _Nullable)appID
                     oidcClientID:(NSString* _Nullable)oidcClientID
               oidcClientProvider:(NSString* _Nullable)oidcClientProvider
    enablePreverifiedVerification:(bool* _Nullable)enablePreverifiedVerification
{
  NSMutableDictionary* contentDictionary = [[NSMutableDictionary alloc] init];
  if (oidcClientID != nil)
    [contentDictionary setValue:oidcClientID forKey:@"oidc_client_id"];
  if (oidcClientProvider != nil)
    [contentDictionary setValue:oidcClientProvider forKey:@"oidc_provider"];
  if (enablePreverifiedVerification != nil)
    [contentDictionary setValue:[NSNumber numberWithBool:*enablePreverifiedVerification]
                         forKey:@"preverified_verification_enabled"];

  NSData* data = [NSJSONSerialization dataWithJSONObject:contentDictionary
                                                 options:NSJSONWritingPrettyPrinted
                                                   error:nil];
  NSString* jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSMutableURLRequest* request = [self createRequestForId:appID method:@"PATCH" body:jsonStr];

  NSError* __block error = nil;
  NSURLResponse* __block response = nil;
  [self sendRequestSync:request errorPtr:&error responsePtr:&response];
  if (error)
    return error;

  NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
  if ([httpResponse statusCode] >= 400)
  {
    return
        [NSError errorWithDomain:@"TKRTestAdmin"
                            code:1
                        userInfo:@{
                          NSLocalizedDescriptionKey : [NSString
                              stringWithFormat:@"update app request returned status %d", (int)[httpResponse statusCode]]
                        }];
  }
  return nil;
}

@end
