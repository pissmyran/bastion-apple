import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOConcurrencyHelpers
import XCTest
@testable import SSHCore

/// Riktiga nätverksanrop mot en pinnad, oföränderlig GitHub-tag (inte ett
/// mockat svar) — samma rigör som repots övriga "verifierat mot RIKTIGT
/// X"-tester. `raw.githubusercontent.com/torvalds/linux/v6.6/COPYING` ändras
/// aldrig (tagg-pinnad), så testet är deterministiskt trots att det går mot
/// internet. Checksumman nedan verifierades separat (`curl` + `sha256sum`)
/// INNAN testet skrevs — testet bevisar alltså att fetcher-koden känner igen
/// en korrekt checksumma, inte att den bara accepterar vad den själv laddar ner.
final class ExternalBinaryFetcherTests: XCTestCase {
    private let sampleURL = URL(string: "https://raw.githubusercontent.com/torvalds/linux/v6.6/COPYING")!
    private let sampleSHA256 = "fb5a425bd3b3cd6071a3a9aff9909a859e7c1158d54d32e07658398cd67eb6a0"

    private func freshCacheDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bastion-binfetch-test-\(UUID().uuidString)")
    }

    /// Fetches the shared sample while treating GitHub's anonymous rate limit
    /// as an unavailable-network condition rather than a product failure.
    private func fetchSample(cacheDir: URL, expectedSHA256: String? = nil) async throws -> URL {
        do {
            return try await ExternalBinaryFetcher.fetch(
                url: sampleURL,
                expectedSHA256: expectedSHA256 ?? sampleSHA256,
                cacheDir: cacheDir,
                binaryName: "sample")
        } catch ExternalBinaryError.downloadFailed(let message) where message.contains("HTTP 429") {
            throw XCTSkip("Nätverket svarade med HTTP 429 (rate limit): \(message)")
        }
    }

    override func setUp() async throws {
        // Nätverksberoende — hoppa tydligt över istället för att låta ett
        // sandboxat/offline CI-läge misslyckas förvirrande.
        var request = URLRequest(url: sampleURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            throw XCTSkip("Ingen nätverksåtkomst i den här miljön: \(error)")
        }
    }

    func testDownloadsAndVerifiesRealFile() async throws {
        let cacheDir = freshCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let path = try await fetchSample(cacheDir: cacheDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let data = try Data(contentsOf: path)
        XCTAssertEqual(ExternalBinaryFetcher.sha256Hex(data), sampleSHA256)

        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o111, 0o111, "binären ska vara körbar (chmod 755)")
    }

    func testSecondFetchIsCacheHitAndSkipsNetwork() async throws {
        let cacheDir = freshCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let first = try await fetchSample(cacheDir: cacheDir)

        // En URL som INTE går att nå — om detta andra anrop av misstag
        // gjorde ett nätverksanrop skulle det kasta/hänga, inte returnera
        // tyst. Bevisar att cache-träffen faktiskt undviker nätverket, inte
        // bara att resultatet råkar stämma.
        let unreachable = URL(string: "https://127.0.0.1.invalid/does-not-exist")!
        let second = try await ExternalBinaryFetcher.fetch(
            url: unreachable, expectedSHA256: sampleSHA256,
            cacheDir: cacheDir, binaryName: "sample")

        XCTAssertEqual(first, second)
    }

    func testWrongChecksumIsRejectedAndNeverCached() async throws {
        let cacheDir = freshCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        let wrongChecksum = String(repeating: "0", count: 64)
        do {
            _ = try await fetchSample(cacheDir: cacheDir, expectedSHA256: wrongChecksum)
            XCTFail("förväntade checksumMismatch")
        } catch ExternalBinaryError.checksumMismatch(let expected, let actual) {
            XCTAssertEqual(expected, wrongChecksum)
            XCTAssertEqual(actual, sampleSHA256)
        }

        // Den felaktiga nedladdningen ska ALDRIG ha skrivits till disk.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: cacheDir.appendingPathComponent(wrongChecksum).appendingPathComponent("sample").path))
    }

    func testCorruptedCacheEntryIsRedownloaded() async throws {
        let cacheDir = freshCacheDir()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let destination = cacheDir.appendingPathComponent(sampleSHA256).appendingPathComponent("sample")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("korrupt-skräp, inte den riktiga filen".utf8).write(to: destination)

        let path = try await fetchSample(cacheDir: cacheDir)

        let data = try Data(contentsOf: path)
        XCTAssertEqual(ExternalBinaryFetcher.sha256Hex(data), sampleSHA256)
    }
}

// These security checks do not require network access.
final class ExternalBinaryFetcherPathTests: XCTestCase {
    func testInvalidNamesCannotRemoveFilesOutsideCache() async throws {
        let names = ["", ".", "..", "../victim", "nested/file", "/absolute", "nested\\file", "bad\0name"]
        for name in names {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let cache = root.appendingPathComponent("cache")
            let victim = root.appendingPathComponent("victim")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: victim)
            do {
                _ = try await ExternalBinaryFetcher.fetch(
                    url: URL(string: "https://example.com/binary")!, expectedSHA256: "irrelevant",
                    cacheDir: cache, binaryName: name)
                XCTFail("Accepted invalid name: \(name.debugDescription)")
            } catch ExternalBinaryError.cacheWriteFailed {
                // Invalid names must be rejected before any filesystem access.
            } catch {
                XCTFail("Unexpected error for \(name.debugDescription): \(error)")
            }
            XCTAssertEqual(try? Data(contentsOf: victim), Data("keep".utf8), name.debugDescription)
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path), name.debugDescription)
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testSymlinkIsNotAcceptedAsCacheHit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let target = root.appendingPathComponent("outside")
        let destination = cache.appendingPathComponent(ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data))
            .appendingPathComponent("sample")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StubBinaryURLProtocol.data.write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubBinaryURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let result = try await ExternalBinaryFetcher.fetch(
            url: URL(string: "https://example.com/binary")!,
            expectedSHA256: ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data),
            cacheDir: cache, binaryName: "sample", session: session)

        XCTAssertEqual(result, destination)
        XCTAssertEqual(try Data(contentsOf: target), StubBinaryURLProtocol.data)
        XCTAssertEqual(try Data(contentsOf: destination), StubBinaryURLProtocol.data)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType, .typeRegular)
    }

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubBinaryURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testInvalidChecksumsAreRejectedBeforeAnyFilesystemAccess() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        for checksum in ["irrelevant", String(repeating: "a", count: 63), "../" + String(repeating: "a", count: 61),
                         String(repeating: "g", count: 64)] {
            do {
                _ = try await ExternalBinaryFetcher.fetch(
                    url: URL(string: "https://example.com/binary")!, expectedSHA256: checksum,
                    cacheDir: cache, binaryName: "sample")
                XCTFail("Accepted invalid checksum \(checksum)")
            } catch ExternalBinaryError.cacheWriteFailed {
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testOtherVersionsUnderTheSameNameAreNotReplaced() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let session = stubSession()
        defer { session.invalidateAndCancel() }
        let first = try await ExternalBinaryFetcher.fetch(
            url: URL(string: "https://example.com/binary")!,
            expectedSHA256: ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data),
            cacheDir: cache, binaryName: "sample", session: session)
        let second = try await ExternalBinaryFetcher.fetch(
            url: URL(string: "https://example.com/other")!,
            expectedSHA256: ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.otherData),
            cacheDir: cache, binaryName: "sample", session: session)

        // The first caller's verified file must still hold the bytes it checked.
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), StubBinaryURLProtocol.data)
        XCTAssertEqual(try Data(contentsOf: second), StubBinaryURLProtocol.otherData)
    }

    /// An entry is replaced only once a verified download is ready. Removing it
    /// earlier could delete a valid file that a concurrent fetch installed after
    /// this one validated the entry, and a failed download would then leave the
    /// other caller with a URL that no longer exists.
    func testFailedDownloadLeavesExistingEntryInPlace() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let checksum = ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data)
        let destination = cache.appendingPathComponent(checksum).appendingPathComponent("sample")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: destination)
        // The file must still exist while the replacement is being downloaded.
        let existedDuringDownload = NIOLockedValueBox(false)
        StubBinaryURLProtocol.onRaceRequest = {
            existedDuringDownload.withLockedValue {
                $0 = FileManager.default.fileExists(atPath: destination.path)
            }
        }
        defer { StubBinaryURLProtocol.onRaceRequest = nil }
        let session = stubSession()
        defer { session.invalidateAndCancel() }

        do {
            _ = try await ExternalBinaryFetcher.fetch(
                url: URL(string: "https://example.com/race")!, expectedSHA256: checksum,
                cacheDir: cache, binaryName: "sample", session: session)
            XCTFail("The download fails with HTTP 500")
        } catch ExternalBinaryError.downloadFailed {
        }

        XCTAssertTrue(existedDuringDownload.withLockedValue { $0 })
        XCTAssertEqual(try Data(contentsOf: destination), Data("corrupt".utf8))
    }

    func testDirectoryInPlaceOfCachedFileIsReplacedAfterDownload() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let checksum = ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data)
        let destination = cache.appendingPathComponent(checksum).appendingPathComponent("sample")
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let session = stubSession()
        defer { session.invalidateAndCancel() }

        let result = try await ExternalBinaryFetcher.fetch(
            url: URL(string: "https://example.com/binary")!, expectedSHA256: checksum,
            cacheDir: cache, binaryName: "sample", session: session)

        XCTAssertEqual(try Data(contentsOf: result), StubBinaryURLProtocol.data)
    }

    func testConcurrentFetchesOfTheSameChecksumAllSucceed() async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let session = stubSession()
        defer { session.invalidateAndCancel() }
        let checksum = ExternalBinaryFetcher.sha256Hex(StubBinaryURLProtocol.data)
        let results = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try await ExternalBinaryFetcher.fetch(
                        url: URL(string: "https://example.com/binary")!, expectedSHA256: checksum,
                        cacheDir: cache, binaryName: "sample", session: session)
                }
            }
            return try await group.reduce(into: Set<URL>()) { $0.insert($1) }
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try Data(contentsOf: results.first!), StubBinaryURLProtocol.data)
    }
}

private final class StubBinaryURLProtocol: URLProtocol {
    static let data = Data("verified binary".utf8)
    /// Served for URLs ending in `/other`: a second version under the same name.
    static let otherData = Data("another verified version".utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Runs when a request for `/race` arrives, before the failure response.
    nonisolated(unsafe) static var onRaceRequest: (() -> Void)?

    override func startLoading() {
        if request.url!.lastPathComponent == "race" {
            Self.onRaceRequest?()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: request.url!.lastPathComponent == "other" ? Self.otherData : Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
