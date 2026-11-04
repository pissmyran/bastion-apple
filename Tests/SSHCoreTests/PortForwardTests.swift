import XCTest
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
@testable import SSHCore

final class PortForwardTests: XCTestCase {
    func testShutdownRejectsAdmissionsAndWaitsForPendingOpens() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .bind(host: "127.0.0.1", port: 0).get()
        let client = try await ClientBootstrap(group: group)
            .connect(host: "127.0.0.1", port: server.localAddress!.port!).get()
        let connections = ForwardConnections()
        XCTAssertTrue(connections.register(client))
        let pending = try XCTUnwrap(connections.beginOpen(on: client.eventLoop))
        let finished = NIOLockedValueBox(0)
        let first = Task {
            await connections.close(serverChannel: server)
            finished.withLockedValue { $0 += 1 }
        }
        try await server.closeFuture.get()
        XCTAssertFalse(connections.register(client))
        XCTAssertNil(connections.beginOpen(on: client.eventLoop))
        let second = Task {
            await connections.close(serverChannel: server)
            finished.withLockedValue { $0 += 1 }
        }
        try await client.closeFuture.get()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(finished.withLockedValue { $0 }, 0)
        pending.succeed(())
        await first.value
        await second.value
        XCTAssertEqual(finished.withLockedValue { $0 }, 2)
        try await group.shutdownGracefully()
    }

    func testCloseDrainsPendingLocalAndDynamicSSHOpens() async throws {
        for dynamic in [false, true] {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let requested = group.next().makePromise(of: Void.self)
            let release = group.next().makePromise(of: Void.self)
            let server = try LoopbackServer.start(password: "hunter2", directTCPIPGate: { channel in
                requested.succeed(())
                return release.futureResult.hop(to: channel.eventLoop)
            })
            let session = SSHSession(
                target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
            try await session.connect()
            let port: Int
            let stop: () async -> Void
            if dynamic {
                let forward = try await session.openDynamicPortForward(bindPort: 0)
                port = forward.actualBindPort
                stop = { await forward.close() }
            } else {
                let forward = try await session.openLocalPortForward(
                    bindPort: 0, targetHost: "example.com", targetPort: 9999)
                port = forward.actualBindPort
                stop = { await forward.close() }
            }
            let client = try await ClientBootstrap(group: group)
                .connect(host: "127.0.0.1", port: port).get()
            if dynamic {
                var request = client.allocator.buffer(capacity: 13)
                request.writeBytes([5, 1, 0, 5, 1, 0, 1, 127, 0, 0, 1, 0x27, 0x0f])
                try await client.writeAndFlush(request).get()
            }
            try await requested.futureResult.get()
            let finished = NIOLockedValueBox(false)
            let closing = Task {
                await stop()
                finished.withLockedValue { $0 = true }
            }
            try await client.closeFuture.get()
            XCTAssertFalse(finished.withLockedValue { $0 }, "close returned with an SSH open pending")
            release.succeed(())
            await closing.value
            XCTAssertTrue(finished.withLockedValue { $0 })
            await session.close()
            server.shutdown()
            try await group.shutdownGracefully()
        }
    }

    /// Lokal portvidarebefordran end-to-end: en riktig lokal TCP-anslutning
    /// mot den lyssnare `openLocalPortForward` startar, genom en direct-tcpip
    /// SSH-kanal, till serverns eko-handler (se `LoopbackServer`), och tillbaka.
    func testLocalPortForwardEchoesThroughSSHChannel() async throws {
        let server = try LoopbackServer.start(password: "hunter2")
        defer { server.shutdown() }

        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()

        let forward = try await session.openLocalPortForward(
            bindPort: 0, targetHost: "internal-target", targetPort: 9999)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        var received = ""
        let collector = ByteCollectorHandler()
        let client = try await ClientBootstrap(group: group)
            .channelInitializer { channel in channel.pipeline.addHandler(collector) }
            .connect(host: "127.0.0.1", port: forward.actualBindPort)
            .get()

        var buf = client.allocator.buffer(capacity: 16)
        buf.writeString("hej genom tunneln")
        try await client.writeAndFlush(buf).get()

        // Vänta in ekot (kort poll — inget event att invänta explicit).
        for _ in 0..<50 {
            received = await collector.text()
            if received.contains("hej genom tunneln") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        // Städa i rätt ordning (klient -> lyssnare -> session -> egen group) —
        // annars hinner NIOSSHs interna schemaläggning krocka med redan
        // nedstängda event loops.
        try? await client.close().get()
        await forward.close()
        await session.close()
        try? await group.shutdownGracefully()

        XCTAssertTrue(received.contains("hej genom tunneln"), "fick: \(received.debugDescription)")
    }

    /// Regressionstest för CodeRabbit-fyndet (PR #25): close() stängde
    /// tidigare bara den lokala TCP-lyssnaren, inte redan öppnade tunnlar —
    /// en aktiv anslutning skulle fortsätta köra tills fjärrsidan/sessionen
    /// stängdes, trots att doc-kommentaren påstod att close() stängde allt.
    func testCloseTerminatesActiveTunnelConnection() async throws {
        let server = try LoopbackServer.start(password: "hunter2")
        defer { server.shutdown() }

        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()

        let forward = try await session.openLocalPortForward(
            bindPort: 0, targetHost: "internal-target", targetPort: 9999)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try await ClientBootstrap(group: group)
            .connect(host: "127.0.0.1", port: forward.actualBindPort)
            .get()

        // Ge klientkanalen en kort stund att faktiskt bli klar (direct-tcpip-
        // kanalen öppnas asynkront på fjärrsidan efter TCP-anslutningen).
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(client.isActive, "klientkanalen borde vara aktiv innan close()")

        await forward.close()

        // closeFuture ska fullföljas av close() nu, inte bara vid att
        // fjärrsidan/sessionen stängs senare.
        try await client.closeFuture.get()
        XCTAssertFalse(client.isActive)

        await session.close()
        try? await group.shutdownGracefully()
    }
}

/// Samlar all inkommen text på en klientkanal (för test).
private final actor TextBox {
    private var text = ""
    func append(_ s: String) { text += s }
    func value() -> String { text }
}

private final class ByteCollectorHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    private let box = TextBox()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        let s = String(buffer: buf)
        Task { await box.append(s) }
    }

    func text() async -> String { await box.value() }
}
