/*!
 * @typedef TKRError
 */
typedef NS_ENUM(NSUInteger, TKRError) {
  TKRErrorInvalidArgument = 1,
  TKRErrorInternalError,
  TKRErrorNetworkError,
  TKRErrorPreconditionFailed,
  TKRErrorOperationCanceled,
  TKRErrorDecryptionFailed,
  TKRErrorGroupTooBig,
  TKRErrorInvalidVerification,
  TKRErrorTooManyAttempts,
  TKRErrorExpiredVerification,
  TKRErrorIOError,
  TKRErrorDeviceRevoked,
  TKRErrorConflict,
  TKRErrorUpgradeRequired,
  TKRIdentityAlreadyAttached,
};
