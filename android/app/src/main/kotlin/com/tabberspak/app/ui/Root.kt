package com.tabberspak.app.ui

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import kotlinx.coroutines.delay

/**
 * The app: Welcome until a computer is paired (or the demo runs), then Studio's own views as
 * tabs, with the transport above the tab bar in the same place on every screen (principle 5).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun RootScreen(model: AppModel) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(model.feedback) {
        if (model.feedback.second == 0) return@LaunchedEffect
        haptics.performHapticFeedback(
            when (model.feedback.first) {
                AppModel.Feedback.TAP -> HapticFeedbackType.SegmentTick
                AppModel.Feedback.RECORD -> HapticFeedbackType.LongPress
                AppModel.Feedback.STOP -> HapticFeedbackType.Confirm
                AppModel.Feedback.GO_AGAIN -> HapticFeedbackType.ContextClick
                AppModel.Feedback.DISCARD -> HapticFeedbackType.Reject
                AppModel.Feedback.FAILURE -> HapticFeedbackType.Reject
            },
        )
    }
    KeepAwake(model.bar.connected && model.keepAwake)

    // Test tags double as resource ids, so UI Automator scripts on the emulator find the same
    // controls the Compose tests do (android/scripts/studio-check.py).
    Box(Modifier.fillMaxSize().background(Studio.bg1).semantics { testTagsAsResourceId = true }) {
        if (model.known == null && !model.isDemo) {
            WelcomeScreen(model)
        } else {
            // While the keyboard is up (Chat's field), it covers the transport and the tabs, as on
            // the iPhone, and the field sits right above it.
            val typing = WindowInsets.isImeVisible
            Column(Modifier.fillMaxSize().imePadding()) {
                Box(Modifier.weight(1f)) {
                    when (model.screen) {
                        AppModel.Screen.TRACKS -> TracksScreen(model)
                        AppModel.Screen.TAB -> TabScreen(model)
                        AppModel.Screen.MIXER -> MixerScreen(model)
                        AppModel.Screen.TUNER -> TunerScreen(model)
                        AppModel.Screen.CHAT -> ChatScreen(model)
                    }
                }
                if (!typing) {
                    TransportBar(model)
                    ScreenBar(model)
                }
            }
        }
        when (val pairing = model.pairing) {
            is AppModel.Pairing.Working -> PairingOverlay("Pairing with ${pairing.name}")
            is AppModel.Pairing.Code -> CodeOverlay(pairing.name, pairing.code)
            else -> Unit
        }
    }

    (model.pairing as? AppModel.Pairing.Failed)?.let { failed ->
        AlertDialog(
            onDismissRequest = model::clearPairing,
            title = { Text("Pairing did not work") },
            text = { Text(failed.message) },
            confirmButton = { TextButton(onClick = model::clearPairing) { Text("OK") } },
            containerColor = Studio.bg2,
        )
    }
    if (model.showingComputer) {
        ModalBottomSheet(onDismissRequest = { model.showingComputer = false }, containerColor = Studio.bg1) {
            ComputerSheet(model)
        }
    }
    if (model.choosingPlace) {
        ModalBottomSheet(onDismissRequest = { model.choosingPlace = false }, containerColor = Studio.bg1) {
            GoToSheet(model)
        }
    }
}

/** The screen stays awake while a session is open, if the setting says so. */
@Composable
private fun KeepAwake(on: Boolean) {
    val activity = LocalActivity.current ?: return
    LaunchedEffect(on) {
        if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}

/** The tabs, named for what they do, as Studio's views. */
@Composable
private fun ScreenBar(model: AppModel) {
    NavigationBar(containerColor = Studio.bg0) {
        val items = listOf(
            Triple(AppModel.Screen.TRACKS, "Tracks", Icons.Filled.LibraryMusic),
            Triple(AppModel.Screen.TAB, "Tab", Icons.Filled.MusicNote),
            Triple(AppModel.Screen.MIXER, "Mixer", Icons.Filled.Tune),
            Triple(AppModel.Screen.TUNER, "Tuner", Icons.Filled.GraphicEq),
            Triple(AppModel.Screen.CHAT, "Chat", Icons.AutoMirrored.Filled.Chat),
        )
        for ((screen, label, icon) in items) {
            NavigationBarItem(
                selected = model.screen == screen,
                onClick = { model.screen = screen },
                icon = { Icon(icon, contentDescription = null) },
                // The tabs' names grow with the text up to half again, on one line: past that a
                // word would break ("Track / s"); TalkBack reads each tab's name at any size.
                label = { LimitedScale(1.5f) { Text(label, maxLines = 1, softWrap = false) } },
                modifier = Modifier.testTag("tab-${label.lowercase()}"),
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = Studio.accent, selectedTextColor = Studio.accent, indicatorColor = Studio.bg2,
                    unselectedIconColor = Studio.text2, unselectedTextColor = Studio.text2,
                ),
            )
        }
    }
}

/**
 * Tabber Studio's transport, in the same place on every screen: Stop, Play and Record, then the
 * position. While recording, the position becomes the take's time in red; during a count-in, the
 * words in amber. Tapping the position goes to the start or to a marker.
 */
@Composable
fun TransportBar(model: AppModel) {
    val bar = model.bar
    val connected = bar.connected
    Row(
        Modifier.fillMaxWidth().background(Studio.bg0).padding(horizontal = 8.dp, vertical = 4.dp).alpha(if (connected) 1f else 0.45f),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(52.dp).clickable(enabled = connected, role = Role.Button, onClick = model::stopButton)
                .semantics { contentDescription = if (bar.playing || bar.recording) "Stop" else "Go to the start" }
                .testTag("stop"),
            contentAlignment = Alignment.Center,
        ) { Box(Modifier.size(16.dp).clip(RoundedCornerShape(2.dp)).background(Studio.text1)) }

        // Tabber Studio's Play is Play / Pause: Pause stops right there, Play goes on from it.
        Box(
            Modifier.size(52.dp).clickable(enabled = connected, role = Role.Button, onClick = model::playOrStop)
                .semantics { contentDescription = if (bar.playing) "Pause" else "Play"; selected = bar.playing }
                .alpha(if ("play" in model.pending) 0.5f else 1f).testTag("play"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (bar.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = null,
                tint = if (bar.playing && !bar.recording) Studio.accent else Studio.text1, modifier = Modifier.size(28.dp),
            )
        }

        Box(
            Modifier.size(52.dp).clickable(enabled = connected, role = Role.Button, onClick = model::record)
                .semantics {
                    contentDescription = when {
                        bar.recording -> "Stop recording"
                        bar.armed.isEmpty() -> "Record"
                        else -> "Record on ${bar.armed.joinToString(" and ")}"
                    }
                }
                .alpha(if ("record" in model.pending || "stop" in model.pending) 0.5f else 1f).testTag("record"),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(38.dp).clip(CircleShape).background(if (bar.recording) Studio.record.copy(alpha = 0.22f) else Color.Transparent))
            Box(Modifier.size(19.dp).clip(CircleShape).background(Studio.record))
        }
        Spacer(Modifier.weight(1f))
        Readout(model)
    }
}

/** Where the song is: Tabber Studio's POS, or the take's time while recording. */
@Composable
private fun Readout(model: AppModel) {
    val bar = model.bar
    val since = bar.recordingSince
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    if (since != null) {
        LaunchedEffect(since) {
            while (true) {
                now = System.currentTimeMillis()
                delay(250)
            }
        }
    }
    val spoken = when {
        since != null -> "Recording"
        bar.countingIn -> "Count-in"
        bar.position != null -> "Bar ${bar.position.bar}, beat ${bar.position.beat}"
        else -> "Not connected"
    }
    Row(
        Modifier.sizeIn(minHeight = 48.dp).clip(RoundedCornerShape(Studio.radiusControl))
            .clickable(enabled = bar.connected, role = Role.Button) { model.choosingPlace = true }
            .semantics { contentDescription = "$spoken. Go to the start or a marker." }
            .padding(horizontal = 12.dp).testTag("readout"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        when {
            since != null -> {
                Box(Modifier.size(8.dp).clip(CircleShape).background(Studio.record))
                Text("REC", color = Studio.record, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                Text(Format.clock((now - since) / 1000.0), style = Studio.counter(20, FontWeight.SemiBold), color = Studio.record)
            }
            bar.countingIn -> Text("Count-in", color = Studio.playhead, fontWeight = FontWeight.SemiBold)
            bar.position != null -> {
                ReadoutLabel("POS")
                Text(Format.position(bar.position.bar, bar.position.beat), style = Studio.counter(20, FontWeight.SemiBold), color = Studio.text1)
            }
            else -> Text("Not connected", color = Studio.text2, fontSize = 15.sp)
        }
    }
}

/** Go to: the start or one of the song's markers, from the transport's position. */
@Composable
private fun GoToSheet(model: AppModel) {
    Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
        Text("Go to", fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = Studio.text1, modifier = Modifier.padding(16.dp))
        LazyColumn {
            item { GoToRow("Start", 1) { model.goToStart(); model.choosingPlace = false } }
            items(model.state.markers, key = { it.id }) { marker ->
                GoToRow(marker.name, marker.bar) { model.go(marker); model.choosingPlace = false }
            }
        }
    }
}

@Composable
private fun GoToRow(name: String, bar: Int, go: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().sizeIn(minHeight = 52.dp).clickable(role = Role.Button, onClick = go)
            .semantics { contentDescription = "$name, bar $bar" }.padding(horizontal = 16.dp).testTag("goto-$name"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, color = Studio.text1, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Text("Bar $bar", style = Studio.counter(15), color = Studio.text2)
    }
}

@Composable
private fun PairingOverlay(text: String) {
    Box(Modifier.fillMaxSize().background(Studio.bg1.copy(alpha = 0.92f)).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            CircularProgressIndicator(color = Studio.text2)
            Text(text, color = Studio.text1, fontSize = 17.sp)
        }
    }
}

/** 6-digit pairing: the digits Tabber Studio shows too, and what to do there. */
@Composable
private fun CodeOverlay(name: String, code: String) {
    Box(Modifier.fillMaxSize().background(Studio.bg1).clickable(enabled = true) {}, contentAlignment = Alignment.Center) {
        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Check the code on $name", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 22.sp)
            Text(
                code.chunked(3).joinToString(" "), style = Studio.counter(44, FontWeight.Bold), color = Studio.text1,
                modifier = Modifier.semantics { contentDescription = "Code ${code.toList().joinToString(" ")}" }.testTag("pairing-code"),
            )
            Text(
                "Tabber Studio shows the same six digits. If they match, click Allow there. If they don't, click Don't Allow.",
                color = Studio.text2, fontSize = 16.sp,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CircularProgressIndicator(color = Studio.text2, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text("Waiting for $name", color = Studio.text2)
            }
        }
    }
}

/** Space a list keeps above the transport. */
@Composable
fun BottomGap() = Spacer(Modifier.height(16.dp).width(1.dp))

/** A screen still to come: its title and a plain sentence. */
@Composable
fun PendingScreen(model: AppModel, title: String) = ScreenScaffold(model, title) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Text("$title comes in the next build.", color = Studio.text2)
    }
}
