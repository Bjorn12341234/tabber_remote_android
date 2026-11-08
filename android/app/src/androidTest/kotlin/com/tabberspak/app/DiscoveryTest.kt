package com.tabberspak.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.random.Random
import kotlin.time.Duration.Companion.seconds

/**
 * Finding Tabber Studio with Bonjour on a real Android network stack: this phone advertises a
 * Tabber Studio of its own, and Discovery finds it.
 *
 * The regression: a lookup runs between reconnect rounds, and closing it once handed NsdManager's
 * late callbacks to an executor already shut down, which ended the app on NsdManager's thread
 * (found by scripts/studio-check.py: the app died when Tabber Studio quit). The pauses between the
 * lookups are where those callbacks arrive.
 */
@RunWith(AndroidJUnit4::class)
class DiscoveryTest {
    private val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val hostId = UUID.randomUUID().toString()
    private val port = 47_000 + Random.nextInt(1_000)
    private val registered = CountDownLatch(1)
    private val advertised = object : NsdManager.RegistrationListener {
        override fun onServiceRegistered(info: NsdServiceInfo) = registered.countDown()
        override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        override fun onServiceUnregistered(info: NsdServiceInfo) {}
        override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
    }

    @Before fun advertise() {
        val info = NsdServiceInfo().apply {
            serviceName = "Discovery Test ${hostId.take(8)}"
            serviceType = Discovery.SERVICE_TYPE
            port = this@DiscoveryTest.port
            setAttribute("id", hostId)
            setAttribute("v", "1.9")
        }
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, advertised)
        assertTrue("the test's own Tabber Studio is advertised", registered.await(10, TimeUnit.SECONDS))
    }

    @After fun withdraw() {
        runCatching { nsd.unregisterService(advertised) }
    }

    @Test fun aPairedComputerIsFoundAgainRoundAfterRound() = runBlocking {
        val discovery = Discovery(context)
        repeat(3) { round ->
            val route = discovery.lookup(hostId, within = 15.seconds)
            assertEquals("round $round: where the computer answers", port, route?.port)
            delay(1_500) // the closed lookup's late callbacks arrive here
        }
    }

    @Test fun browsingShowsTheComputerWithItsVersions() = runBlocking {
        val discovery = Discovery(context)
        val list = withTimeout(15.seconds) {
            discovery.browse().first { found -> found.any { it.hostId == hostId && it.route != null } }
        }
        val computer = list.first { it.hostId == hostId }
        assertEquals("Discovery Test ${hostId.take(8)}", computer.name)
        assertEquals(listOf("1.9"), computer.versions)
        assertEquals(port, computer.route?.port)
        delay(1_500) // as above: leaving the Find screen closes the browse the same way
    }
}
