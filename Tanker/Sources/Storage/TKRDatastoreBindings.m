#import <Tanker/Storage/TKRDatastoreBindings.h>

#import <Tanker/Storage/TKRDatastore.h>

#import "ctanker/datastore.h"

static void report_error(void* error_handle, NSError* _Nonnull err)
{
  tanker_datastore_report_error(error_handle, err.code, err.localizedDescription.UTF8String);
}

void TKR_datastore_open(void* error_handle, void** datastore, char const* data_path, char const* cache_path)
{
  NSString* persistentPath = [NSString stringWithUTF8String:data_path];
  NSString* cachePath = [NSString stringWithUTF8String:cache_path];

  NSError* err;

  TKRDatastore* store = [TKRDatastore datastoreWithPersistentPath:persistentPath cachePath:cachePath error:&err];
  if (err)
    return report_error(error_handle, err);
  *datastore = (__bridge_retained void*)store;
}

void TKR_datastore_close(void* datastore)
{
  TKRDatastore* store = (__bridge_transfer TKRDatastore*)datastore;
  [store close];
}

void TKR_datastore_nuke(void* datastore, void* error_handle)
{
  TKRDatastore* store = (__bridge TKRDatastore*)datastore;
  NSError* err = [store nuke];
  if (err)
    report_error(error_handle, err);
}

void TKR_datastore_put_serialized_device(void* datastore,
                                         void* error_handle,
                                         uint8_t const* serialized_device,
                                         uint32_t serialized_device_size)
{
  TKRDatastore* store = (__bridge TKRDatastore*)datastore;

  NSData* serializedDevice = [NSData dataWithBytesNoCopy:(void*)serialized_device
                                                  length:serialized_device_size
                                            freeWhenDone:NO];
  NSError* err = [store setSerializedDevice:serializedDevice];
  if (err)
    report_error(error_handle, err);
}

void TKR_datastore_find_serialized_device(void* datastore, void* result_handle)
{
  TKRDatastore* store = (__bridge TKRDatastore*)datastore;
  NSError* err;

  NSData* serializedDevice = [store serializedDeviceWithError:&err];
  if (err)
    return report_error(result_handle, err);

  if (!serializedDevice)
    return;
  uint8_t* buffer = tanker_datastore_allocate_device_buffer(result_handle, (uint32_t)serializedDevice.length);
  memcpy(buffer, serializedDevice.bytes, serializedDevice.length);
}

void TKR_datastore_put_cache_values(void* datastore,
                                    void* error_handle,
                                    uint8_t const* const* keys,
                                    uint32_t const* key_sizes,
                                    uint8_t const* const* values,
                                    uint32_t const* value_sizes,
                                    uint32_t elem_count,
                                    uint8_t on_conflict)
{
  TKRDatastore* store = (__bridge TKRDatastore*)datastore;

  NSMutableDictionary<NSData*, NSData*>* keyValues = [NSMutableDictionary dictionaryWithCapacity:elem_count];

  for (int i = 0; i < elem_count; ++i)
  {
    NSData* key = [NSData dataWithBytesNoCopy:(void*)keys[i] length:key_sizes[i] freeWhenDone:NO];
    NSData* value = [NSData dataWithBytesNoCopy:(void*)values[i] length:value_sizes[i] freeWhenDone:NO];
    [keyValues setObject:value forKey:key];
  }

  NSError* err = [store cacheValues:keyValues onConflict:(TKRDatastoreOnConflict)on_conflict];
  if (err)
    report_error(error_handle, err);
}

void TKR_datastore_find_cache_values(
    void* datastore, void* result_handle, uint8_t const* const* keys, uint32_t const* key_sizes, uint32_t elem_count)
{
  TKRDatastore* store = (__bridge TKRDatastore*)datastore;

  NSMutableArray<NSData*>* k = [NSMutableArray arrayWithCapacity:elem_count];

  for (int i = 0; i < elem_count; ++i)
    [k addObject:[NSData dataWithBytesNoCopy:(void*)keys[i] length:key_sizes[i] freeWhenDone:NO]];

  NSError* err;
  NSArray<id>* values = [store findCacheValuesWithKeys:k error:&err];

  if (err)
    return report_error(result_handle, err);

  uint32_t* size_ptrs = (uint32_t*)malloc(sizeof(uint32_t) * values.count);
  for (int i = 0; i < values.count; ++i)
  {
    if (values[i] == [NSNull null])
      size_ptrs[i] = TANKER_DATASTORE_ALLOCATION_NONE;
    else
      size_ptrs[i] = (uint32_t)((NSData*)values[i]).length;
  }
  uint8_t** out_ptrs = (uint8_t**)malloc(sizeof(uint8_t*) * values.count);

  tanker_datastore_allocate_cache_buffer(result_handle, out_ptrs, size_ptrs);

  for (int i = 0; i < values.count; ++i)
  {
    if (values[i] != [NSNull null])
    {
      NSData* data = (NSData*)values[i];
      memcpy(out_ptrs[i], data.bytes, data.length);
    }
  }

  free(size_ptrs);
  free(out_ptrs);
}
