#import <Foundation/Foundation.h>

/*!
 @typedef TKRValidationHandler
 @brief Block which will be called when a new device gets created.

 @discussion This block @b MUST @b NOT hang the current thread, otherwise Tanker
 will deadlock!

 @param validationCode The base64 encoded validation code, which must be
 accepted by an already registered device
 */
typedef void (^TKRValidationHandler)(NSString* validationCode);

/*!
 @typedef TKRUnlockRequiredHandler
 @brief Block which will be called when the current device must be unlocked.
 */
typedef void (^TKRUnlockRequiredHandler)(void);

/*!
 @typedef TKRDeviceRevokedHandler
 @brief Block which will be called when the current device is revoked.
 */
typedef void (^TKRDeviceRevokedHandler)(void);

/*!
 @typedef TKRDeviceCreatedHandler
 @brief Block which will be called when new devices have been unlocked for the current user since their last connection
        or if the new device in question is the current device.
 */
typedef void (^TKRDeviceCreatedHandler)(void);
