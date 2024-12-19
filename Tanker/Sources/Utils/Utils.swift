internal func getExpectedString(_ expected: OpaquePointer) throws -> String {
  let expectedRawPtr = try unwrapAndFreeExpected(expected)!;
  // NOTE: freeWhenDone will call free() instead of tanker_free(), but this should be fine
  return NSString(
    bytesNoCopy: expectedRawPtr,
    length: strlen(expectedRawPtr),
    encoding: String.Encoding.utf8.rawValue,
    freeWhenDone: true
  )! as String
}

internal func getFutureError(_ fut: OpaquePointer) -> NSError? {
  guard let errPtr = tanker_future_get_error(fut) else {
    return nil;
  }
  let err: tanker_error_t = errPtr.pointee;
  return TKR_createNSError(UInt(err.code), String(cString: err.message)) as NSError;
}

func resolvePromise(_ fut: OpaquePointer?, _ arg: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
  let maybeErr = getFutureError(fut!);
  var ptrValue: NSNumber? = nil;

  if maybeErr == nil {
    ptrValue = NSNumber(value: UInt(bitPattern: tanker_future_get_voidptr(fut)));
  }

  DispatchQueue.main.async(execute: {
    let adapter = Unmanaged<AnyObject>.fromOpaque(arg!).takeRetainedValue() as! Adapter;
    adapter(ptrValue, maybeErr);
  });
  return nil;
};

public func unwrapAndFreeExpected(_ expected: OpaquePointer) throws -> UnsafeMutableRawPointer?
{
  if let err = TKR_getOptionalFutureError(UnsafeMutableRawPointer(expected)) as NSError? {
    tanker_future_destroy(expected);
    throw err;
  }

  let ptr: UnsafeMutableRawPointer? = tanker_future_get_voidptr(expected);
  tanker_future_destroy(expected);

  return ptr;
}
