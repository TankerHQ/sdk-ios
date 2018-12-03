/*!
 * @typedef TKRStatus
 * @constant TKRStatusClosed Default state
 * @constant TKRStatusOpen Session is open
 */
typedef NS_ENUM(NSUInteger, TKRStatus) {
  /// Default state
  TKRStatusClosed = 0,
  TKRStatusOpen = 1,
  TKRStatusUserCreation = 2,
  TKRStatusDeviceCreation = 3,
  TKRStatusClosing = 4,
};
