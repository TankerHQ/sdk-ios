#import <Tanker/Storage/TKRDatastore.h>

#import <Tanker/Storage/TKRDatastoreError.h>

#import <Tanker/Utils/TKRUtils.h>

#import <sqlite3.h>

#import <stdlib.h>

static int const latestCacheVersion = 1;
static int const latestDeviceVersion = 1;

NSString* const cacheTableName = @"cache";
NSString* const deviceTableName = @"device";

@interface TKRDatastore ()

@property sqlite3* persistent_handle;
@property sqlite3* cache_handle;

@end

static TKRDatastoreError translateSQLiteError(int err_code)
{
  assert(err_code != SQLITE_OK && err_code != SQLITE_ROW && err_code != SQLITE_DONE);

  switch (err_code)
  {
  case SQLITE_NOTFOUND:
    return TKRDatastoreErrorRecordNotFound;
  case SQLITE_CONSTRAINT:
    return TKRDatastoreErrorConstraintFailed;
  case SQLITE_CORRUPT:
    return TKRDatastoreErrorDatabaseCorrupt;
  case SQLITE_LOCKED:
    return TKRDatastoreErrorDatabaseLocked;
  default:
    return TKRDatastoreErrorDatabaseError;
  }
}

static NSError* _Nullable errorFromSQLite(sqlite3* handle)
{
  int sqlite_code = sqlite3_errcode(handle);
  if (sqlite_code == SQLITE_OK)
    return nil;
  char const* sqlite_msg = sqlite3_errmsg(handle);

  NSString* msg = [NSString stringWithFormat:@"SQLite returned %d, with message: %s", sqlite_code, sqlite_msg];

  return TKR_createNSError(TKRDatastoreErrorDomain, msg, translateSQLiteError(sqlite_code));
}

static NSError* _Nullable initDb(sqlite3* handle)
{
  NSArray<NSString*>* cmds = @[
    @"PRAGMA secure_delete = ON",
    @"SELECT count(*) FROM sqlite_master",
    @"PRAGMA locking_mode = EXCLUSIVE",
    @"CREATE TABLE IF NOT EXISTS access (last_access INT NOT NULL)",
    @"UPDATE access SET last_access = 0"
  ];

  for (NSString* cmd in cmds)
  {
    sqlite3_exec(handle, cmd.UTF8String, NULL, NULL, NULL);
    NSError* err = errorFromSQLite(handle);
    if (err)
    {
      NSLog(@"Command failed: %@, with err: %@", cmd, err.localizedDescription);
      return err;
    }
  }
  return nil;
}

static NSError* _Nullable openOrCreateDb(NSString* _Nonnull dbPath, sqlite3** handle)
{
  sqlite3_open(dbPath.UTF8String, handle);
  NSError* err = errorFromSQLite(*handle);
  if (err)
    return err;
  return initDb(*handle);
}

static NSError* _Nullable dbVersion(sqlite3* handle, int* ret)
{
  sqlite3_stmt* stmt;
  int err_code = sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &stmt, NULL);
  if (err_code != SQLITE_OK)
    return errorFromSQLite(handle);

  err_code = sqlite3_step(stmt);
  if (err_code != SQLITE_ROW)
  {
    NSString* errMsg = [NSString stringWithCString:sqlite3_errstr(err_code) encoding:NSUTF8StringEncoding];
    return TKR_createNSError(TKRDatastoreErrorDomain, errMsg, translateSQLiteError(err_code));
  }
  *ret = sqlite3_column_int(stmt, 0);

  sqlite3_finalize(stmt);
  return errorFromSQLite(handle);
}

static NSError* _Nullable setDbVersion(sqlite3* handle, int version)
{
  NSString* cmd = [NSString stringWithFormat:@"PRAGMA user_version = %d", version];
  sqlite3_exec(handle, cmd.UTF8String, NULL, NULL, NULL);
  return errorFromSQLite(handle);
}

static NSString* _Nonnull onConflictToString(TKRDatastoreOnConflict action)
{
  switch (action)
  {
  case TKRDatastoreOnConflictFail:
    return @"FAIL";
  case TKRDatastoreOnConflictIgnore:
    return @"IGNORE";
  case TKRDatastoreOnConflictReplace:
    return @"REPLACE";
  default:
    return @"unknown";
  }
}

static NSString* _Nonnull dataToHexString(NSData* _Nonnull data)
{
  char const* ptr = (char const*)data.bytes;
  char const* end = ptr + data.length;

  NSMutableString* hex = [NSMutableString string];
  while (ptr != end)
    [hex appendFormat:@"%02x", *ptr++ & 0x00FF];

  return [NSString stringWithFormat:@"x'%@'", hex];
}

static NSString* _Nonnull buildCacheRequest(NSString* _Nonnull tableName,
                                            NSDictionary<NSData*, NSData*>* _Nonnull keyValues,
                                            TKRDatastoreOnConflict action)
{
  NSMutableString* cmd = [NSMutableString stringWithString:@"INSERT OR "];
  [cmd appendString:onConflictToString(action)];
  [cmd appendFormat:@" INTO %@ VALUES ", tableName];
  for (NSData* key in keyValues)
  {
    NSString* hexKey = dataToHexString(key);
    NSString* hexValue = dataToHexString([keyValues objectForKey:key]);
    [cmd appendFormat:@"(%@, %@),", hexKey, hexValue];
  }
  // pop last ','
  [cmd deleteCharactersInRange:NSMakeRange([cmd length] - 1, 1)];

  return cmd;
}

static NSString* _Nonnull buildFindCacheRequest(NSArray<NSData*>* _Nonnull keys)
{
  NSMutableString* cmd = [NSMutableString stringWithString:@"SELECT key, value FROM "];
  [cmd appendString:cacheTableName];
  [cmd appendString:@" WHERE key IN ("];
  for (NSData* key in keys)
  {
    NSString* hexKey = dataToHexString(key);
    [cmd appendFormat:@"%@,", hexKey];
  }
  [cmd deleteCharactersInRange:NSMakeRange([cmd length] - 1, 1)];
  [cmd appendString:@")"];

  return cmd;
}

static NSString* _Nonnull buildSetDeviceRequest(NSData* _Nonnull serializedDevice)
{
  NSString* hexSerializedDevice = dataToHexString(serializedDevice);
  return [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ VALUES (1, %@)", deviceTableName, hexSerializedDevice];
}

static NSArray<id>* _Nonnull setDifferenceToNull(NSArray<NSData*>* _Nonnull keys,
                                                 NSArray<NSArray<NSData*>*>* _Nonnull selectedValues)
{
  NSMutableArray<id>* ret = [NSMutableArray arrayWithCapacity:keys.count];
  for (__block NSData* key in keys)
  {
    NSUInteger idx = [selectedValues indexOfObjectPassingTest:^(NSArray<NSData*>* obj, NSUInteger idx, BOOL* stop) {
      if ([obj[0] isEqualToData:key])
      {
        *stop = YES;
        return YES;
      }
      return NO;
    }];
    if (idx == NSNotFound)
      [ret addObject:[NSNull null]];
    else
      [ret addObject:[selectedValues objectAtIndex:idx][1]];
  }
  return ret;
}

static NSArray<NSArray<NSData*>*>* _Nullable retrieveCachedValues(sqlite3* handle,
                                                                  NSString* _Nonnull cmd,
                                                                  NSError* _Nullable* _Nonnull err)
{
  NSMutableArray<NSArray<NSData*>*>* selectedValues = [NSMutableArray array];
  sqlite3_stmt* stmt;

  int err_code = sqlite3_prepare_v2(handle, cmd.UTF8String, (int)cmd.length, &stmt, NULL);
  if (err_code != SQLITE_OK)
  {
    *err = TKR_createNSError(TKRDatastoreErrorDomain,
                             [NSString stringWithFormat:@"Failed to prepare statement: %s", sqlite3_errstr(err_code)],
                             translateSQLiteError(err_code));
    return nil;
  }
  for (err_code = sqlite3_step(stmt); err_code == SQLITE_ROW; err_code = sqlite3_step(stmt))
  {
    NSData* key = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:sqlite3_column_bytes(stmt, 0)];
    NSData* value = [NSData dataWithBytes:sqlite3_column_blob(stmt, 1) length:sqlite3_column_bytes(stmt, 1)];
    [selectedValues addObject:[NSArray arrayWithObjects:key, value, nil]];
  }

  sqlite3_finalize(stmt);
  if (err_code != SQLITE_DONE)
  {
    NSString* errMsg = [NSString stringWithCString:sqlite3_errstr(err_code) encoding:NSUTF8StringEncoding];
    *err = TKR_createNSError(TKRDatastoreErrorDomain, errMsg, translateSQLiteError(err_code));
    return nil;
  }
  return selectedValues;
}

@implementation TKRDatastore

- (nullable NSError*)createDeviceTable
{
  char const* cmd =
      "CREATE TABLE device ("
      "  id INTEGER PRIMARY KEY,"
      "  deviceblob BLOB NOT NULL"
      ")";
  sqlite3_exec(self.persistent_handle, cmd, NULL, NULL, NULL);
  return errorFromSQLite(self.persistent_handle);
}

- (nullable NSError*)createCacheTable
{
  char const* cmd =
      "CREATE TABLE cache ("
      "  key BLOB PRIMARY KEY,"
      "  value BLOB NOT NULL"
      ")";
  sqlite3_exec(self.cache_handle, cmd, NULL, NULL, NULL);
  return errorFromSQLite(self.cache_handle);
}

- (nullable NSError*)migratePersistentDb
{
  int version;
  NSError* err = dbVersion(self.persistent_handle, &version);
  if (err)
    return err;

  switch (version)
  {
  case 0:
    if ((err = [self createDeviceTable]))
      return err;
    if ((err = setDbVersion(self.persistent_handle, latestCacheVersion)))
      return err;
    // fallthrough
  case latestCacheVersion:
    return nil;
  default:
  {
    NSString* msg = [NSString
        stringWithFormat:@"device database version too recent, expected %d, got %d", latestDeviceVersion, version];
    return TKR_createNSError(TKRDatastoreErrorDomain, msg, TKRDatastoreErrorDatabaseTooRecent);
  }
  }
}

- (nullable NSError*)migrateCacheDb
{
  int version;
  NSError* err = dbVersion(self.cache_handle, &version);
  if (err)
    return err;

  switch (version)
  {
  case 0:
    if ((err = [self createCacheTable]))
      return err;
    if ((err = setDbVersion(self.cache_handle, latestCacheVersion)))
      return err;
    // fallthrough
  case latestCacheVersion:
    return nil;
  default:
  {
    NSString* msg = [NSString
        stringWithFormat:@"cache database version too recent, expected %d, got %d", latestCacheVersion, version];
    return TKR_createNSError(TKRDatastoreErrorDomain, msg, TKRDatastoreErrorDatabaseTooRecent);
  }
  }
}

- (nullable NSError*)migrate
{
  NSError* err = [self migratePersistentDb];
  if (err)
    return err;
  return [self migrateCacheDb];
}

+ (nullable TKRDatastore*)datastoreWithPersistentPath:(nonnull NSString*)persistentPath
                                            cachePath:(nonnull NSString*)cachePath
                                                error:(NSError* _Nullable* _Nonnull)err
{
  return [[TKRDatastore alloc] initWithPersistentPath:persistentPath cachePath:cachePath error:err];
}

- (instancetype _Nullable)initWithPersistentPath:(nonnull NSString*)persistentPath
                                       cachePath:(nonnull NSString*)cachePath
                                           error:(NSError* _Nullable* _Nonnull)err
{
  if (self = [super init])
  {
    sqlite3* tmp;
    if ((*err = openOrCreateDb(persistentPath, &tmp)))
      goto fail;
    self.persistent_handle = tmp;
    NSLog(@"persistent pointer = %p", self.persistent_handle);
    if ((*err = openOrCreateDb(cachePath, &tmp)))
      goto fail;
    self.cache_handle = tmp;
    if ((*err = [self migrate]))
      goto fail;
    NSLog(@"cache pointer = %p", self.cache_handle);
  }
  return self;

fail:
  sqlite3_close(self.persistent_handle);
  sqlite3_close(self.cache_handle);
  return nil;
}

- (nullable NSError*)nuke
{
  NSString* format = @"DELETE FROM %@";
  NSError* err;

  sqlite3_exec(
      self.persistent_handle, [NSString stringWithFormat:format, deviceTableName].UTF8String, NULL, NULL, NULL);
  if ((err = errorFromSQLite(self.persistent_handle)))
    return err;
  sqlite3_exec(self.cache_handle, [NSString stringWithFormat:format, cacheTableName].UTF8String, NULL, NULL, NULL);
  return errorFromSQLite(self.cache_handle);
}

- (void)close
{
  sqlite3_close(self.persistent_handle);
  sqlite3_close(self.cache_handle);
  self.persistent_handle = nil;
  self.cache_handle = nil;
}

- (nullable NSError*)cacheValues:(nonnull NSDictionary<NSData*, NSData*>*)keyValues
                      onConflict:(TKRDatastoreOnConflict)action
{
  if (keyValues.count == 0)
    return nil;
  NSString* cmd = buildCacheRequest(cacheTableName, keyValues, action);
  sqlite3_exec(self.cache_handle, cmd.UTF8String, NULL, NULL, NULL);
  return errorFromSQLite(self.cache_handle);
}

- (nullable NSArray<id>*)findCacheValuesWithKeys:(nonnull NSArray<NSData*>*)keys error:(NSError* _Nullable* _Nonnull)err
{
  *err = nil;
  if (keys.count == 0)
    return @[];

  NSString* cmd = buildFindCacheRequest(keys);
  NSArray<NSArray<NSData*>*>* values = retrieveCachedValues(self.cache_handle, cmd, err);

  if (*err)
    return nil;
  return setDifferenceToNull(keys, values);
}

- (nullable NSError*)setSerializedDevice:(nonnull NSData*)serializedDevice
{
  NSString* cmd = buildSetDeviceRequest(serializedDevice);
  sqlite3_exec(self.persistent_handle, cmd.UTF8String, NULL, NULL, NULL);
  return errorFromSQLite(self.persistent_handle);
}

- (nullable NSData*)serializedDeviceWithError:(NSError* _Nullable* _Nonnull)err
{
  NSString* cmd = [NSString stringWithFormat:@"SELECT deviceblob FROM %@ WHERE id = 1", deviceTableName];
  sqlite3_stmt* stmt;
  int err_code = sqlite3_prepare_v2(self.persistent_handle, cmd.UTF8String, -1, &stmt, NULL);
  if (err_code != SQLITE_OK)
  {
    *err = errorFromSQLite(self.persistent_handle);
    return nil;
  }

  err_code = sqlite3_step(stmt);
  if (err_code == SQLITE_DONE)
    return nil;
  if (err_code != SQLITE_ROW)
  {
    NSString* errMsg = [NSString stringWithCString:sqlite3_errstr(err_code) encoding:NSUTF8StringEncoding];
    *err = TKR_createNSError(TKRDatastoreErrorDomain, errMsg, translateSQLiteError(err_code));
    return nil;
  }
  NSData* ret = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:sqlite3_column_bytes(stmt, 0)];

  sqlite3_finalize(stmt);
  if ((*err = errorFromSQLite(self.persistent_handle)))
    return nil;
  return ret;
}

@end
