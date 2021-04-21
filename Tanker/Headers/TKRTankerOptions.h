
#import <Foundation/Foundation.h>

/*!
 @brief Options that must be given when creating a TKRTanker
 */
@interface TKRTankerOptions : NSObject

/*!
 @deprecated use appID
 */
@property NSString* trustchainID DEPRECATED_MSG_ATTRIBUTE("use appID instead");

/*!
 @brief ID of your app
 */
@property NSString* appID;

/*!
 @brief Only for testing purposes. Do not use.
 */
@property NSString* url;

/*!
 @brief Path to which Tanker will write its internal files.

 @discussion The path must point to an existing folder.
 */
@property NSString* writablePath;

@property NSString* sdkType;

/*!
  @brief Create and return an empty TKRTankerOptions.
 */
+ (instancetype)options;

@end
