#include "ctanker.h"

tanker_http_request_handle_t* httpSendRequestCallback(
    tanker_http_request_t* crequest, void* data);
void httpCancelRequestCallback(
    tanker_http_request_t* request,
    tanker_http_request_handle_t* request_handle,
    void* data);
