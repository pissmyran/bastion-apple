import Crypto
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Hämtar och cachar en enskild extern binär (t.ex. `wireguard-go`,
/// `tailscale`) från en URL, verifierad mot en känd SHA256-checksumma innan
/// den någonsin skrivs till disk som "giltig". Motiveras av VISION.md
/// "Native WireGuard/Tailscale — inget externt beroende": Bastion ska kunna
/// ladda ner+köra dessa verktyg själv istället för att kräva att användaren
/// installerat dem separat, men en nedladdad binär är samma tillitsnivå som
/// ett `curl | sudo bash`-skript om checksumman inte verifieras — se
/// ROADMAP.md för den fulla designmotiveringen.
///
/// Medvetet GENERISK (URL + förväntad checksumma in, verifierad sökväg ut) —
/// varken WireGuard- eller Tailscale-specifik. Anroparen (framtida UI-lager)
/// äger plattforms-/arkitekturval av URL och det publicerade checksum-värdet;
/// den här typen äger bara hämta+verifiera+cacha-mekaniken, så den kan
/// återanvändas för båda verktygen (och andra framtida) utan duplicering.
public enum ExternalBinaryError: Error, Sendable, Equatable {
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case cacheWriteFailed(String)
}

public enum ExternalBinaryFetcher {
    /// Hämtar `url` till `cacheDir/binaryName` om den inte redan finns där
    /// med RÄTT checksumma (idempotent — ett andra anrop med samma
    /// parametrar gör ingen nätverkstrafik alls). En redan cachad fil med FEL
    /// checksumma (korrupt/manipulerad) tas bort och laddas ner på nytt,
    /// aldrig litad på tyst.
    ///
    /// Checksumman verifieras mot de NEDLADDADE bytesen INNAN något skrivs
    /// till disk — en manipulerad/fel binär hamnar aldrig i cachen ens
    /// tillfälligt.
    /// `cacheDir` must be trusted and `binaryName` must be a single filename.
    public static func fetch(
        url: URL,
        expectedSHA256: String,
        cacheDir: URL,
        binaryName: String,
        session: URLSession = .shared
    ) async throws -> URL {
        guard !binaryName.isEmpty, binaryName != ".", binaryName != "..",
              !binaryName.contains("/"), !binaryName.contains("\\"), !binaryName.contains("\0") else {
            throw ExternalBinaryError.cacheWriteFailed("Invalid binary name")
        }
        let expected = expectedSHA256.lowercased()
        guard expected.count == 64, expected.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw ExternalBinaryError.cacheWriteFailed("Invalid SHA-256 checksum")
        }
        // Content-addressed: each checksum gets its own directory, so concurrent
        // fetches of different versions under one name never replace each other.
        let directory = cacheDir.appendingPathComponent(expected)
        let destination = directory.appendingPathComponent(binaryName)

        if let existing = cachedData(at: destination), sha256Hex(existing) == expected {
            return destination
        }
        // Finns men med fel checksumma (korrupt eller ett gammalt, felaktigt
        // cachat försök) — städa bort tyst, hämta rent på nytt nedan.
        try? FileManager.default.removeItem(at: destination)

        let data: Data
        do {
            let (downloaded, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw ExternalBinaryError.downloadFailed("HTTP \(status) för \(url.absoluteString)")
            }
            data = downloaded
        } catch let error as ExternalBinaryError {
            throw error
        } catch {
            throw ExternalBinaryError.downloadFailed("\(error)")
        }

        let actual = sha256Hex(data)
        guard actual == expected else {
            throw ExternalBinaryError.checksumMismatch(expected: expected, actual: actual)
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Skriv till en temporär fil i SAMMA katalog, byt sedan namn —
            // en process som läser `destination` mitt under en nedladdning
            // ska aldrig kunna se en halvskriven fil.
            let tmp = directory.appendingPathComponent(".\(binaryName).\(UUID().uuidString).tmp")
            defer { _ = unlink(tmp.path) }
            try data.write(to: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            // rename(2) replaces atomically: a concurrent fetch of the same
            // checksum cannot fail on an existing file or expose a missing one.
            guard rename(tmp.path, destination.path) == 0 else {
                throw ExternalBinaryError.cacheWriteFailed(String(cString: strerror(errno)))
            }
        } catch {
            throw ExternalBinaryError.cacheWriteFailed("\(error)")
        }

        return destination
    }

    private static func cachedData(at url: URL) -> Data? {
        // Do not treat a symbolic link as a cache hit, even if its target matches.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            return nil
        }
        return try? handle.readToEnd()
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
