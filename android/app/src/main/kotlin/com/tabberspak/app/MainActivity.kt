package com.tabberspak.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.tabberspak.app.ui.RootScreen
import com.tabberspak.app.ui.StudioTheme
import com.tabberspak.remotekit.PairingLink
import kotlinx.coroutines.launch

/**
 * The one activity. The pairing QR code's link arrives here from the phone's camera app
 * (`tabber-remote://pair?...`); launch extras set up tests and screenshots (AppModel.launch).
 */
class MainActivity : ComponentActivity() {
    private val model: AppModel get() = (application as SpakApplication).model

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The app is always dark, as Tabber Studio is: light status and navigation icons, whatever
        // the phone's own light or dark setting.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        if (savedInstanceState == null) take(intent)
        setContent { StudioTheme { RootScreen(model) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        take(intent)
    }

    /** Back on the screen: reconnect at once if the line went quiet (TR6, under a second). */
    override fun onResume() {
        super.onResume()
        model.wake()
    }

    private fun take(intent: Intent?) {
        intent ?: return
        val link = intent.dataString?.let(PairingLink::parse)
        if (link != null) {
            lifecycleScope.launch { model.pair(link) }
        } else if (BuildConfig.DEBUG) {
            // The launch options for tests and scripts, in debug builds only: any app may start
            // this activity, and in a release build these would let it pair the phone elsewhere
            // or forget its computer. On the iPhone only Xcode passes launch arguments.
            model.launch(intent.extras)
        }
    }
}
