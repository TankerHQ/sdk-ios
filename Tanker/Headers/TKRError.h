/*!
 * @typedef TKRError
 */
typedef NS_ENUM(NSUInteger, TKRError) {
  TKRErrorNoError = 0,
  TKRErrorOther = 1,
  TKRErrorInvalidStatus = 2,
  TKRErrorServerError = 3,
  TKRErrorInvalidArgument = 4,
  TKRErrorResourceKeyNotFound = 5,
  TKRErrorUserNotFound = 6,
  TKRErrorDecryptFailed = 7,
  TKRErrorInvalidUnlockEventHandler = 8,
  TKRErrorVersionNotSupported = 9,
  TKRErrorInvalidUnlockKey = 8,
  TKRErrorInternalError = 9,
  TKRErrorInvalidUnlockPassword = 10,
  TKRErrorInvalidVerificationCode = 11,
  TKRErrorUnlockKeyAlreadyExists = 12,
  TKRErrorMaxVerificationAttemptsReached = 13,
  TKRErrorInvalidGroupSize = 14,
  TKRErrorRecipientNotFound = 15,
  TKRErrorGroupNotFound = 16,
  TKRErrorDeviceNotFound = 17,
};
