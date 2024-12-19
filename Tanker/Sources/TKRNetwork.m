#include <Tanker/TKRNetwork.h>
#include <Tanker/TKRTanker.h>
#import <Tanker/Utils/TKRUtils.h>

#include <libkern/OSAtomic.h>

#include <Tanker/ctanker.h>

@interface HTTPClient : NSObject <NSURLSessionTaskDelegate>

@property int32_t _lastId;
@property NSMutableDictionary* _requests;

+ (instancetype)sharedInstance;
- (instancetype)init;
- (tanker_http_request_handle_t*)sendRequest:(tanker_http_request_t*)crequest withData:(void*)data;
- (void)cancelRequest:(tanker_http_request_t*)request
           withHandle:(tanker_http_request_handle_t*)request_handle
             withData:(void*)data;

@end

@implementation HTTPClient

@synthesize _lastId;
@synthesize _requests;

+ (instancetype)sharedInstance
{
  static HTTPClient* sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init
{
  self = [super init];
  if (self != nil)
  {
    _lastId = 0;
    _requests = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (tanker_http_request_handle_t*)sendRequest:(tanker_http_request_t*)crequest withData:(void*)data
{
  NSURL* url = [NSURL URLWithString:[NSString stringWithUTF8String:crequest->url]];
  NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
  req.HTTPMethod = [NSString stringWithUTF8String:crequest->method];
  // Cast to void* to discard the constness
  req.HTTPBody = [NSData dataWithBytesNoCopy:(void*)crequest->body length:crequest->body_size freeWhenDone:NO];

  for (int i = 0; i < crequest->num_headers; ++i)
  {
    tanker_http_header_t* hdr = &crequest->headers[i];
    [req addValue:[NSString stringWithUTF8String:hdr->value]
        forHTTPHeaderField:[NSString stringWithUTF8String:hdr->name]];
  }

  TKRTanker* tanker = (__bridge TKRTanker*)data;
  [req setValue:tanker.options.sdkType forHTTPHeaderField:@"X-Tanker-SdkType"];
  [req setValue:[TKRTanker versionString] forHTTPHeaderField:@"X-Tanker-SdkVersion"];

  NSNumber* requestId = [NSNumber numberWithInteger:OSAtomicIncrement32(&_lastId)];

  NSURLSessionConfiguration* configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  NSURLSession* session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];

  NSURLSessionDataTask* task =
      [session dataTaskWithRequest:req
                 completionHandler:^(NSData* data, NSURLResponse* baseResponse, NSError* error) {
                   NSHTTPURLResponse* response = (NSHTTPURLResponse*)baseResponse;

                   tanker_http_response_t cresponse;

                   if (error)
                   {
                     cresponse.error_msg = error.localizedDescription.UTF8String;
                     cresponse.headers = NULL;
                     cresponse.num_headers = 0;
                     cresponse.body = NULL;
                     cresponse.body_size = 0;
                   }
                   else
                   {
                     cresponse.num_headers = (int32_t)response.allHeaderFields.count;
                     cresponse.headers = malloc(sizeof(tanker_http_header_t) * response.allHeaderFields.count);
                     int i = 0;
                     for (NSString* key in response.allHeaderFields)
                     {
                       cresponse.headers[i++] = (tanker_http_header_t){
                           .name = key.UTF8String,
                           .value = ((NSString*)response.allHeaderFields[key]).UTF8String,
                       };
                     }

                     cresponse.error_msg = NULL;
                     cresponse.status_code = (int32_t)response.statusCode;
                     cresponse.body = data.bytes;
                     cresponse.body_size = data.length;
                   }

                   @synchronized(self)
                   {
                     NSURLSessionDataTask* task = [self->_requests objectForKey:requestId];
                     if (task)
                     {
                       tanker_http_handle_response(crequest, &cresponse);
                       [self->_requests removeObjectForKey:requestId];
                     }
                   }

                   free(cresponse.headers);
                 }];

  @synchronized(self)
  {
    [self->_requests setObject:task forKey:requestId];
  }

  [task resume];
  [session finishTasksAndInvalidate];

  return (tanker_http_request_handle_t*)TKR_numberToPtr(requestId);
}

// Prevent URLSession from following redirections:
// - sdk-native will handle the redirection response
- (void)URLSession:(NSURLSession*)session
                          task:(NSURLSessionTask*)task
    willPerformHTTPRedirection:(NSHTTPURLResponse*)response
                    newRequest:(NSURLRequest*)request
             completionHandler:(void (^)(NSURLRequest*))completionHandler
{
  completionHandler(NULL);
}

- (void)cancelRequest:(tanker_http_request_t*)request
           withHandle:(tanker_http_request_handle_t*)request_handle
             withData:(void*)data;
{
  NSNumber* requestId = TKR_ptrToNumber(request_handle);
  @synchronized(self)
  {
    NSURLSessionDataTask* task = [self->_requests objectForKey:requestId];
    if (task)
    {
      [task cancel];
      [self->_requests removeObjectForKey:requestId];
    }
  }
}

@end

tanker_http_request_handle_t* httpSendRequestCallback(tanker_http_request_t* request, void* data)
{
  return [[HTTPClient sharedInstance] sendRequest:request withData:data];
}

void httpCancelRequestCallback(tanker_http_request_t* request, tanker_http_request_handle_t* request_handle, void* data)
{
  [[HTTPClient sharedInstance] cancelRequest:request withHandle:request_handle withData:data];
}
