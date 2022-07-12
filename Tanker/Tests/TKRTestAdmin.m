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

// MARK: Instance methods

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

- (NSDictionary*)sendRequestSync:(nonnull NSMutableURLRequest*)request
                        errorPtr:(__autoreleasing NSError**)errorPtr
                     responsePtr:(__autoreleasing NSURLResponse**)responsePtr
{
  __block NSData* result = nil;
  dispatch_semaphore_t sem;
  sem = dispatch_semaphore_create(0);
  [[self.session dataTaskWithRequest:request
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

  if (error)
  {
    NSLog(@"create app error : %@", error.description);
    return nil;
  }

  NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
  if ([httpResponse statusCode] >= 400)
  {
    NSLog(@"create app request returned status %d", (int)[httpResponse statusCode]);
    return nil;
  }

  return result;
}

- (void)deleteApp:(nonnull NSString*)id
{
  NSMutableURLRequest* request = [self createRequestForId:id method:@"DELETE" body:nil];

  NSError* __block error = nil;
  NSURLResponse* __block response = nil;
  [self sendRequestSync:request errorPtr:&error responsePtr:&response];

  if (error)
  {
    NSLog(@"delete app error : %@", error.description);
    return;
  }

  NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
  if ([httpResponse statusCode] >= 400)
    NSLog(@"delete app request returned status %d", (int)[httpResponse statusCode]);
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
