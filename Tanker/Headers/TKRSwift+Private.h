// In sdk-ios itself, we should import Tanker/Tanker-Swift.h
// But when exporting the pod locally (e.g. for React Native),
// this changes the rules for where the header is generated
#if __has_include(<Tanker/Tanker-Swift.h>)
#import <Tanker/Tanker-Swift.h>
#else
#import <Tanker-Swift.h>
#endif
