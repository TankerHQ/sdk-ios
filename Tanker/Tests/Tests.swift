import Foundation

import XCTest
@testable import Tanker

final class SwiftTests: XCTestCase {
    func testNativeVersion() throws {
        XCTAssertNotEqual(TKRTanker.nativeVersionString().count, 0)
    }
}

