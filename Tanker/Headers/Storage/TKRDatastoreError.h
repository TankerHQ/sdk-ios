#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, TKRDatastoreError) {
  TKRDatastoreErrorInvalidDatabaseVersion = 1,
  TKRDatastoreErrorRecordNotFound = 2,
  TKRDatastoreErrorDatabaseError = 3,
  TKRDatastoreErrorDatabaseLocked = 4,
  TKRDatastoreErrorDatabaseCorrupt = 5,
  TKRDatastoreErrorDatabaseTooRecent = 6,
  TKRDatastoreErrorConstraintFailed = 7,
};

FOUNDATION_EXPORT NSString* const TKRDatastoreErrorDomain;
