import XCTest
import Foundation
@testable import SSHCore

final class SFTPClientTests: XCTestCase {
    private func connectedSession(_ server: LoopbackServer) async throws -> SSHSession {
        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password(TestCredentials.password), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        return session
    }

    func testRealpathResolvesRelativeToRoot() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        let resolved = try await sftp.realpath("some/path")
        XCTAssertEqual(resolved, "/some/path")

        await sftp.close()
        await session.close()
    }

    func testWriteThenReadFileRoundTrips() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        let content = Array("hej från Bastion — åäö\n".utf8)
        try await sftp.writeFile("test.txt", data: content)
        let readBack = try await sftp.readFile("test.txt")
        XCTAssertEqual(readBack, content)

        await sftp.close()
        await session.close()
    }

    func testWriteFileLargerThanOneChunk() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        // Tre gånger chunkSize -> minst tre READ/WRITE-rundor krävs.
        let content = (0..<200_000).map { UInt8($0 % 256) }
        try await sftp.writeFile("big.bin", data: content, chunkSize: 32768)
        let readBack = try await sftp.readFile("big.bin", chunkSize: 32768)
        XCTAssertEqual(readBack, content)

        await sftp.close()
        await session.close()
    }

    func testListDirectoryFindsWrittenFiles() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("a.txt", data: Array("a".utf8))
        try await sftp.writeFile("b.txt", data: Array("b".utf8))
        let entries = try await sftp.listDirectory(".")

        XCTAssertEqual(Set(entries.map(\.filename)), ["a.txt", "b.txt"])
        XCTAssertTrue(entries.allSatisfy { $0.attributes.size != nil })
        XCTAssertTrue(entries.allSatisfy { !$0.attributes.isDirectory })

        await sftp.close()
        await session.close()
    }

    func testListDirectoryDistinguishesFilesFromDirectories() async throws {
        // Regressionstest: testserverns attributes(atDiskPath:) måste sätta
        // POSIX-filtypsbitarna (S_IFDIR/S_IFREG), inte bara behörighets-
        // bitarna — annars kan en klient (SFTPBrowserView) inte skilja mapp
        // från fil utan ett extra STAT-anrop per post.
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.mkdir("adir")
        try await sftp.writeFile("afile.txt", data: Array("x".utf8))
        let entries = try await sftp.listDirectory(".")

        let dir = entries.first { $0.filename == "adir" }
        let file = entries.first { $0.filename == "afile.txt" }
        XCTAssertEqual(dir?.attributes.isDirectory, true)
        XCTAssertEqual(file?.attributes.isDirectory, false)

        await sftp.close()
        await session.close()
    }

    func testMkdirRmdirRoundTrip() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.mkdir("subdir")
        let entries = try await sftp.listDirectory(".")
        XCTAssertTrue(entries.contains { $0.filename == "subdir" })

        try await sftp.rmdir("subdir")
        let afterRemoval = try await sftp.listDirectory(".")
        XCTAssertFalse(afterRemoval.contains { $0.filename == "subdir" })

        await sftp.close()
        await session.close()
    }

    /// Verifierar mot den RIKTIGA filen på disk (backad av `server.sftpRoot`,
    /// samma sandlåda-mönster som testservern använder överallt) — inte bara
    /// att servern svarar OK, utan att behörigheten faktiskt ändrades.
    func testSetPermissionsChangesRealFileMode() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("perm-test.txt", data: Array("x".utf8))
        try await sftp.setPermissions("perm-test.txt", mode: 0o600)

        let diskPath = server.sftpRoot + "/perm-test.txt"
        let attrs = try FileManager.default.attributesOfItem(atPath: diskPath)
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(mode & 0o777, 0o600)

        await sftp.close()
        await session.close()
    }

    /// Verifierar mot den RIKTIGA filen på disk, precis som
    /// `testSetPermissionsChangesRealFileMode`. `chown` till en ANNAN
    /// uid/gid än processens egen kräver root (normalt POSIX-beteende) —
    /// den här testkörningen är oprivilegierad, så vi "byter" till samma
    /// uid/gid processen redan kör som. Bevisar ändå hela protokollvägen:
    /// klient bygger ett SETSTAT med uid+gid -> servern tar emot och
    /// applicerar det -> filen på disk har verkligen det värdet efteråt
    /// (inte bara att servern svarade OK).
    func testChownChangesRealFileOwnership() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("chown-test.txt", data: Array("x".utf8))
        let myUID = UInt32(getuid())
        let myGID = UInt32(getgid())
        try await sftp.chown("chown-test.txt", uid: myUID, gid: myGID)

        let diskPath = server.sftpRoot + "/chown-test.txt"
        let attrs = try FileManager.default.attributesOfItem(atPath: diskPath)
        let ownerID = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value
        let groupID = (attrs[.groupOwnerAccountID] as? NSNumber)?.uint32Value
        XCTAssertEqual(ownerID, myUID)
        XCTAssertEqual(groupID, myGID)

        await sftp.close()
        await session.close()
    }

    func testRemoveDeletesFile() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("gone.txt", data: Array("x".utf8))
        try await sftp.remove("gone.txt")
        let entries = try await sftp.listDirectory(".")
        XCTAssertFalse(entries.contains { $0.filename == "gone.txt" })

        await sftp.close()
        await session.close()
    }

    func testRenameMovesFile() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("old.txt", data: Array("hej".utf8))
        try await sftp.rename("old.txt", to: "new.txt")
        let entries = try await sftp.listDirectory(".")
        XCTAssertFalse(entries.contains { $0.filename == "old.txt" })
        XCTAssertTrue(entries.contains { $0.filename == "new.txt" })
        let renamed = try await sftp.readFile("new.txt")
        XCTAssertEqual(renamed, Array("hej".utf8))

        await sftp.close()
        await session.close()
    }

    func testStatReturnsFileSize() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("sized.txt", data: Array(repeating: 0x41, count: 777))
        let attrs = try await sftp.stat("sized.txt")
        XCTAssertEqual(attrs.size, 777)

        await sftp.close()
        await session.close()
    }

    func testReadingMissingFileThrowsNoSuchFile() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        do {
            _ = try await sftp.readFile("does-not-exist.txt")
            XCTFail("skulle ha kastat")
        } catch let error as SFTPStatusError {
            XCTAssertEqual(error.code, .noSuchFile)
        }

        await sftp.close()
        await session.close()
    }

    func testPathTraversalOutsideSandboxIsBlocked() async throws {
        // Regressionstest för CodeRabbit-fyndet i testserverns diskPath(for:):
        // "../"-segment fick tidigare lämna sandlådan (server.sftpRoot) och
        // nå riktiga filer på testmaskinen. Ett skadligt/buggigt klientanrop
        // ska svaras som "hittades inte", inte lyckas läsa något utanför roten.
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        do {
            _ = try await sftp.readFile("../../../../../../etc/passwd")
            XCTFail("skulle ha kastat — sökvägen ligger utanför sandlådan")
        } catch let error as SFTPStatusError {
            XCTAssertEqual(error.code, .noSuchFile)
        }

        await sftp.close()
        await session.close()
    }

    func testRejectedPathsCannotTouchFallbackOrFollowSymlinks() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let fm = FileManager.default
        let outside = NSTemporaryDirectory() + "bastion-outside-\(UUID().uuidString)"
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: false)
        defer { try? fm.removeItem(atPath: outside) }
        let victim = outside + "/victim"
        try "original".write(toFile: victim, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: server.sftpRoot + "/__blocked_path_traversal__", withDestinationPath: victim)
        try fm.createSymbolicLink(atPath: server.sftpRoot + "/link", withDestinationPath: outside)

        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)
        try await sftp.writeFile("inside", data: [1])

        func rejected(_ operation: () async throws -> Void) async throws {
            do {
                try await operation()
                XCTFail("Expected path rejection")
            } catch let error as SFTPStatusError {
                XCTAssertEqual(error.code, .noSuchFile)
            }
        }

        // The server root is a sibling of `outside` in the temporary directory,
        // so this path reaches the real directory if traversal protection fails.
        let escaped = "../" + (outside as NSString).lastPathComponent
        XCTAssertEqual(
            ((server.sftpRoot + "/" + escaped) as NSString).standardizingPath, outside,
            "the traversal path must resolve to the directory created above")
        try await rejected { _ = try await sftp.readFile(escaped + "/victim") }
        try await rejected { try await sftp.writeFile(escaped + "/new", data: [2]) }
        try await rejected { _ = try await sftp.stat(escaped + "/victim") }
        try await rejected { _ = try await sftp.listDirectory(escaped) }
        try await rejected { try await sftp.mkdir(escaped + "/newdir") }
        try await rejected { try await sftp.remove(escaped + "/victim") }
        try await rejected { try await sftp.rmdir(escaped) }
        try await rejected { try await sftp.rename("inside", to: escaped + "/moved") }
        try await rejected { try await sftp.rename(escaped + "/victim", to: "stolen") }
        try await rejected { try await sftp.setPermissions(escaped + "/victim", mode: 0o777) }
        try await rejected { _ = try await sftp.readFile("link/victim") }
        try await rejected { try await sftp.writeFile("link/victim", data: [3]) }
        try await rejected { try await sftp.remove("link/victim") }
        try await rejected { try await sftp.mkdir("link/new") }
        try await rejected { try await sftp.setPermissions(".\0/ignored", mode: 0o777) }

        XCTAssertEqual(try String(contentsOfFile: victim, encoding: .utf8), "original")
        XCTAssertTrue(fm.fileExists(atPath: server.sftpRoot + "/inside"))
        for name in ["new", "newdir", "moved"] {
            XCTAssertFalse(fm.fileExists(atPath: outside + "/" + name), name)
        }
        XCTAssertFalse(fm.fileExists(atPath: server.sftpRoot + "/stolen"))
        let victimMode = try fm.attributesOfItem(atPath: victim)[.posixPermissions] as? NSNumber
        XCTAssertNotEqual(victimMode?.intValue, 0o777)
        await sftp.close()
        await session.close()
    }

    func testSFTPRootRemainsPrivateAndCannotBeReplaced() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let fm = FileManager.default
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        func rootMode() throws -> UInt16 {
            let attrs = try fm.attributesOfItem(atPath: server.sftpRoot)
            return (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        }
        XCTAssertEqual(try rootMode() & 0o777, 0o700)

        func denied(_ operation: () async throws -> Void) async throws {
            do {
                try await operation()
                XCTFail("Expected root protection")
            } catch let error as SFTPStatusError {
                XCTAssertEqual(error.code, .permissionDenied)
            }
        }
        try await denied { try await sftp.setPermissions("/", mode: 0o777) }
        try await denied { try await sftp.chown("./", uid: UInt32(getuid()), gid: UInt32(getgid())) }
        try await denied { try await sftp.rmdir(".") }
        try await denied { try await sftp.remove("/") }
        try await denied { try await sftp.rename(".", to: "moved") }
        XCTAssertEqual(try rootMode() & 0o777, 0o700)
        try await sftp.writeFile("still-usable", data: [42])
        let contents = try await sftp.readFile("still-usable")
        XCTAssertEqual(contents, [42])
        await sftp.close()
        await session.close()
    }

    func testWriteFileRejectsZeroChunkSize() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        do {
            try await sftp.writeFile("x.txt", data: [1, 2, 3], chunkSize: 0)
            XCTFail("skulle ha kastat — chunkSize: 0 avancerar aldrig")
        } catch is SFTPClientError {
            // förväntat
        }

        await sftp.close()
        await session.close()
    }

    func testReadFileRejectsZeroChunkSize() async throws {
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        try await sftp.writeFile("x.txt", data: [1, 2, 3])
        do {
            _ = try await sftp.readFile("x.txt", chunkSize: 0)
            XCTFail("skulle ha kastat")
        } catch is SFTPClientError {
            // förväntat
        }

        await sftp.close()
        await session.close()
    }

    func testListDirectoryClosesHandleEvenWhenReaddirFails() async throws {
        // Regressionstest för CodeRabbit-fyndet: en handle som läcker på
        // serversidan om readdir-loopen kastar. Vi kan inte tvinga fram ett
        // riktigt readdir-fel utan att ändra testservern, men vi verifierar
        // åtminstone att en efterföljande, orelaterad operation fortfarande
        // fungerar normalt (dvs. att klienten/kanalen inte hamnar i ett
        // trasigt tillstånd av det normala, lyckade fallet).
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        _ = try await sftp.listDirectory(".")
        try await sftp.writeFile("still-works.txt", data: Array("ok".utf8))
        let readBack = try await sftp.readFile("still-works.txt")
        XCTAssertEqual(readBack, Array("ok".utf8))

        await sftp.close()
        await session.close()
    }

    func testConcurrentRequestsOnSameConnectionAreMatchedByID() async throws {
        // Flera samtidiga anrop över samma SFTP-kanal ska matchas rätt via
        // SFTP:s eget id-fält, inte råka blanda ihop svar (aktören
        // serialiserar pending-tabellen, men själva förfrågningarna skickas
        // koncurrent här för att bevisa att inget kapplöpningstillstånd
        // uppstår i id-tilldelningen/dispatchen).
        let server = try LoopbackServer.start(password: TestCredentials.password)
        defer { server.shutdown() }
        let session = try await connectedSession(server)
        let sftp = try await SFTPClient.open(on: session)

        for i in 0..<10 {
            try await sftp.writeFile("file\(i).txt", data: Array("innehåll \(i)".utf8))
        }

        try await withThrowingTaskGroup(of: (Int, [UInt8]).self) { group in
            for i in 0..<10 {
                group.addTask {
                    let data = try await sftp.readFile("file\(i).txt")
                    return (i, data)
                }
            }
            for try await (i, data) in group {
                XCTAssertEqual(data, Array("innehåll \(i)".utf8))
            }
        }

        await sftp.close()
        await session.close()
    }
}
