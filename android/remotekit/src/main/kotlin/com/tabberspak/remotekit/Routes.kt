package com.tabberspak.remotekit

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicReference
import kotlin.time.Duration

/**
 * How long the computer takes to answer a change made on this phone: from sending it to applying
 * the answer, when the phone shows the confirmed state (plan: TR7's gate, 19 taps in 20 within
 * 150 ms on home Wi-Fi). As apple/RemoteKit's ResponseTimes.
 */
class ResponseTimes private constructor(val samples: List<Duration>) {
    constructor() : this(emptyList())

    val count: Int get() = samples.size

    /** Half the taps were answered within this. */
    val median: Duration? get() = percentile(50)

    /** 19 taps in 20 were answered within this. */
    val p95: Duration? get() = percentile(95)

    fun adding(sample: Duration): ResponseTimes = ResponseTimes((samples + sample).takeLast(KEPT))

    /** The nearest-rank percentile: the smallest answer time with at least [percent] of the answers at or under it. */
    fun percentile(percent: Int): Duration? {
        if (samples.isEmpty()) return null
        val sorted = samples.sorted()
        val rank = (percent * sorted.size + 99) / 100
        return sorted[rank.coerceIn(1, sorted.size) - 1]
    }

    companion object {
        /** Enough for a rehearsal, small enough to sort each second. */
        const val KEPT = 500

        /**
         * Whether a verb's answer is a tap's: reads are not, the chat's answers wait for the AI, and a
         * plug-in's insert waits for it to load.
         */
        fun counts(method: String): Boolean =
            method !in RemoteSession.READS && !method.startsWith("chat.") && method != "plugins.insert"
    }
}

/**
 * Every remembered address at once: the first that answers is the connection, as
 * apple/RemoteKit's RacingTransport (the owner, 2026-11-07: "it doesn't work when I'm not on the
 * same wifi"). Each frame sent before an answer goes to every address; the first to answer wins and
 * the others are dropped. Nothing is weaker for it: each address is its own TLS connection pinned
 * to the computer's key, and the first frame is the hello, which carries no secret. A wrong key at
 * one address is only a failure there.
 */
class RacingTransport(
    routes: List<Route>,
    make: (Route) -> RemoteTransport,
    private val onWinner: suspend (Route) -> Unit = {},
) : RemoteTransport {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private var candidates: List<Pair<Route, RemoteTransport>> = routes.distinct().map { it to make(it) }
    private val winner = AtomicReference<RemoteTransport?>(null)
    private val work = HashMap<Int, MutableList<Job>>()

    override suspend fun send(text: String) {
        winner.get()?.let { return it.send(text) }
        val all = lock.withLock { candidates }
        if (all.isEmpty()) throw TransportFailure.Unreachable("No address for the computer.")
        lock.withLock {
            all.forEachIndexed { index, (_, transport) ->
                work.getOrPut(index) { mutableListOf() }.add(scope.launch { runCatching { transport.send(text) } })
            }
        }
    }

    override suspend fun receive(): String? {
        winner.get()?.let { return it.receive() }
        val all = lock.withLock { candidates }
        if (all.isEmpty()) throw TransportFailure.Unreachable("No address for the computer.")
        val race = CompletableDeferred<Pair<Int, String>>()
        val failures = ArrayList<Throwable>()
        lock.withLock {
            all.forEachIndexed { index, (_, transport) ->
                work.getOrPut(index) { mutableListOf() }.add(scope.launch {
                    val outcome = runCatching { transport.receive() }
                    val frame = outcome.getOrNull()
                    if (frame != null) {
                        race.complete(index to frame)
                    } else {
                        val failure = outcome.exceptionOrNull() ?: TransportFailure.Closed(transport.closeCode)
                        val everyOne = synchronized(failures) { failures.add(failure); failures.size == all.size }
                        if (everyOne) race.completeExceptionally(telling(synchronized(failures) { failures.toList() }))
                    }
                })
            }
        }
        val (index, frame) = race.await()
        val chosen = all[index]
        val losers = lock.withLock {
            winner.set(chosen.second)
            val others = candidates.filterIndexed { i, _ -> i != index }.map { it.second }
            work.filterKeys { it != index }.values.flatten().forEach(Job::cancel)
            candidates = listOf(chosen)
            work.clear()
            others
        }
        losers.forEach(RemoteTransport::close)
        onWinner(chosen.first)
        return frame
    }

    override fun close() {
        winner.get()?.let { return it.close() }
        candidates.forEach { it.second.close() }
    }

    override val closeCode: Int? get() = winner.get()?.closeCode

    companion object {
        /** Once every address failed, the failure that says most: the local network refused, then any other, a wrong key last. */
        fun telling(failures: List<Throwable>): Throwable =
            failures.firstOrNull { it is TransportFailure.LocalNetworkDenied }
                ?: failures.firstOrNull { it !is TransportFailure.WrongKey }
                ?: failures.firstOrNull()
                ?: TransportFailure.Unreachable("No address answered.")
    }
}

/**
 * The addresses to try for a paired computer, with a Bonjour lookup between rounds, so a computer
 * whose address or port changed is found again without pairing (TR6). As apple/RemoteKit's
 * RouteBook; the lookup is the app's (Android's NsdManager).
 */
class RouteBook(routes: List<Route>, private val hostId: String, private val lookup: suspend (String) -> Route? = { null }) {
    private val lock = Mutex()

    @Volatile var routes: List<Route> = routes
        private set

    @Volatile var lastTried: Route? = null
        private set

    /** Attempt n: the remembered addresses in turn, then Bonjour. */
    suspend fun route(attempt: Int): Route = lock.withLock {
        val slot = attempt % (routes.size + 1)
        lastTried = if (slot < routes.size) routes[slot] else lookup(hostId) ?: routes.firstOrNull()
        lastTried ?: Route("127.0.0.1", 9474)
    }

    /** Every address to try at once (RacingTransport): the remembered ones, and on every other attempt the one Bonjour finds now. */
    suspend fun candidates(attempt: Int): List<Route> = lock.withLock {
        val all = routes.toMutableList()
        if (attempt % 2 == 1 || all.isEmpty()) {
            lookup(hostId)?.let { found -> if (found !in all) all.add(found) }
        }
        all
    }

    /** The address that answered, for [connected]. */
    suspend fun use(route: Route) = lock.withLock { lastTried = route }

    /**
     * After a connection: the route that worked goes first, and when the port moved, the other
     * addresses move with it (the computer has one port). Returns the new list when it changed.
     */
    suspend fun connected(): List<Route>? = lock.withLock {
        val used = lastTried ?: return@withLock null
        val next = mutableListOf(used)
        for (route in routes) {
            val moved = Route(route.host, used.port)
            if (moved !in next) next.add(moved)
        }
        val kept = next.take(KEPT)
        if (kept == routes) return@withLock null
        routes = kept
        kept
    }

    companion object {
        const val KEPT = 6
    }
}
