#import <Foundation/Foundation.h>

/*!
 * @typedef TKRError
 */
typedef NS_ENUM(NSInteger, TKRError) {
  TKRErrorInvalidArgument = 1,
  TKRErrorInternalError = 2,
  TKRErrorNetworkError = 3,
  TKRErrorPreconditionFailed = 4,
  TKRErrorOperationCanceled = 5,
  TKRErrorDecryptionFailed = 6,
  TKRErrorGroupTooBig = 7,
  TKRErrorInvalidVerification = 8,
  TKRErrorTooManyAttempts = 9,
  TKRErrorExpiredVerification = 10,
  TKRErrorIOError = 11,
  TKRErrorDeviceRevoked = 12,
  TKRErrorConflict = 13,
  TKRErrorUpgradeRequired = 14,
  TKRErrorIdentityAlreadyAttached = 15,
} NS_SWIFT_NAME(Error);

NS_SWIFT_NAME(ErrorDomain)
FOUNDATION_EXPORT NSString* const TKRErrorDomain;
