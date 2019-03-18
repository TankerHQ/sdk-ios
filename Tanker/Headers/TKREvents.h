#import <Foundation/Foundation.h>

/*!
 @typedef TKRDeviceRevokedHandler
 @brief Block which will be called when the current device is revoked.
 */
typedef void (^TKRDeviceRevokedHandler)(void);

/*!
 @typedef TKRDeviceCreatedHandler
 @brief Block which will be called when new devices have been unlocked for the
 current user since their last connection or if the new device in question is
 the current device.
 */
typedef void (^TKRDeviceCreatedHandler)(void);
