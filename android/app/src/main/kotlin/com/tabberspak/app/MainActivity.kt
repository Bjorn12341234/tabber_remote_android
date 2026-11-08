package com.tabberspak.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
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
        enableEdgeToEdge()
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
        } else {
            model.launch(intent.extras)
        }
    }
}
