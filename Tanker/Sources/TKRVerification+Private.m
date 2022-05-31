#import <Tanker/TKRVerification+Private.h>

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

- (nonnull NSString*)e2ePassphrase
{
  return self.valuePrivate;
}

- (void)setE2ePassphrase:(nonnull NSString*)e2ePassphrase
{
  self.valuePrivate = e2ePassphrase;
}

- (nonnull TKREmailVerification*)email
{
  return self.valuePrivate;
}

- (void)setEmail:(nonnull TKREmailVerification*)email
{
  self.valuePrivate = email;
}

- (nonnull TKRPhoneNumberVerification*)phoneNumber
{
  return self.valuePrivate;
}

- (void)setPhoneNumber:(nonnull TKRPhoneNumberVerification*)phoneNumber
{
  self.valuePrivate = phoneNumber;
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

- (nonnull NSString*)preverifiedEmail
{
  return self.valuePrivate;
}

- (void)setPreverifiedEmail:(nonnull NSString*)preverifiedEmail
{
  self.valuePrivate = preverifiedEmail;
}

- (nonnull NSString*)preverifiedPhoneNumber
{
  return self.valuePrivate;
}

- (void)setPreverifiedPhoneNumber:(nonnull NSString*)preverifiedPhoneNumber
{
  self.valuePrivate = preverifiedPhoneNumber;
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
