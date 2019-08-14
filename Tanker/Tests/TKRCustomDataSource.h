#import <Foundation/Foundation.h>

#import <POSInputStreamLibrary/POSBlobInputStreamDataSource.h>

@interface TKRCustomDataSource : NSObject <POSBlobInputStreamDataSource>

+ (nullable instancetype)customDataSourceWithData:(nonnull NSData*)data;

@property BOOL isSlow;
@property BOOL willErr;

@property NSInteger currentPosition;
@property(nonnull) NSData* data;

@property(nonatomic, nullable) NSError* error;
@property(nonatomic, getter=isOpenCompleted) BOOL openCompleted;
@property(nonatomic) BOOL hasBytesAvailable;
@property(nonatomic, getter=isAtEnd) BOOL atEnd;

@end
