#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import <Tanker/TKRError.h>
#import <Tanker/TKRStreamBase.h>
#import <Tanker/Utils/TKRUtils.h>
 
@interface TKRStreamBase () <NSStreamDelegate> {
  __weak id<NSStreamDelegate> delegate;
  
  CFReadStreamClientCallBack clientCallback;
  CFStreamClientContext clientContext;
  CFOptionFlags requestedEventsFlags;
  
  NSStreamEvent pendingEvents;
  CFRunLoopSourceRef runLoopSource;
  CFMutableSetRef runLoopsSet;
  CFMutableDictionaryRef runLoopsModes;
  NSStreamStatus status;
  NSError* error;
}
@end

@implementation TKRStreamBase

#pragma mark - TKRStreamBase

- (nullable instancetype)init
{
  if (self = [super init])
  {
    self->clientCallback = NULL;
    self->clientContext = (CFStreamClientContext) { 0 };
    
    self->status = NSStreamStatusNotOpen;
    
    CFRunLoopSourceContext runLoopSourceContext = {
      0, (__bridge void *)(self), NULL, NULL, NULL, NULL, NULL, NULL, NULL, CFRunLoopPerformCallBack
    };
    self->runLoopSource = CFRunLoopSourceCreate(NULL, 0, &runLoopSourceContext);
    
    CFSetCallBacks runLoopsSetCallBacks = {
      0, NULL, NULL, NULL, CFEqual, CFHash // CFRunLoop retains CFStream, so we will not.
    };
    self->runLoopsSet = CFSetCreateMutable(NULL, 0, &runLoopsSetCallBacks);
    CFDictionaryKeyCallBacks runLoopsModesKeyCallBacks = {
      0, NULL, NULL, NULL, CFEqual, CFHash
    };
    CFDictionaryValueCallBacks runLoopsModesValueCallBacks = {
      0, CFRetainCallBack, CFReleaseCallBack, NULL, CFEqual
    };
    self->runLoopsModes = CFDictionaryCreateMutable(NULL, 0, &runLoopsModesKeyCallBacks, &runLoopsModesValueCallBacks);
    
    [self setDelegate:self];
  }
  return self;
}

- (void)setStatus:(NSStreamStatus)aStatus {
  self->status = aStatus;
}

- (void)setError:(NSError *)anError {
  self->status = NSStreamStatusError;
  [self enqueueEvent:NSStreamEventErrorOccurred];
  self->error = anError;
}

- (BOOL)isOpen {
    return (status != NSStreamStatusNotOpen &&
            status != NSStreamStatusOpening &&
            status != NSStreamStatusClosed &&
            status != NSStreamStatusError);
    
}

#pragma mark - NSInputStream

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)maxLength {
  if (![self isOpen]) {
    NSLog(@"%@: Stream is not open, status %ld.", self, (long)self->status);
    return -1;
  }
  if (self->status != NSStreamStatusAtEnd) {
    self->status = NSStreamStatusAtEnd;
    [self enqueueEvent:NSStreamEventEndEncountered];
  }
  return 0;
}

- (BOOL)getBuffer:(uint8_t **)buffer length:(NSUInteger *)len {
  return NO;
}

#pragma mark - NSStream

- (void)open {
  if (self->status != NSStreamStatusNotOpen) {
    NSLog(@"%@: stream already open", self);
    return;
  }
  self->status = NSStreamStatusOpen;
}

- (void)close {
  if (![self isOpen])
    return;
  self->status = NSStreamStatusClosed;
  [self unscheduleFromAllRunLoops];
}

- (id <NSStreamDelegate>)delegate {
  return self->delegate;
}

- (void)setDelegate:(id<NSStreamDelegate>)aDelegate {
  if (aDelegate == nil) {
    self->delegate = self;
  } else {
    self->delegate = aDelegate;
  }
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [self scheduleInCFRunLoop:[aRunLoop getCFRunLoop] forMode:(CFStringRef) mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [self unscheduleFromCFRunLoop:[aRunLoop getCFRunLoop] forMode:(CFStringRef) mode];
}

- (id)propertyForKey:(NSString *)key {
  return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key {
  return NO;
}

- (NSStreamStatus)streamStatus {
  return self->status;
}

- (NSError *)streamError {
  return self->error;
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
  if (aStream == self) {
    switch (eventCode) {
      case NSStreamEventOpenCompleted:
        if (self->requestedEventsFlags & kCFStreamEventOpenCompleted) {
          self->clientCallback((__bridge CFReadStreamRef)self,
                               kCFStreamEventOpenCompleted,
                               self->clientContext.info);
        }
        break;

      case NSStreamEventHasBytesAvailable:
        if (self->requestedEventsFlags & kCFStreamEventHasBytesAvailable) {
          self->clientCallback((__bridge CFReadStreamRef)self,
                               kCFStreamEventHasBytesAvailable,
                               self->clientContext.info);
        }
        break;

      case NSStreamEventErrorOccurred:
        if (self->requestedEventsFlags & kCFStreamEventErrorOccurred) {
          self->clientCallback((__bridge CFReadStreamRef)self,
                               kCFStreamEventErrorOccurred,
                               self->clientContext.info);
        }
        break;

      case NSStreamEventEndEncountered:
        if (self->requestedEventsFlags & kCFStreamEventEndEncountered) {
          self->clientCallback((__bridge CFReadStreamRef)self,
                               kCFStreamEventEndEncountered,
                               self->clientContext.info);
        }
        break;

      default:
        break;
    }
  }
}

#pragma mark - NSObject

+ (BOOL)resolveInstanceMethod:(SEL)selector {
    NSString *name = NSStringFromSelector(selector);
    if ([name hasPrefix:@"_"]) {
        name = [name substringFromIndex:1];
        SEL aSelector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(self, aSelector);
        if (method) {
            class_addMethod(self,
                            selector,
                            method_getImplementation(method),
                            method_getTypeEncoding(method));
            return YES;
        }
    }
    return [super resolveInstanceMethod:selector];
}


- (void)dealloc {
  if ([self isOpen]) {
    [self close];
  }
  if (self->clientContext.release) {
    self->clientContext.release(self->clientContext.info);
  }
  CFRelease(self->runLoopSource);
  CFRelease(self->runLoopsSet);
  CFRelease(self->runLoopsModes);
}

#pragma mark - CF callbacks

static const void *CFRetainCallBack(CFAllocatorRef allocator, const void *value) { return CFRetain(value); }
static void CFReleaseCallBack(CFAllocatorRef allocator, const void *value) { CFRelease(value); }

void CFRunLoopPerformCallBack(void *info) {
    TKRStreamBase *stream = (__bridge TKRStreamBase *)info;
    [stream streamEventTrigger];
}

#pragma mark - CFReadStream undocumented

- (void)_scheduleInCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode {
    CFReadStreamScheduleWithRunLoop((CFReadStreamRef)self, aRunLoop, aMode);
}

- (void)_unscheduleFromCFRunLoop:(CFRunLoopRef)aRunLoop forMode:(CFStringRef)aMode {
    CFReadStreamUnscheduleFromRunLoop((CFReadStreamRef)self, aRunLoop, aMode);
}

- (BOOL)_setCFClientFlags:(CFOptionFlags)inOptionFlags
                 callback:(CFReadStreamClientCallBack)inClientCallback
                  context:(CFStreamClientContext *)inClientContext {
  if (inClientContext && inClientContext->version != 0) {
      return NO;
  }

  if (inClientCallback != NULL) {
    self->requestedEventsFlags = inOptionFlags;
    self->clientCallback = inClientCallback;
    memcpy(&self->clientContext, inClientContext, sizeof(CFStreamClientContext));

    if (self->clientContext.info && self->clientContext.retain) {
      self->clientContext.retain(self->clientContext.info);
    }
  } else {
    self->requestedEventsFlags = kCFStreamEventNone;
    self->clientCallback = NULL;
    if (self->clientContext.info && self->clientContext.release) {
      self->clientContext.release(self->clientContext.info);
    }

    memset(&self->clientContext, 0, sizeof(CFStreamClientContext));
  }

  return YES;
}

#pragma mark - CFReadStream run loop

- (void)enqueueEvent:(NSStreamEvent)event {
  self->pendingEvents |= event;
  CFRunLoopSourceSignal(self->runLoopSource);
  [self enumerateRunLoopsUsingBlock:^(CFRunLoopRef runLoop) {
      CFRunLoopWakeUp(runLoop);
  }];
}

- (NSStreamEvent)dequeueEvent {
  if (self->pendingEvents == NSStreamEventNone) {
      return NSStreamEventNone;
  }
  NSStreamEvent event = 1UL << __builtin_ctz(self->pendingEvents);
  self->pendingEvents ^= event;
  return event;
}

- (void)streamEventTrigger {
  if (self->status == NSStreamStatusClosed) {
    return;
  }
  NSStreamEvent event = [self dequeueEvent];
  while (event != NSStreamEventNone) {
    if ([self->delegate respondsToSelector:@selector(stream:handleEvent:)]) {
      [self->delegate stream:self handleEvent:event];
    }
    event = [self dequeueEvent];
  }
}

- (void)enumerateRunLoopsUsingBlock:(void (^)(CFRunLoopRef runLoop))block {
    CFIndex runLoopsCount = CFSetGetCount(self->runLoopsSet);
    if (runLoopsCount > 0) {
        CFTypeRef runLoops[runLoopsCount];
        CFSetGetValues(self->runLoopsSet, runLoops);
        for (CFIndex i = 0; i < runLoopsCount; ++i) {
            block((CFRunLoopRef)runLoops[i]);
        }
    }
}

- (void)addMode:(CFStringRef)mode forRunLoop:(CFRunLoopRef)runLoop {
    CFMutableSetRef modes = NULL;
    if (!CFDictionaryContainsKey(self->runLoopsModes, runLoop)) {
        CFSetCallBacks modesSetCallBacks = {
            0, CFRetainCallBack, CFReleaseCallBack, NULL, CFEqual, CFHash
        };
        modes = CFSetCreateMutable(NULL, 0, &modesSetCallBacks);
        CFDictionaryAddValue(self->runLoopsModes, runLoop, modes);
    } else {
        modes = (CFMutableSetRef)CFDictionaryGetValue(self->runLoopsModes, runLoop);
    }
    CFStringRef modeCopy = CFStringCreateCopy(NULL, mode);
    CFSetAddValue(modes, modeCopy);
    CFRelease(modeCopy);
}

- (void)removeMode:(CFStringRef)mode forRunLoop:(CFRunLoopRef)runLoop {
    if (!CFDictionaryContainsKey(self->runLoopsModes, runLoop)) {
        return;
    }
    CFMutableSetRef modes = (CFMutableSetRef)CFDictionaryGetValue(self->runLoopsModes, runLoop);
    CFSetRemoveValue(modes, mode);
}

- (void)scheduleInCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)mode {
    CFSetAddValue(self->runLoopsSet, runLoop);
    [self addMode:mode forRunLoop:runLoop];
    CFRunLoopAddSource(runLoop, self->runLoopSource, mode);
}

- (void)unscheduleFromCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)mode {
    CFRunLoopRemoveSource(runLoop, self->runLoopSource, mode);
    [self removeMode:mode forRunLoop:runLoop];
    CFSetRemoveValue(self->runLoopsSet, runLoop);
}

- (void)unscheduleFromAllRunLoops {
    [self enumerateRunLoopsUsingBlock:^(CFRunLoopRef runLoop) {
        CFMutableSetRef runLoopModesSet = (CFMutableSetRef)CFDictionaryGetValue(self->runLoopsModes, runLoop);
        CFIndex runLoopModesCount = CFSetGetCount(runLoopModesSet);
        if (runLoopModesCount > 0) {
            CFTypeRef runLoopModes[runLoopModesCount];
            CFSetGetValues(runLoopModesSet, runLoopModes);
            for (CFIndex j = 0; j < runLoopModesCount; ++j) {
                [self unscheduleFromCFRunLoop:runLoop forMode:(CFStringRef)runLoopModes[j]];
            }
        }
    }];
}

@end
