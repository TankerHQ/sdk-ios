#include <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TKRLogLevel) {
  TKRLogLevelDebug = 1,
  TKRLogLevelInfo,
  TKRLogLevelWarning,
  TKRLogLevelError
};

@interface TKRLogEntry : NSObject

@property NSString* category;
@property TKRLogLevel level;
@property NSString* file;
@property NSUInteger line;
@property NSString* message;

@end
