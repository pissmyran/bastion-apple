// Synthetic Keychain and HTTP responses let the actual store run on Linux.
enum Keychain {
    private static let lock = NSLock()
    private static var values: [String: String] = [:]
    static var beforeSet: (() -> Void)?

    static func set(_ value: String, for key: String) -> Bool {
        beforeSet?()
        lock.lock(); defer { lock.unlock() }
        values[key] = value
        return true
    }
    static func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    static func getAsync(_ key: String) async -> String? { get(key) }
    static func delete(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
        return true
    }
}

final class TokenProtocol: URLProtocol {
    static var handler: (() -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TokenStoreTests: XCTestCase {
    private let provider = "test-provider"
    private let endpoint = URL(string: "https://test.invalid/token")!
    private let success = (200, "{\"access_token\":\"refreshed\",\"refresh_token\":\"rotated\",\"expires_in\":3600}")

    override func setUp() {
        super.setUp()
        _ = URLProtocol.registerClass(TokenProtocol.self)
        Keychain.beforeSet = nil
        _ = TVOAuthTokenStore.logout(provider)
    }
    override func tearDown() {
        Keychain.beforeSet = nil
        _ = TVOAuthTokenStore.logout(provider)
        URLProtocol.unregisterClass(TokenProtocol.self)
        super.tearDown()
    }
    private func token(_ access: String, expired: Bool = false, refresh: String? = "refresh") -> StoredOAuthToken {
        StoredOAuthToken(response: OAuthTokenResponse(accessToken: access, refreshToken: refresh, expiresIn: expired ? 0 : 3600))
    }
    private func beginRefresh(response: (Int, String)) throws -> (DispatchSemaphore, DispatchSemaphore, XCTestExpectation) {
        try TVOAuthTokenStore.save(token("old", expired: true), for: provider)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        TokenProtocol.handler = {
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return response
        }
        let done = expectation(description: "refresh rejected")
        DispatchQueue.global().async {
            defer { done.fulfill() }
            do {
                _ = try TVOAuthTokenStore.validAccessToken(for: self.provider, tokenEndpoint: self.endpoint, clientID: "client")
                XCTFail("stale refresh returned a token")
            } catch OAuthError.notLoggedIn {
            } catch { XCTFail("unexpected error: \(error)") }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        return (started, release, done)
    }
    func testLogoutRejectsPendingRefresh() throws {
        let (_, release, done) = try beginRefresh(response: success)
        XCTAssertTrue(TVOAuthTokenStore.logout(provider))
        release.signal()
        wait(for: [done], timeout: 5)
        XCTAssertNil(TVOAuthTokenStore.load(for: provider))
    }
    func testNewLoginSurvivesPendingRefreshAndInvalidGrant() throws {
        for response in [success, (400, "{\"error\":\"invalid_grant\"}")] {
            let (_, release, done) = try beginRefresh(response: response)
            try TVOAuthTokenStore.save(token("new-login"), for: provider)
            release.signal()
            wait(for: [done], timeout: 5)
            XCTAssertEqual(TVOAuthTokenStore.load(for: provider)?.accessToken, "new-login")
        }
    }
    func testCurrentInvalidGrantDeletesCredential() throws {
        try TVOAuthTokenStore.save(token("old", expired: true), for: provider)
        TokenProtocol.handler = { (400, "{\"error\":\"invalid_grant\"}") }
        XCTAssertThrowsError(try TVOAuthTokenStore.validAccessToken(for: provider, tokenEndpoint: endpoint, clientID: "client"))
        XCTAssertNil(TVOAuthTokenStore.load(for: provider))
    }
    func testRefreshesAreSerializedPerProvider() throws {
        try TVOAuthTokenStore.save(token("old", expired: true), for: provider)
        try TVOAuthTokenStore.save(token("other"), for: "other-provider")
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let countLock = NSLock()
        var requests = 0
        TokenProtocol.handler = {
            countLock.lock(); requests += 1; countLock.unlock()
            started.signal()
            _ = release.wait(timeout: .now() + 5)
            return self.success
        }
        let first = expectation(description: "first refresh")
        let second = expectation(description: "second refresh")
        for done in [first, second] {
            DispatchQueue.global().async {
                XCTAssertEqual(try? TVOAuthTokenStore.validAccessToken(for: self.provider, tokenEndpoint: self.endpoint, clientID: "client"), "refreshed")
                done.fulfill()
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(try TVOAuthTokenStore.validAccessToken(for: "other-provider", tokenEndpoint: endpoint, clientID: "client"), "other")
        release.signal()
        wait(for: [first, second], timeout: 5)
        countLock.lock(); let requestCount = requests; countLock.unlock()
        XCTAssertEqual(requestCount, 1)
        _ = TVOAuthTokenStore.logout("other-provider")
    }
    func testRefreshThenLogoutWaitsForCredentialWrite() throws {
        try TVOAuthTokenStore.save(token("old", expired: true), for: provider)
        TokenProtocol.handler = { self.success }
        let writing = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        Keychain.beforeSet = { writing.signal(); _ = release.wait(timeout: .now() + 5) }
        let refreshed = expectation(description: "refresh completed")
        DispatchQueue.global().async {
            defer { refreshed.fulfill() }
            XCTAssertEqual(try? TVOAuthTokenStore.validAccessToken(for: self.provider, tokenEndpoint: self.endpoint, clientID: "client"), "refreshed")
        }
        XCTAssertEqual(writing.wait(timeout: .now() + 5), .success)
        let logoutStarted = DispatchSemaphore(value: 0)
        let loggedOut = expectation(description: "logout completed")
        let logoutFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            logoutStarted.signal()
            XCTAssertTrue(TVOAuthTokenStore.logout(self.provider))
            logoutFinished.signal()
            loggedOut.fulfill()
        }
        XCTAssertEqual(logoutStarted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(logoutFinished.wait(timeout: .now() + 0.1), .timedOut)
        release.signal()
        wait(for: [refreshed, loggedOut], timeout: 5)
        XCTAssertNil(TVOAuthTokenStore.load(for: provider))
    }
}

XCTMain([testCase([
    ("testLogoutRejectsPendingRefresh", TokenStoreTests.testLogoutRejectsPendingRefresh),
    ("testNewLoginSurvivesPendingRefreshAndInvalidGrant", TokenStoreTests.testNewLoginSurvivesPendingRefreshAndInvalidGrant),
    ("testCurrentInvalidGrantDeletesCredential", TokenStoreTests.testCurrentInvalidGrantDeletesCredential),
    ("testRefreshesAreSerializedPerProvider", TokenStoreTests.testRefreshesAreSerializedPerProvider),
    ("testRefreshThenLogoutWaitsForCredentialWrite", TokenStoreTests.testRefreshThenLogoutWaitsForCredentialWrite),
])])
