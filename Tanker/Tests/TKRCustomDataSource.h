#import <Foundation/Foundation.h>

#import <Tanker/TKRStreamBase.h>

@interface TKRCustomDataSource : TKRStreamBase

+ (nullable instancetype)customDataSourceWithData:(nonnull NSData*)data;
- (nonnull instancetype)initWithData:(nonnull NSData*)data;

@property BOOL isSlow;
@property BOOL willErr;

@property NSInteger currentPosition;
@property(nonnull) NSData* data;

@property(nonatomic, readonly, getter=hasBytesAvailable) BOOL hasBytesAvailable;
@property(nonatomic, getter=isAtEnd) BOOL atEnd;

@end
