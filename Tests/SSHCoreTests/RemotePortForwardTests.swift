import XCTest
import NIOCore
import NIOPosix
import NIOSSH
import NIOConcurrencyHelpers
@testable import SSHCore

/// Ekar rakt tillbaka — används som "det lokala målet" (targetHost:targetPort)
/// som en fjärr-portvidarebefordran ska nå, motsvarande `ServerDirectTCPIPEchoHandler`
/// men för en riktig fristående TCP-server, inte en SSH-kanal.
private final class TCPEchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
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

private final class ControlledForwardDelegate: GlobalRequestDelegate {
    let requests = NIOLockedValueBox<[(GlobalRequest.TCPForwardingRequest, EventLoopPromise<GlobalRequest.TCPForwardingResponse>)]>([])

    func tcpForwardingRequest(
        _ request: GlobalRequest.TCPForwardingRequest, handler: NIOSSHHandler,
        promise: EventLoopPromise<GlobalRequest.TCPForwardingResponse>
    ) {
        requests.withLockedValue { $0.append((request, promise)) }
    }

    func waitForRequest(_ index: Int) async throws -> EventLoopPromise<GlobalRequest.TCPForwardingResponse> {
        for _ in 0..<200 {
            if let promise = requests.withLockedValue({ $0.count > index ? $0[index].1 : nil }) {
                return promise
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw SSHError.channelFailed("timed out waiting for forwarding request")
    }
}

final class RemotePortForwardTests: XCTestCase {
    func testDisconnectDoesNotWaitForCancelReply() async throws {
        let server = try LoopbackServer.start(password: "hunter2", withholdCancelReply: true)
        defer { server.shutdown() }
        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let target = try await ServerBootstrap(group: group)
            .childChannelInitializer { $0.pipeline.addHandler(TCPEchoHandler()) }
            .bind(host: "127.0.0.1", port: 0).get()
        let forward = try await session.openRemotePortForward(
            bindPort: 0, targetHost: "127.0.0.1", targetPort: target.localAddress!.port!)
        let local = try await session.openLocalPortForward(
            bindPort: 0, targetHost: "example.com", targetPort: 80)
        let localPort = local.actualBindPort
        let collector = ByteCollectorHandler()
        let external = try await ClientBootstrap(group: group)
            .channelInitializer { $0.pipeline.addHandler(collector) }
            .connect(host: "127.0.0.1", port: forward.actualBindPort).get()
        var buffer = external.allocator.buffer(capacity: 4)
        buffer.writeString("ping")
        try await external.writeAndFlush(buffer).get()
        for _ in 0..<100 {
            if await collector.text().contains("ping") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let received = await collector.text()

        var cleanupError: Error?
        do {
            // The server retains the cancellation promise until transport close.
            try await withTimeout(seconds: 3) { await forward.close() }
            for _ in 0..<100 {
                if server.withheldCancel!.withLockedValue({ $0 }) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertTrue(server.withheldCancel!.withLockedValue { $0 })
            // Without a reply the port stays reserved (the server may still be
            // listening), but no longer routes connections.
            XCTAssertEqual(session.remoteForwards.withLockedValue { $0[forward.actualBindPort]?.active }, false)
        } catch {
            cleanupError = error
        }

        await local.close()
        var localStillListening = false
        if let lateClient = try? await ClientBootstrap(group: group)
            .connect(host: "127.0.0.1", port: localPort).get() {
            localStillListening = true
            try? await lateClient.close().get()
        }
        await session.close()
        do {
            try await withTimeout(seconds: 3) { try await external.closeFuture.get() }
        } catch {
            if cleanupError == nil { cleanupError = error }
        }
        try? await external.close().get()
        try? await target.close().get()
        try? await group.shutdownGracefully()
        XCTAssertEqual(received, "ping")
        XCTAssertFalse(localStillListening)
        if let cleanupError { throw cleanupError }
    }

    /// Fjärr-portvidarebefordran end-to-end: en riktig extern TCP-anslutning
    /// mot den port servern binder åt oss (LoopbackServers `ServerRemoteForwarder`),
    /// genom en `forwarded-tcpip`-SSH-kanal tillbaka till klienten, till en
    /// riktig lokal TCP-ekoserver, och samma väg tillbaka.
    func testRemotePortForwardEchoesThroughSSHChannel() async throws {
        let server = try LoopbackServer.start(password: "hunter2")
        defer { server.shutdown() }

        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()

        // Riktigt lokalt mål (motsvarande "internal-target" i localforward-
        // testerna, men här måste det faktiskt gå att ansluta till — fjärr-
        // vidarebefordran kopplar upp en riktig lokal TCP-anslutning dit).
        let targetGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let targetChannel = try await ServerBootstrap(group: targetGroup)
            .childChannelInitializer { channel in channel.pipeline.addHandler(TCPEchoHandler()) }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        let targetPort = targetChannel.localAddress!.port!

        let forward = try await session.openRemotePortForward(
            bindPort: 0, targetHost: "127.0.0.1", targetPort: targetPort)
        XCTAssertGreaterThan(forward.actualBindPort, 0)
        do {
            _ = try await session.openRemotePortForward(
                bindHost: "127.0.0.1", bindPort: forward.actualBindPort,
                targetHost: "127.0.0.1", targetPort: 1)
            XCTFail("duplicate port should be rejected")
        } catch { }
        do {
            _ = try await session.openRemotePortForward(
                bindHost: "127.0.0.1", bindPort: 0, targetHost: "127.0.0.1", targetPort: 1)
            XCTFail("allocation while another port is reserved should be rejected")
        } catch { }

        // Simulerar en extern klient som ansluter till servern.
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let collector = ByteCollectorHandler()
        let externalClient = try await ClientBootstrap(group: clientGroup)
            .channelInitializer { channel in channel.pipeline.addHandler(collector) }
            .connect(host: "127.0.0.1", port: forward.actualBindPort)
            .get()

        var buf = externalClient.allocator.buffer(capacity: 16)
        buf.writeString("hej genom fjärrtunneln")
        try await externalClient.writeAndFlush(buf).get()

        var received = ""
        for _ in 0..<50 {
            received = await collector.text()
            if received.contains("hej genom fjärrtunneln") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        try? await externalClient.close().get()
        await forward.close()
        await session.close()
        try? await targetChannel.close().get()
        try? await targetGroup.shutdownGracefully()
        try? await clientGroup.shutdownGracefully()

        XCTAssertTrue(received.contains("hej genom fjärrtunneln"), "fick: \(received.debugDescription)")
    }

    func testPendingRequestsAndRefusalRelease() async throws {
        let delegate = ControlledForwardDelegate()
        let server = try LoopbackServer.start(password: "hunter2", globalRequestDelegate: delegate)
        defer { server.shutdown() }
        let session = SSHSession(target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                                 auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        let first = Task { try await session.openRemotePortForward(bindHost: "127.0.0.1", bindPort: 45678, targetHost: "first", targetPort: 1) }
        let pending = try await delegate.waitForRequest(0)
        do {
            _ = try await session.openRemotePortForward(bindHost: "127.0.0.2", bindPort: 45678, targetHost: "second", targetPort: 2)
            XCTFail("pending port must be reserved")
        } catch { }
        do {
            _ = try await session.openRemotePortForward(bindPort: 0, targetHost: "second", targetPort: 2)
            XCTFail("allocation must wait for pending requests")
        } catch { }
        XCTAssertEqual(delegate.requests.withLockedValue { $0.count }, 1)
        pending.fail(SSHError.channelFailed("refused"))
        do { _ = try await first.value; XCTFail("server refused") } catch { }

        let retry = Task { try await session.openRemotePortForward(bindPort: 45678, targetHost: "first", targetPort: 1) }
        let retryRequest = try await delegate.waitForRequest(1)
        retryRequest.succeed(.init(boundPort: nil))
        let forward = try await retry.value
        let closing = Task { await forward.close() }
        let cancel = try await delegate.waitForRequest(2)
        cancel.succeed(.init(boundPort: nil))
        await closing.value
        await session.close()
    }

    func testAllocationAndCancellationReservations() async throws {
        let delegate = ControlledForwardDelegate()
        let server = try LoopbackServer.start(password: "hunter2", globalRequestDelegate: delegate)
        defer { server.shutdown() }
        let session = SSHSession(target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                                 auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        let opening = Task { try await session.openRemotePortForward(bindPort: 0, targetHost: "first", targetPort: 1) }
        let request = try await delegate.waitForRequest(0)
        do {
            _ = try await session.openRemotePortForward(bindPort: 45678, targetHost: "second", targetPort: 2)
            XCTFail("allocation in progress must be exclusive")
        } catch { }
        request.succeed(.init(boundPort: 45678))
        let forward = try await opening.value
        let closing = Task { await forward.close() }
        let cancel = try await delegate.waitForRequest(1)
        do {
            _ = try await session.openRemotePortForward(bindPort: 45678, targetHost: "second", targetPort: 2)
            XCTFail("port must stay reserved while cancellation is pending")
        } catch { }
        cancel.fail(SSHError.channelFailed("refused"))
        await closing.value
        await forward.close()
        do {
            _ = try await session.openRemotePortForward(bindPort: 45678, targetHost: "second", targetPort: 2)
            XCTFail("failed cancellation must retain reservation")
        } catch { }
        XCTAssertEqual(delegate.requests.withLockedValue { $0.count }, 2)
        await session.close()
    }

    func testDistinctPortsCanBeReservedConcurrently() async throws {
        let delegate = ControlledForwardDelegate()
        let server = try LoopbackServer.start(password: "hunter2", globalRequestDelegate: delegate)
        defer { server.shutdown() }
        let session = SSHSession(target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                                 auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        let firstOpening = Task { try await session.openRemotePortForward(bindPort: 45678, targetHost: "first", targetPort: 1) }
        let firstRequest = try await delegate.waitForRequest(0)
        let secondOpening = Task { try await session.openRemotePortForward(bindPort: 45679, targetHost: "second", targetPort: 2) }
        let secondRequest = try await delegate.waitForRequest(1)
        firstRequest.succeed(.init(boundPort: nil))
        secondRequest.succeed(.init(boundPort: nil))
        let first = try await firstOpening.value
        let second = try await secondOpening.value
        XCTAssertEqual(session.remoteForwards.withLockedValue { $0[45678]?.targetHost }, "first")
        XCTAssertEqual(session.remoteForwards.withLockedValue { $0[45679]?.targetHost }, "second")
        let firstClosing = Task { await first.close() }
        try await delegate.waitForRequest(2).succeed(.init(boundPort: nil))
        await firstClosing.value
        let secondClosing = Task { await second.close() }
        try await delegate.waitForRequest(3).succeed(.init(boundPort: nil))
        await secondClosing.value
        await session.close()
    }

    func testInvalidAllocatedPortKeepsReservation() async throws {
        let delegate = ControlledForwardDelegate()
        let server = try LoopbackServer.start(password: "hunter2", globalRequestDelegate: delegate)
        defer { server.shutdown() }
        let session = SSHSession(target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                                 auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        let opening = Task { try await session.openRemotePortForward(bindPort: 0, targetHost: "first", targetPort: 1) }
        try await delegate.waitForRequest(0).succeed(.init(boundPort: nil))
        do { _ = try await opening.value; XCTFail("missing allocated port must be rejected") } catch { }
        do {
            _ = try await session.openRemotePortForward(bindPort: 45678, targetHost: "second", targetPort: 2)
            XCTFail("unknown allocated port must keep the exclusive reservation")
        } catch { }
        XCTAssertEqual(delegate.requests.withLockedValue { $0.count }, 1)
        await session.close()
    }

    func testStaleCloseCannotCancelReplacement() async throws {
        let delegate = ControlledForwardDelegate()
        let server = try LoopbackServer.start(password: "hunter2", globalRequestDelegate: delegate)
        defer { server.shutdown() }
        let session = SSHSession(target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
                                 auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()
        let opening = Task { try await session.openRemotePortForward(bindPort: 45678, targetHost: "first", targetPort: 1) }
        try await delegate.waitForRequest(0).succeed(.init(boundPort: nil))
        let first = try await opening.value
        let closing = Task { await first.close() }
        try await delegate.waitForRequest(1).succeed(.init(boundPort: nil))
        await closing.value
        let replacement = Task { try await session.openRemotePortForward(bindPort: 45678, targetHost: "second", targetPort: 2) }
        try await delegate.waitForRequest(2).succeed(.init(boundPort: nil))
        let second = try await replacement.value
        await first.close()
        XCTAssertEqual(delegate.requests.withLockedValue { $0.count }, 3)
        XCTAssertEqual(session.remoteForwards.withLockedValue { $0[45678]?.targetHost }, "second")
        let closingSecond = Task { await second.close() }
        try await delegate.waitForRequest(3).succeed(.init(boundPort: nil))
        await closingSecond.value
        await session.close()
    }

    /// Regressionstest: en `forwarded-tcpip`-kanal för en port som INTE har
    /// någon aktiv, registrerad fjärr-vidarebefordran ska avvisas med ett fel
    /// — inte krascha eller hänga. Anropar `handleInboundForwardedChannel`
    /// direkt (internal, tillgänglig via @testable) med en fabricerad kanaltyp
    /// för en port som aldrig registrerats, eftersom det är svårt att
    /// deterministiskt trigga just det här racet end-to-end över ett riktigt
    /// nätverk.
    func testUnregisteredPortIsRejectedNotCrashed() async throws {
        let server = try LoopbackServer.start(password: "hunter2")
        defer { server.shutdown() }

        let session = SSHSession(
            target: SSHTarget(host: "127.0.0.1", port: server.port, username: "tester"),
            auth: .password("hunter2"), knownHosts: KnownHosts(path: nil))
        try await session.connect()

        // En riktig, godtycklig Channel räcker — guarden avvisar innan den
        // någonsin rör dess pipeline (bara dess eventLoop används i felfallet).
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let dummyChannel = try await ClientBootstrap(group: group)
            .connect(host: "127.0.0.1", port: server.port)
            .get()

        let channelType = SSHChannelType.forwardedTCPIP(
            .init(
                listeningHost: "0.0.0.0", listeningPort: 65_000,  // aldrig registrerad
                originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            )
        )
        do {
            try await session.handleInboundForwardedChannel(dummyChannel, channelType: channelType).get()
            XCTFail("skulle ha kastat — porten är inte registrerad")
        } catch {
            // förväntat
        }

        try? await dummyChannel.close().get()
        try? await group.shutdownGracefully()
        await session.close()
    }
}
