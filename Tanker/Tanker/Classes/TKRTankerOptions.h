
#import <Foundation/Foundation.h>

/*!
 @brief Options that must be given when creating a TKRTanker
 */
@interface TKRTankerOptions : NSObject

/*!
 @brief ID of your Trustchain
 */
@property NSString* trustchainID;

/*!
 @brief Only for testing purposes. Do not use.
 */
@property NSString* trustchainURL;

/*!
 @brief Only for testing purposes. Do not use.
 */
@property bool isTest;

/*!
 @brief Path to which Tanker will write its internal files.

 @discussion The path must point to an existing folder.
 */
@property NSString* writablePath;

/*!
  @brief Create and return an empty TKRTankerOptions.
 */
+ (instancetype)options;

@end
