import NIOCore
import NIOPosix
import NIOSSH
import NIOConcurrencyHelpers

/// Slår om rå `ByteBuffer` <-> `SSHChannelData` på en direct-tcpip-barnkanal —
/// motsvarande `ExecHandler`, men utan kommando-/exitstatus-hantering (en
/// portvidarebefordrad kanal har varken).
final class DirectTCPIPWrapperHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = unwrapInboundIn(data)
        guard case .channel = data.type, case .byteBuffer(let buffer) = data.data else {
            context.fireErrorCaught(SSHError.channelFailed("oväntad kanaldata"))
            return
        }
        context.fireChannelRead(wrapInboundOut(buffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buf = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buf))), promise: promise)
    }
}

// Admission, active sockets, and outstanding SSH opens share one shutdown gate.
final class ForwardConnections: @unchecked Sendable {
    private struct State {
        var closing = false
        var channels: [ObjectIdentifier: Channel] = [:]
        var nextOpenID = 0
        var opens: [Int: EventLoopFuture<Void>] = [:]
    }
    private let state = NIOLockedValueBox(State())

    func register(_ channel: Channel) -> Bool {
        let id = ObjectIdentifier(channel)
        let accepted = state.withLockedValue { state in
            guard !state.closing else { return false }
            state.channels[id] = channel
            return true
        }
        if accepted {
            channel.closeFuture.whenComplete { _ in
                self.state.withLockedValue { _ = $0.channels.removeValue(forKey: id) }
            }
        }
        return accepted
    }

    func beginOpen(on eventLoop: EventLoop) -> EventLoopPromise<Void>? {
        let entry: (Int, EventLoopPromise<Void>)? = state.withLockedValue { state in
            guard !state.closing else { return nil }
            let id = state.nextOpenID
            state.nextOpenID += 1
            let promise = eventLoop.makePromise(of: Void.self)
            state.opens[id] = promise.futureResult
            return (id, promise)
        }
        guard let (id, promise) = entry else { return nil }
        promise.futureResult.whenComplete { _ in
            self.state.withLockedValue { _ = $0.opens.removeValue(forKey: id) }
        }
        return promise
    }

    func close(serverChannel: Channel) async {
        let snapshot = state.withLockedValue { state in
            state.closing = true
            return (Array(state.channels.values), Array(state.opens.values))
        }
        serverChannel.close(promise: nil)
        for channel in snapshot.0 { channel.close(promise: nil) }
        for channel in snapshot.0 { _ = try? await channel.closeFuture.get() }
        for open in snapshot.1 { _ = try? await open.get() }
        _ = try? await serverChannel.closeFuture.get()
    }
}

/// Ett aktivt lokalt portvidarebefordran (`ssh -L bindPort:targetHost:targetPort`).
/// Håller den lokala TCP-lyssnaren vid liv — `close()` stänger den OCH alla
/// aktiva vidarebefordrade anslutningar (CodeRabbit-fynd, PR #25: close()
/// stängde tidigare bara lyssnaren, redan öppnade tunnlar fortsatte köra
/// tills fjärrsidan eller SSH-sessionen stängdes — kommentaren påstod
/// motsatsen).
public final class LocalPortForward {
    private let serverChannel: Channel
    private let activeChannels: ForwardConnections
    public let bindHost: String
    public let bindPort: Int
    public let targetHost: String
    public let targetPort: Int

    /// Faktiskt bunden lokal port — samma som `bindPort` om den var != 0,
    /// annars den OS-tilldelade porten (`bindPort: 0` = "valfri ledig port").
    public var actualBindPort: Int { serverChannel.localAddress?.port ?? bindPort }

    init(
        serverChannel: Channel, activeChannels: ForwardConnections,
        bindHost: String, bindPort: Int, targetHost: String, targetPort: Int
    ) {
        self.serverChannel = serverChannel
        self.activeChannels = activeChannels
        self.bindHost = bindHost
        self.bindPort = bindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    public func close() async {
        await activeChannels.close(serverChannel: serverChannel)
    }
}

extension SSHSession {
    /// Lokal portvidarebefordran, motsvarande `ssh -L bindPort:targetHost:targetPort`:
    /// startar en lokal TCP-lyssnare på `bindHost:bindPort`. Varje ansluten
    /// klient får en egen `direct-tcpip`-SSH-kanal mot `targetHost:targetPort`
    /// på fjärrsidan — datan bryggas rakt igenom (`GlueHandler`).
    public func openLocalPortForward(
        bindHost: String = "127.0.0.1",
        bindPort: Int,
        targetHost: String,
        targetPort: Int
    ) async throws -> LocalPortForward {
        guard let channel = self.channel else {
            throw SSHError.channelFailed("inte ansluten")
        }
        let sshHandler: NIOSSHHandler
        do {
            sshHandler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
        } catch {
            throw SSHError.channelFailed(String(describing: error))
        }

        // Skapas FÖRE bind() (inte inuti LocalPortForward efteråt) — annars
        // kunde en klient hinna ansluta mellan att bind() returnerar och
        // LocalPortForward konstrueras, och den anslutningen skulle aldrig
        // spåras/stängas av close().
        let activeChannels = ForwardConnections()
        let serverChannel: Channel
        do {
            serverChannel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { inboundChannel in
                    guard let originatorAddress = inboundChannel.remoteAddress else {
                        return inboundChannel.eventLoop.makeFailedFuture(
                            SSHError.channelFailed("okänd avsändaradress"))
                    }
                    guard activeChannels.register(inboundChannel),
                          let open = activeChannels.beginOpen(on: inboundChannel.eventLoop) else {
                        return inboundChannel.eventLoop.makeFailedFuture(SSHError.channelFailed("forward closed"))
                    }
                    let promise = inboundChannel.eventLoop.makePromise(of: Channel.self)
                    let directTCPIP = SSHChannelType.DirectTCPIP(
                        targetHost: targetHost, targetPort: targetPort,
                        originatorAddress: originatorAddress
                    )
                    sshHandler.createChannel(promise, channelType: .directTCPIP(directTCPIP)) { childChannel, channelType in
                        guard case .directTCPIP = channelType else {
                            return inboundChannel.eventLoop.makeFailedFuture(
                                SSHError.channelFailed("fel kanaltyp"))
                        }
                        guard activeChannels.register(childChannel) else {
                            return childChannel.eventLoop.makeFailedFuture(SSHError.channelFailed("forward closed"))
                        }
                        return childChannel.eventLoop.makeCompletedFuture {
                            let (ours, theirs) = GlueHandler.matchedPair()
                            try childChannel.pipeline.syncOperations.addHandler(DirectTCPIPWrapperHandler())
                            try childChannel.pipeline.syncOperations.addHandler(ours)
                            try inboundChannel.pipeline.syncOperations.addHandler(theirs)
                        }
                    }
                    promise.futureResult.whenComplete { _ in open.succeed(()) }
                    return promise.futureResult.map { _ in }
                }
                .bind(host: bindHost, port: bindPort)
                .get()
        } catch {
            throw SSHError.channelFailed(String(describing: error))
        }

        return LocalPortForward(
            serverChannel: serverChannel, activeChannels: activeChannels,
            bindHost: bindHost, bindPort: bindPort,
            targetHost: targetHost, targetPort: targetPort
        )
    }
}

// All mutable fields are protected by SSHSession.remoteForwards' lock.
final class RemoteForwardReservation: @unchecked Sendable {
    let targetHost: String
    let targetPort: Int
    var active = false
    var closing = false

    init(targetHost: String, targetPort: Int) {
        self.targetHost = targetHost
        self.targetPort = targetPort
    }
}

/// Ett aktivt fjärr-portvidarebefordran (`ssh -R bindPort:targetHost:targetPort`):
/// servern lyssnar åt oss, och vidarebefordrar inkommande anslutningar till oss
/// som `forwarded-tcpip`-kanaler, som vi i sin tur bryggar mot en lokal
/// TCP-anslutning till `targetHost:targetPort` (sett från klientens sida, till
/// skillnad från `LocalPortForward` där målet ligger på fjärrsidan).
public final class RemotePortForward {
    private weak var session: SSHSession?
    private let reservation: RemoteForwardReservation
    public let bindHost: String
    /// Porten som begärdes (kan vara 0 = "valfri ledig port hos servern").
    public let bindPort: Int
    /// Porten servern faktiskt band — samma som `bindPort` om den inte var 0.
    public let actualBindPort: Int
    public let targetHost: String
    public let targetPort: Int

    init(session: SSHSession, reservation: RemoteForwardReservation, bindHost: String, bindPort: Int, actualBindPort: Int, targetHost: String, targetPort: Int) {
        self.session = session
        self.reservation = reservation
        self.bindHost = bindHost
        self.bindPort = bindPort
        self.actualBindPort = actualBindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    /// Removes the local route and sends a best-effort cancellation without
    /// waiting for a reply from the server.
    public func close() async {
        guard let session, let channel = session.channel else { return }
        let shouldCancel = session.remoteForwards.withLockedValue { forwards in
            guard let current = forwards[actualBindPort], current === reservation, !current.closing else { return false }
            current.closing = true
            current.active = false
            return true
        }
        guard shouldCancel else { return }
        guard let sshHandler = try? await channel.pipeline.handler(type: NIOSSHHandler.self).get() else { return }
        // sendTCPForwardingRequest är dokumenterat "inte trådsäker, får bara
        // anropas på kanalens egen event loop" — en async-fortsättning
        // garanterar INTE att vi fortfarande kör där, så själva anropet måste
        // skickas in explicit via eventLoop.execute (kraschade annars med
        // "Precondition failed" i assumeIsolatedUnsafeUnchecked).
        // The port's reservation is released only once the server confirms the
        // cancellation; without a reply it stays reserved for the rest of the
        // session, because the server may still be listening.
        let promise = channel.eventLoop.makePromise(of: GlobalRequest.TCPForwardingResponse?.self)
        let remoteForwards = session.remoteForwards
        let port = actualBindPort
        let reservation = reservation
        promise.futureResult.whenSuccess { _ in
            remoteForwards.withLockedValue { forwards in
                if forwards[port] === reservation {
                    forwards.removeValue(forKey: port)
                }
            }
        }
        channel.eventLoop.execute {
            sshHandler.sendTCPForwardingRequest(.cancel(host: self.bindHost, port: self.actualBindPort), promise: promise)
        }
        // Wait briefly for the confirmation, so the port can be reused as soon
        // as close() returns, but never let a server that does not answer
        // stall teardown.
        let done = channel.eventLoop.makePromise(of: Void.self)
        let finished = NIOLockedValueBox(false)
        let finish: @Sendable () -> Void = {
            let first = finished.withLockedValue { wasFinished -> Bool in
                defer { wasFinished = true }
                return !wasFinished
            }
            if first { done.succeed(()) }
        }
        promise.futureResult.whenComplete { _ in finish() }
        let timer = channel.eventLoop.scheduleTask(in: .seconds(1)) { finish() }
        _ = try? await done.futureResult.get()
        timer.cancel()
    }
}

extension SSHSession {
    /// Fjärr-portvidarebefordran, motsvarande `ssh -R bindPort:targetHost:targetPort`:
    /// ber servern lyssna på `bindHost:bindPort` på sin sida. Varje anslutning
    /// dit ger en `forwarded-tcpip`-kanal tillbaka till oss (dirigerad via
    /// `remoteForwards`, se `handleInboundForwardedChannel`), som bryggas mot
    /// en ny lokal TCP-anslutning till `targetHost:targetPort`.
    ///
    /// A port can be reserved only once per session, regardless of bind host.
    /// Port 0 can only be requested when no other ports are reserved, and
    /// blocks other requests until the assigned port is known. An uncertain
    /// listen or cancel result keeps its reservation for the session lifetime.
    public func openRemotePortForward(
        bindHost: String = "0.0.0.0",
        bindPort: Int,
        targetHost: String,
        targetPort: Int
    ) async throws -> RemotePortForward {
        guard let channel = self.channel else {
            throw SSHError.channelFailed("inte ansluten")
        }
        let sshHandler: NIOSSHHandler
        do {
            sshHandler = try await channel.pipeline.handler(type: NIOSSHHandler.self).get()
        } catch {
            throw SSHError.channelFailed(String(describing: error))
        }

        guard (0...65535).contains(bindPort) else {
            throw SSHError.channelFailed("invalid remote bind port")
        }
        let reservation = RemoteForwardReservation(targetHost: targetHost, targetPort: targetPort)
        let reserved = remoteForwards.withLockedValue { forwards in
            // Port 0 may be allocated on a different interface at a port that
            // is already in use. While allocation is pending, no other request
            // may start; it can only start when the table is empty.
            guard forwards[0] == nil, forwards[bindPort] == nil,
                  bindPort != 0 || forwards.isEmpty else { return false }
            forwards[bindPort] = reservation
            return true
        }
        guard reserved else {
            throw SSHError.channelFailed("remote bind port is already reserved")
        }

        let promise = channel.eventLoop.makePromise(of: GlobalRequest.TCPForwardingResponse?.self)
        // Install the route on the SSH event loop before dispatching subsequent
        // inbound channels, and before sending the request.
        let result = promise.futureResult.flatMapThrowing { [remoteForwards] response in
            let port: Int
            if bindPort == 0 {
                guard let assigned = response?.boundPort, (1...65535).contains(assigned) else {
                    // The server may still be listening; retain the exclusive
                    // reservation when its assigned port is unknown.
                    throw SSHError.channelFailed("invalid allocated remote bind port")
                }
                port = assigned
            } else {
                port = bindPort
            }
            remoteForwards.withLockedValue { forwards in
                if bindPort == 0 {
                    forwards.removeValue(forKey: 0)
                    forwards[port] = reservation
                }
                reservation.active = true
            }
            return port
        }
        channel.eventLoop.execute {
            sshHandler.sendTCPForwardingRequest(.listen(host: bindHost, port: bindPort), promise: promise)
        }
        let actualBindPort: Int
        do {
            actualBindPort = try await result.get()
        } catch {
            // Only an explicit refusal proves the listener was not created.
            // Keep the reservation for an uncertain outcome until the session ends.
            if let error = error as? NIOSSHError, error.type == .globalRequestRefused {
                remoteForwards.withLockedValue { forwards in
                    if forwards[bindPort] === reservation {
                        forwards.removeValue(forKey: bindPort)
                    }
                }
            }
            throw SSHError.channelFailed(String(describing: error))
        }

        return RemotePortForward(
            session: self, reservation: reservation, bindHost: bindHost, bindPort: bindPort, actualBindPort: actualBindPort,
            targetHost: targetHost, targetPort: targetPort
        )
    }

    /// Kallas av `inboundChildChannelInitializer` (se `connect()`) för varje
    /// kanal fjärrsidan öppnar mot oss. Bara `forwarded-tcpip` med en port som
    /// finns i `remoteForwards` accepteras — allt annat avvisas.
    func handleInboundForwardedChannel(_ inboundChannel: Channel, channelType: SSHChannelType) -> EventLoopFuture<Void> {
        guard case .forwardedTCPIP(let info) = channelType else {
            return inboundChannel.eventLoop.makeFailedFuture(
                SSHError.channelFailed("oväntad kanaltyp för inkommande fjärrvidarebefordran"))
        }
        guard let target = remoteForwards.withLockedValue({ forwards -> (targetHost: String, targetPort: Int)? in
            guard let reservation = forwards[info.listeningPort], reservation.active else { return nil }
            return (reservation.targetHost, reservation.targetPort)
        }) else {
            return inboundChannel.eventLoop.makeFailedFuture(
                SSHError.channelFailed("ingen aktiv fjärrvidarebefordran för port \(info.listeningPort)"))
        }

        return ClientBootstrap(group: group)
            .connect(host: target.targetHost, port: target.targetPort)
            .flatMap { localChannel in
                localChannel.eventLoop.makeCompletedFuture {
                    // Wrappern hör hemma på SSH-kanalen (SSHChannelData-domän),
                    // INTE den lokala TCP-anslutningen (redan rå ByteBuffer) —
                    // fick dem omvända i ett tidigare försök, vilket kraschade
                    // med "tried to decode as type ByteBuffer but found
                    // SSHChannelData" så fort riktig data flödade igenom.
                    let (ours, theirs) = GlueHandler.matchedPair()
                    try localChannel.pipeline.syncOperations.addHandler(ours)
                    try inboundChannel.pipeline.syncOperations.addHandler(DirectTCPIPWrapperHandler())
                    try inboundChannel.pipeline.syncOperations.addHandler(theirs)
                }
            }
    }
}
