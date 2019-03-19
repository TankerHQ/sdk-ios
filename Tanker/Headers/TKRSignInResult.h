#import <Foundation/Foundation.h>

/*!
 * @typedef TKRSignInResult
 */
typedef NS_ENUM(NSUInteger, TKRSignInResult) {
  TKRSignInResultOk = 0,
  TKRSignInResultIdentityNotRegistered = 1,
  TKRSignInResultIdentityVerificationNeeded = 2,
};
