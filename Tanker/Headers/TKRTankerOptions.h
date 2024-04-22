
#import <Foundation/Foundation.h>

/*!
 @brief Options that must be given when creating a TKRTanker
 */
NS_SWIFT_NAME(TankerOptions)
@interface TKRTankerOptions : NSObject

/*!
 @brief ID of your app
 */
@property NSString* appID;

/*!
 @brief Optional. Sets the dedicated environment to use.
 */
@property NSString* url;

/*!
 @brief Path to which Tanker will write its internal persistent files.

 @discussion The path must point to an existing folder.
 */
@property NSString* persistentPath;

/*!
 @brief Path to which Tanker will write its internal temporary files.

 @discussion The path must point to an existing folder.
 */
@property NSString* cachePath;

@property NSString* sdkType;

/*!
  @brief Create and return an empty TKRTankerOptions.
 */
+ (instancetype)options;

@end
