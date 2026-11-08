package com.tabberspak.remotekit

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * An in-process connection: DemoHost and tests, as apple/RemoteKit's MemoryTransport. Each side's
 * sends are the other side's receives, in order.
 */
class MemoryTransport private constructor(
    private val inbound: Channel<String>,
    private val outbound: Channel<String>,
) : RemoteTransport {
    private val finished = AtomicBoolean(false)
    private lateinit var other: MemoryTransport
    @Volatile override var closeCode: Int? = null
        private set

    override suspend fun send(text: String) {
        if (!sendNow(text)) throw TransportFailure.Closed(closeCode)
    }

    /** Delivers a frame at once, in order; false once closed. */
    fun sendNow(text: String): Boolean = !finished.get() && outbound.trySend(text).isSuccess

    override suspend fun receive(): String? = try {
        inbound.receive()
    } catch (_: ClosedReceiveChannelException) {
        null
    }

    override fun close() = close(1000)

    /** Closes with a code the other side will see. */
    fun close(code: Int) {
        if (!finished.compareAndSet(false, true)) return
        other.closeCode = code
        outbound.close()
    }

    /** The network dropped: no close frame, and the other side sees only the end. */
    fun drop() = close(1006)

    companion object {
        /** Two connected ends. */
        fun pair(): Pair<MemoryTransport, MemoryTransport> {
            val toHost = Channel<String>(Channel.UNLIMITED)
            val toPhone = Channel<String>(Channel.UNLIMITED)
            val phone = MemoryTransport(inbound = toPhone, outbound = toHost)
            val host = MemoryTransport(inbound = toHost, outbound = toPhone)
            phone.other = host
            host.other = phone
            return phone to host
        }
    }
}
