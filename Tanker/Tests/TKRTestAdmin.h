#import <Foundation/Foundation.h>

#import <PromiseKit/PromiseKit.h>

@interface TKRTestAdmin : NSObject

// MARK: Class methods

+ (nonnull TKRTestAdmin*)adminWithUrl:(nonnull NSString*)appManagementUrl
                   appManagementToken:(nonnull NSString*)appManagementToken
                      environmentName:(nonnull NSString*)environmentName;

// MARK: Instance methods

- (NSDictionary* _Nullable)createAppWithName:(nonnull NSString*)name;
- (void)deleteApp:(nonnull NSString*)id;
- (NSError* _Nullable)updateApp:(NSString* _Nullable)appID
                   oidcClientID:(NSString* _Nullable)oidcClientID
             oidcClientProvider:(NSString* _Nullable)oidcClientProvider
  enablePreverifiedVerification:(bool* _Nullable)enablePreverifiedVerification;

@end
