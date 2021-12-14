#include <stdint.h>

void TKR_datastore_open(void* error_handle, void** datastore, char const* data_path, char const* cache_path);
void TKR_datastore_close(void* db_handle);
void TKR_datastore_nuke(void* datastore, void* error_handle);
void TKR_datastore_put_serialized_device(void* db_handle,
                                         void* error_handle,
                                         uint8_t const* serialized_device,
                                         uint32_t serialized_device_size);
void TKR_datastore_find_serialized_device(void* datastore, void* result_handle);
void TKR_datastore_put_cache_values(void* datastore,
                                    void* error_handle,
                                    uint8_t const* const* keys,
                                    uint32_t const* key_sizes,
                                    uint8_t const* const* values,
                                    uint32_t const* value_sizes,
                                    uint32_t elem_count,
                                    uint8_t on_conflict);
void TKR_datastore_find_cache_values(
    void* datastore, void* result_handle, uint8_t const* const* keys, uint32_t const* key_sizes, uint32_t elem_count);
