import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(homekit_webos_picture_modeTests.allTests),
    ]
}
#endif
