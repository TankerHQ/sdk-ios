#import "TKRVerification+Private.h"

#import <objc/runtime.h>

@implementation TKRVerification (Private)

@dynamic valuePrivate;
@dynamic type;

- (nonnull NSString*)passphrase
{
  return self.valuePrivate;
}

- (void)setPassphrase:(nonnull NSString*)passphrase
{
  self.valuePrivate = passphrase;
}

- (nonnull TKREmailVerification*)email
{
  return self.valuePrivate;
}

- (void)setEmail:(nonnull TKREmailVerification*)email
{
  self.valuePrivate = email;
}

- (nonnull TKRVerificationKey*)verificationKey
{
  return self.valuePrivate;
}

- (void)setVerificationKey:(nonnull TKRVerificationKey*)key
{
  self.valuePrivate = key;
}

- (nonnull NSString*)oidcIDToken
{
  return self.valuePrivate;
}

- (void)setOidcIDToken:(nonnull NSString*)token
{
  self.valuePrivate = token;
}

- (void)setValuePrivate:(id)value
{
  objc_setAssociatedObject(self, @selector(valuePrivate), value, OBJC_ASSOCIATION_RETAIN);
}

- (id)valuePrivate
{
  return objc_getAssociatedObject(self, @selector(valuePrivate));
}

- (void)setType:(TKRVerificationMethodType)value
{
  objc_setAssociatedObject(self, @selector(type), [NSNumber numberWithUnsignedInteger:value], OBJC_ASSOCIATION_RETAIN);
}

- (TKRVerificationMethodType)type
{
  NSNumber* n = objc_getAssociatedObject(self, @selector(type));
  return n.unsignedIntegerValue;
}

@end
