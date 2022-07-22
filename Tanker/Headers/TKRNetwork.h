struct tanker_http_request;
typedef struct tanker_http_request tanker_http_request_t;
typedef void tanker_http_request_handle_t;

tanker_http_request_handle_t* httpSendRequestCallback(
    tanker_http_request_t* crequest, void* data);
void httpCancelRequestCallback(
    tanker_http_request_t* request,
    tanker_http_request_handle_t* request_handle,
    void* data);
