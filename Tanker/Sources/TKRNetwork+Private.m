#include <Tanker/TKRNetwork+Private.h>
#import <Tanker/TKRUtils+Private.h>

#include <libkern/OSAtomic.h>

@interface HTTPClient : NSObject

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
  req.HTTPBody = [NSData dataWithBytesNoCopy:(void*)crequest->body length:crequest->body_size freeWhenDone:false];
  [req addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
  if (crequest->authorization)
    [req addValue:[NSString stringWithUTF8String:crequest->authorization] forHTTPHeaderField:@"Authorization"];
  if (crequest->instance_id)
    [req addValue:[NSString stringWithUTF8String:crequest->instance_id] forHTTPHeaderField:@"X-Tanker-Instanceid"];

  NSNumber* requestId = [NSNumber numberWithInteger:OSAtomicIncrement32(&_lastId)];
  NSURLSessionDataTask* task =
      [[NSURLSession sharedSession] dataTaskWithRequest:req
                                      completionHandler:^(NSData* data, NSURLResponse* baseResponse, NSError* error) {
                                        NSHTTPURLResponse* response = (NSHTTPURLResponse*)baseResponse;

                                        tanker_http_response_t cresponse;

                                        if (error)
                                        {
                                          cresponse.error_msg = error.localizedDescription.UTF8String;
                                        }
                                        else
                                        {
                                          cresponse.error_msg = NULL;
                                          cresponse.status_code = (int32_t)response.statusCode;
                                          cresponse.content_type = response.MIMEType.UTF8String;
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
                                      }];

  @synchronized(self)
  {
    [self->_requests setObject:task forKey:requestId];
  }

  [task resume];

  return (tanker_http_request_handle_t*)numberToPtr(requestId);
}

- (void)cancelRequest:(tanker_http_request_t*)request
           withHandle:(tanker_http_request_handle_t*)request_handle
             withData:(void*)data;
{
  NSNumber* requestId = ptrToNumber(request_handle);
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
