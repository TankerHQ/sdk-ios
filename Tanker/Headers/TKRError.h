/*!
 * @typedef TKRError
 */
typedef NS_ENUM(NSUInteger, TKRError) {
  TKRErrorNoError = 0,
  TKRErrorOther = 1,
  TKRErrorInvalidStatus = 2,
  TKRErrorServerError = 3,
  TKRErrorUnused1 = 4,
  TKRErrorInvalidArgument = 5,
  TKRErrorResourceKeyNotFound = 6,
  TKRErrorUserNotFound = 7,
  TKRErrorDecryptFailed = 8,
  TKRErrorInvalidUnlockEventHandler = 9,
  TKRErrorChunkIndexOutOfRange = 10,
  TKRErrorVersionNotSupported = 11,
  TKRErrorInvalidUnlockKey = 12,
  TKRErrorInternalError = 13,
  TKRErrorChunkNotFound = 14,
  TKRErrorInvalidUnlockPassword = 15,
  TKRErrorInvalidVerificationCode = 16,
  TKRErrorUnlockKeyAlreadyExists = 17,
  TKRErrorMaxVerificationAttemptsReached = 18,
  TKRErrorInvalidGroupSize = 19,
  TKRErrorRecipientNotFound = 20,
  TKRErrorGroupNotFound = 21,
  TKRErrorDeviceNotFound = 22,
};
