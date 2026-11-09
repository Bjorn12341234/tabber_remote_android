package com.tabberspak.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.tabberspak.remotekit.KnownHost
import com.tabberspak.remotekit.Route
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** The app's model as a phone starts it, outside the demo the screens' tests use. */
@RunWith(AndroidJUnit4::class)
class AppModelTest {
    /**
     * A phone that paired before starts its session as the model is made. The model's state must
     * all be set by then: Kotlin sets properties in the order they are written, and a session
     * started above the plug-in state stopped the app at launch on every paired phone (found
     * while porting TR44: the demo never starts that way).
     */
    @Test fun aPairedPhoneStartsItsSessionAtLaunch() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val host = KnownHost("h-nowhere", "Nowhere Mac", "A".repeat(43), listOf(Route("127.0.0.1", 1)))
        val hosts = HostStore(Prefs(context))
        hosts.save(host)
        var model: AppModel? = null
        try {
            instrumentation.runOnMainSync { model = AppModel(context) }
            assertEquals("the remembered computer", host, model?.known)
            assertEquals("Nowhere Mac", model?.computerName)
        } finally {
            instrumentation.runOnMainSync { model?.forget() }
            hosts.clear()
        }
    }
}
