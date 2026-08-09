import Foundation
import XCTest

/// Fails closed when an Xcode unit test attempts an unmocked network request.
final class StrictNetworkGuard: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        XCTFail("Unmocked network request: \(request.url?.absoluteString ?? "unknown")")
        client?.urlProtocol(
            self,
            didFailWithError: URLError(.notConnectedToInternet)
        )
    }

    override func stopLoading() {}
}

@objc(TestSuiteSetup)
final class TestSuiteSetup: NSObject {
    override init() {
        super.init()
        URLProtocol.registerClass(StrictNetworkGuard.self)
    }
}
