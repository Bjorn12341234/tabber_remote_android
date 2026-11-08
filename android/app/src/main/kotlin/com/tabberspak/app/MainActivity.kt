package com.tabberspak.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.tabberspak.remotekit.AppInfo
import com.tabberspak.remotekit.PairingLink
import com.tabberspak.remotekit.RemoteClient
import com.tabberspak.remotekit.RemoteError
import com.tabberspak.remotekit.OkHttpTransport
import com.tabberspak.remotekit.TransportFailure
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.time.Duration.Companion.seconds

/**
 * TA1's first screen: the pairing link the phone's camera hands over (or `adb shell am start
 * -d`), then pairing with the computer and its song's snapshot, read back. The session screens
 * replace it from TA2 on (android/README.md).
 */
class MainActivity : ComponentActivity() {
    private var link by mutableStateOf<PairingLink?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        take(intent)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Color(0xFFE5484D))) {
                Surface(Modifier.fillMaxSize()) { PairingScreen(link) }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        take(intent)
    }

    private fun take(intent: Intent?) {
        intent?.dataString?.let(PairingLink::parse)?.let { link = it }
    }
}

private val app = AppInfo(version = BuildConfig.VERSION_NAME, build = BuildConfig.VERSION_CODE.toString())

private fun deviceName(context: android.content.Context): String =
    Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL

@Composable
private fun PairingScreen(link: PairingLink?) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    var status by remember(link) {
        mutableStateOf(
            if (link == null) "Scan the pairing code in Tabber Studio with your camera." else "Pair with ${link.name}?",
        )
    }
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Tabber Spak", style = MaterialTheme.typography.headlineLarge)
        Text(status, Modifier.testTag("status"), style = MaterialTheme.typography.bodyLarge)
        if (link != null) {
            Button(onClick = {
                status = "Connecting to ${link.name}…"
                scope.launch {
                    status = withContext(Dispatchers.IO) { pair(link, deviceName(context)) }
                }
            }) { Text("Pair") }
        }
    }
}

/** Tries the link's routes in order, pairs on the first that answers, and reads the song back. */
private suspend fun pair(link: PairingLink, name: String): String {
    val signer = KeystoreSigner.loadOrCreate()
    var last = "Nothing answered at ${link.routes.joinToString()}."
    for (route in link.routes) {
        val client = RemoteClient(OkHttpTransport(route, link.pin)).apply { start() }
        try {
            client.sayHello(app, timeout = 5.seconds)
            val paired = client.pair(link.token, link.pin, signer, name = name, model = Build.MODEL)
            val song = try {
                val snapshot = client.subscribe(listOf("transport", "record", "tracks", "markers", "takes", "undo", "project"))
                "Its song is \"${snapshot.project.title}\" with ${snapshot.tracks.size} tracks."
            } catch (failure: RemoteError) {
                "It has no song to show: ${failure.message}"
            }
            return "Paired with ${paired.host.name} at $route. $song"
        } catch (failure: RemoteError) {
            return "${link.name} said no: ${failure.message}"
        } catch (failure: TransportFailure.WrongKey) {
            return "The computer at $route is not ${link.name}: its key does not match the code."
        } catch (failure: Exception) {
            last = "No answer from ${link.name} at $route (${failure.message})."
        } finally {
            client.close()
        }
    }
    return last
}
