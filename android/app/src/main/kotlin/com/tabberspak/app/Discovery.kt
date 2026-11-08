package com.tabberspak.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import com.tabberspak.remotekit.Route
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.Executor
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** A Tabber Studio found on the network with Bonjour (spec 3), as apple/RemoteKit's FoundComputer. */
data class FoundComputer(
    /** The computer's name, as Tabber Studio announces it. */
    val name: String,
    /** The host id from the TXT record: which paired computer this is. */
    val hostId: String?,
    val versions: List<String>,
    /** Where it answers, IPv4 first; null until resolved. */
    val route: Route?,
)

/**
 * Finding Tabber Studio with Android's NsdManager: browsing `_tabber-remote._tcp`, reading each
 * service's TXT record (`v`, `id`) and address, and finding a paired computer again after its
 * address or port changed (TR6). Android resolves a service at a time before Android 14, so
 * services are resolved one after another there.
 *
 * Callbacks run on NsdManager's own thread, as its overloads without an executor do. An executor
 * of the flow's own would have to be shut down when the flow closes, and NsdManager still delivers
 * to it afterwards (the unregistration's confirmation, a late update): a task rejected on
 * NsdManager's thread ends the app. Anything thrown there ends it too, so the calls made from a
 * callback are guarded.
 */
class Discovery(context: Context) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager

    /** Every Tabber Studio on the network, kept up to date until the flow is dropped. */
    fun browse(): Flow<List<FoundComputer>> = callbackFlow {
        val found = LinkedHashMap<String, FoundComputer>()
        val resolving = ArrayDeque<NsdServiceInfo>()
        var busy = false
        val callbacks = HashMap<String, Any>()
        var closed = false
        // NsdManager calls back on its own threads: the lists are touched under one lock.
        val lock = Any()

        fun publish() = trySend(synchronized(lock) { found.values.sortedBy { it.name.lowercase() } })

        fun take(info: NsdServiceInfo) {
            synchronized(lock) { found[info.serviceName] = computer(info) }
            publish()
        }

        fun resolveNext() {
            val next = synchronized(lock) {
                if (busy || closed) return
                resolving.removeFirstOrNull()?.also { busy = true }
            } ?: return
            val listener = object : NsdManager.ResolveListener {
                override fun onServiceResolved(info: NsdServiceInfo) {
                    take(info)
                    synchronized(lock) { busy = false }
                    resolveNext()
                }

                override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                    synchronized(lock) { busy = false }
                    resolveNext()
                }
            }
            @Suppress("DEPRECATION")
            if (runCatching { nsd.resolveService(next, listener) }.isFailure) {
                synchronized(lock) { busy = false }
            }
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                if (!info.serviceType.startsWith(SERVICE_TYPE)) return
                synchronized(lock) { found.putIfAbsent(info.serviceName, FoundComputer(info.serviceName, null, listOf("1"), null)) }
                publish()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val callback = object : NsdManager.ServiceInfoCallback {
                        override fun onServiceUpdated(updated: NsdServiceInfo) = take(updated)
                        override fun onServiceLost() {}
                        override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                            synchronized(lock) { callbacks.remove(info.serviceName) }
                        }
                        override fun onServiceInfoCallbackUnregistered() {}
                    }
                    // One callback a service: one found again (on another network) is already followed.
                    val fresh = synchronized(lock) { !closed && callbacks.putIfAbsent(info.serviceName, callback) == null }
                    if (fresh && runCatching { nsd.registerServiceInfoCallback(info, CALLING_THREAD, callback) }.isFailure) {
                        synchronized(lock) { callbacks.remove(info.serviceName) }
                    }
                } else {
                    synchronized(lock) { resolving.addLast(info) }
                    resolveNext()
                }
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                synchronized(lock) { found.remove(info.serviceName) }
                publish()
            }

            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { close() }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        publish()
        awaitClose {
            val followed = synchronized(lock) {
                closed = true
                callbacks.values.toList().also { callbacks.clear() }
            }
            runCatching { nsd.stopServiceDiscovery(listener) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                followed.forEach { runCatching { nsd.unregisterServiceInfoCallback(it as NsdManager.ServiceInfoCallback) } }
            }
        }
    }

    /** Where a paired computer is now, by its host id (TR6); null when Bonjour does not find it in time. */
    suspend fun lookup(hostId: String, within: Duration = 2.seconds): Route? = withTimeoutOrNull(within) {
        browse().first { list -> list.any { it.hostId == hostId && it.route != null } }
            .first { it.hostId == hostId }.route
    }

    private fun computer(info: NsdServiceInfo): FoundComputer {
        val txt = info.attributes.mapValues { (_, value) -> value?.toString(Charsets.UTF_8) ?: "" }
        return FoundComputer(
            name = info.serviceName,
            hostId = txt["id"]?.takeIf { it.isNotEmpty() },
            versions = (txt["v"] ?: "1").split(',').filter { it.isNotEmpty() },
            route = route(info),
        )
    }

    /** IPv4 first: it needs no interface name in a URL (Known traps). */
    private fun route(info: NsdServiceInfo): Route? {
        val addresses: List<InetAddress> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            info.hostAddresses
        } else {
            @Suppress("DEPRECATION")
            listOfNotNull(info.host)
        }
        if (info.port <= 0) return null
        val address = addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull { !it.isLinkLocalAddress } ?: return null
        return Route(address.hostAddress ?: return null, info.port)
    }

    companion object {
        const val SERVICE_TYPE = "_tabber-remote._tcp"

        /** NsdManager's own thread, as its overloads without an executor use: never shut down, never rejects. */
        private val CALLING_THREAD = Executor(Runnable::run)
    }
}
