package com.tabberspak.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.app.Discovery
import com.tabberspak.app.FoundComputer
import com.tabberspak.remotekit.LinkState
import com.tabberspak.remotekit.PairingLink
import com.tabberspak.remotekit.RemoteClient
import com.tabberspak.remotekit.Trouble
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch

/**
 * The first screen on a fresh install (plan: TR6): what Tabber Spak is for, the three steps that
 * pair it, and the demo for trying it without a computer. On Android the phone's own camera app
 * scans the pairing code and opens Tabber Spak with it (the owner's choice, 2026-11-08).
 */
@Composable
fun WelcomeScreen(model: AppModel) {
    var finding by remember { mutableStateOf(false) }
    if (finding) {
        FindComputerScreen(model) { finding = false }
        return
    }
    Column(
        Modifier.fillMaxSize().background(Studio.bg1).statusBarsPadding().navigationBarsPadding()
            .verticalScroll(rememberScrollState()).padding(24.dp).widthIn(max = 560.dp),
    ) {
        Spacer(Modifier.height(24.dp))
        SpakMark()
        Text("Tabber Spak", color = Studio.text1, fontWeight = FontWeight.Bold, fontSize = 34.sp, modifier = Modifier.padding(top = 20.dp))
        Text(
            "Play, record and mix in Tabber Studio from across the room. The sound plays on your computer.",
            color = Studio.text2, fontSize = 20.sp, modifier = Modifier.padding(top = 6.dp),
        )
        Column(Modifier.padding(top = 36.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Step(1, "On your computer, open Tabber Studio's Preferences › Remote and turn it on.")
            Step(2, "Click Pair. A code appears.")
            Step(3, "Point this phone's camera at the code and open the link it shows. Tabber Spak pairs by itself.")
        }
        Spacer(Modifier.height(36.dp))
        StudioButton("Find my computer", onClick = { finding = true }, kind = ButtonKind.PRIMARY, modifier = Modifier.fillMaxWidth().testTag("get-started"))
        PasteLink(model)
        StudioButton("Try the demo", onClick = { model.startDemo() }, kind = ButtonKind.QUIET, modifier = Modifier.fillMaxWidth().padding(top = 6.dp).testTag("demo"))
    }
}

/** The app's mark: the record dot on Studio's surface. */
@Composable
private fun SpakMark() {
    Row(
        Modifier.size(64.dp).clip(RoundedCornerShape(14.dp)).background(Studio.bg2),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        Spacer(Modifier.size(26.dp).clip(RoundedCornerShape(13.dp)).background(Studio.record))
    }
}

@Composable
private fun Step(number: Int, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text("$number", style = Studio.counter(17), color = Studio.text3)
        Text(text, color = Studio.text1, fontSize = 17.sp)
    }
}

/** For a camera app that copies the link rather than opening it: paste it here. */
@Composable
private fun PasteLink(model: AppModel) {
    var open by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    StudioButton("Paste the pairing link", onClick = { open = true }, kind = ButtonKind.QUIET, modifier = Modifier.fillMaxWidth().padding(top = 6.dp).testTag("paste-link"))
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            title = { Text("Paste the pairing link") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("It starts with tabber-remote://pair.", color = Studio.text2)
                    OutlinedTextField(text, { text = it; wrong = false }, singleLine = true, modifier = Modifier.testTag("link-field"),
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Studio.accent))
                    if (wrong) Text("That is not a Tabber Studio pairing link.", color = Studio.record, modifier = Modifier.testTag("not-a-code"))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val link = PairingLink.parse(text.trim())
                    if (link == null) wrong = true else { open = false; scope.launch { model.pair(link) } }
                }, modifier = Modifier.testTag("pair-link-button")) { Text("Pair") }
            },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
            containerColor = Studio.bg2,
        )
    }
}

/**
 * The computers Bonjour finds on this Wi-Fi. Each pairs with the 6-digit code; the camera's code
 * works without this list, because it carries the computer's address.
 */
@Composable
fun FindComputerScreen(model: AppModel, back: () -> Unit) {
    val context = LocalContext.current
    val discovery = remember { Discovery(context) }
    val found by remember { discovery.browse() }.collectAsState(initial = emptyList())
    var searchedLong by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        delay(6000)
        searchedLong = true
    }
    androidx.activity.compose.BackHandler(onBack = back)
    Column(Modifier.fillMaxSize().background(Studio.bg1).statusBarsPadding().navigationBarsPadding().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StudioButton("Back", onClick = back, kind = ButtonKind.QUIET)
            Text("Find my computer", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, modifier = Modifier.semantics { heading() })
        }
        Text("On this Wi-Fi", color = Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
        for (computer in found) {
            Column(
                Modifier.fillMaxWidth().sizeIn(minHeight = 56.dp).clip(RoundedCornerShape(Studio.radiusCard)).background(Studio.bg2)
                    .clickable(role = Role.Button) { scope.launch { model.pairWithCode(computer) } }
                    .padding(horizontal = 14.dp, vertical = 10.dp).testTag("found-computer"),
            ) {
                Text(computer.name, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text("Pair with a 6-digit code", color = Studio.text2, fontSize = 14.sp)
            }
            Spacer(Modifier.height(8.dp))
        }
        if (found.isEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.testTag("searching")) {
                CircularProgressIndicator(color = Studio.text2, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Text("Looking for Tabber Studio", color = Studio.text2)
            }
        }
        Text("Your computer shows here while Tabber Studio's remote is on.", color = Studio.text3, fontSize = 13.sp, modifier = Modifier.padding(top = 12.dp))
        if (found.isEmpty() && searchedLong) {
            Text(
                "Nothing found yet. The code works without this list, because it carries the computer's address: point the camera at it. On a guest or venue Wi-Fi, use your own router.",
                color = Studio.text2, fontSize = 15.sp, modifier = Modifier.padding(top = 16.dp).testTag("nothing-found"),
            )
        }
    }
}

/**
 * When the phone cannot use its computer: what happened, what to check, and the action that fixes
 * it (plan: TR6's fix-it cards, principle 3), in the screen's own voice: no alert box.
 */
@Composable
fun FixItCard(model: AppModel, trouble: Trouble, computer: String) {
    val title = when (trouble) {
        Trouble.Unreachable -> "Can't reach $computer"
        Trouble.LocalNetworkDenied -> "Tabber Spak can't use the local network"
        is Trouble.UpdateStudio -> "Update Tabber Studio"
        is Trouble.UpdateSpak -> "Update Tabber Spak"
        Trouble.Forgotten -> "$computer no longer knows this phone"
        Trouble.OtherComputer -> "A different computer answers"
    }
    val message = when (trouble) {
        Trouble.Unreachable -> "Tabber Spak keeps trying. In the meantime, check that:"
        Trouble.LocalNetworkDenied -> "It needs the local network to reach $computer. Allow Tabber Spak to find devices nearby in Settings."
        is Trouble.UpdateStudio -> "Tabber Studio on $computer is too old for this Tabber Spak. Update Tabber Studio on the computer, then try again."
        is Trouble.UpdateSpak -> "Tabber Studio on $computer is newer than this Tabber Spak. Update Tabber Spak from Google Play."
        Trouble.Forgotten -> "It was removed in Tabber Studio's Preferences › Remote. Pair again to use it."
        Trouble.OtherComputer -> "The computer at this address is not the one this phone paired with. Pair again with the right one."
    }
    val checks = if (trouble == Trouble.Unreachable) listOf(
        "Tabber Studio is open, with Preferences › Remote turned on. If Preferences has no Remote page, update Tabber Studio.",
        "This phone is on the same Wi-Fi as the computer. Away from it, Tailscale is on, on both, with the same account.",
        "The Wi-Fi isn't a guest or venue network. Those keep devices apart, so bring your own router.",
        "No VPN but Tailscale is on. Another VPN can keep this phone from the computer.",
    ) else emptyList()
    Column(Modifier.fillMaxWidth().testTag("fix-it"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(title, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, modifier = Modifier.testTag("fix-it-title"))
        Text(message, color = Studio.text2, fontSize = 17.sp)
        for (check in checks) Text(check, color = Studio.text1, fontSize = 17.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 8.dp)) {
            when (trouble) {
                Trouble.Unreachable -> {
                    StudioButton("Try again", onClick = model::wake, modifier = Modifier.testTag("fix-it-retry"))
                    StudioButton("Pair again", onClick = model::forget, kind = ButtonKind.QUIET, modifier = Modifier.testTag("fix-it-pair"))
                }
                is Trouble.UpdateStudio, is Trouble.UpdateSpak ->
                    StudioButton("Try again", onClick = model::retry, modifier = Modifier.testTag("fix-it-retry"))
                Trouble.Forgotten, Trouble.OtherComputer ->
                    StudioButton("Pair again", onClick = model::forget, modifier = Modifier.testTag("fix-it-pair"))
                Trouble.LocalNetworkDenied -> Unit
            }
        }
    }
}

/**
 * The Computer sheet, from the computer's name at the top of every screen: which computer this
 * phone runs, how the line is, the response time, and pairing again or forgetting it.
 */
@Composable
fun ComputerSheet(model: AppModel) {
    val scope = rememberCoroutineScope()
    var confirmForget by remember { mutableStateOf(false) }
    var times by remember { mutableStateOf(model.responseTimes()) }
    val link = when (val l = model.state.link) {
        LinkState.Idle -> "Not connected"
        LinkState.Connecting -> "Connecting"
        is LinkState.Connected -> if (l.busy) "Connected, Tabber Studio is busy" else "Connected"
        LinkState.Reconnecting -> "Reconnecting"
        is LinkState.Failed -> "Stopped"
    }
    Column(Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Computer", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, modifier = Modifier.weight(1f).semantics { heading() })
            StudioButton("Done", onClick = { model.showingComputer = false }, kind = ButtonKind.QUIET, modifier = Modifier.testTag("done"))
        }
        Labeled("Computer", model.computerName, "host-name")
        Labeled("State", link, "link-state")
        val route = model.known?.routes?.firstOrNull()
        if (route != null && !model.isDemo) Labeled("Address", route.toString(), "address")
        model.state.trouble?.let { FixItCard(model, it, model.computerName) }
        HorizontalDivider(color = Studio.edge)
        if (model.isDemo) {
            StudioButton("Leave the demo", onClick = { model.showingComputer = false; model.leaveDemo() }, modifier = Modifier.fillMaxWidth().testTag("leave-demo"))
        } else if (model.known != null) {
            StudioButton("Forget this computer", onClick = { confirmForget = true }, kind = ButtonKind.DESTRUCTIVE, modifier = Modifier.fillMaxWidth().testTag("forget"))
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Keep the screen awake during a session", color = Studio.text1, modifier = Modifier.weight(1f))
            Switch(model.keepAwake, { model.keepAwake = it }, colors = SwitchDefaults.colors(checkedTrackColor = Studio.accent), modifier = Modifier.testTag("keep-awake"))
        }
        HorizontalDivider(color = Studio.edge)
        Text("Response time", color = Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        Labeled("Typical", times.median?.let { "${it.inWholeMilliseconds} ms" } ?: "Not yet", "response-typical")
        Labeled("19 in 20 taps within", times.p95?.let { "${it.inWholeMilliseconds} ms" } ?: "Not yet", "response-p95")
        Text(
            when (times.count) {
                0 -> "Tap a control, like Play, and the time ${model.computerName} takes to answer shows here."
                1 -> "From a tap on this phone to ${model.computerName}'s answer, over 1 tap."
                else -> "From a tap on this phone to ${model.computerName}'s answer, over the last ${times.count} taps."
            },
            color = Studio.text3, fontSize = 13.sp, modifier = Modifier.testTag("response-note"),
        )
        // The sheet reads the times back once they are forgotten, not before.
        StudioButton("Start again", onClick = { scope.launch { model.startResponseTimesAgain(); times = model.responseTimes() } }, enabled = times.count > 0,
            kind = ButtonKind.QUIET, modifier = Modifier.testTag("response-again"))
        HorizontalDivider(color = Studio.edge)
        Labeled("Tabber Spak", "${model.app.version} (${model.app.build})", "version")
        Labeled("Protocol", RemoteClient.PROTOCOL_VERSIONS.joinToString(", "), "protocol")
        Spacer(Modifier.height(12.dp))
    }
    if (confirmForget) {
        AlertDialog(
            onDismissRequest = { confirmForget = false },
            title = { Text("Forget ${model.computerName}?") },
            text = { Text("To use it again, pair again with its code.") },
            confirmButton = { TextButton(onClick = { confirmForget = false; model.showingComputer = false; model.forget() }) { Text("Forget", color = Studio.record) } },
            dismissButton = { TextButton(onClick = { confirmForget = false }) { Text("Cancel") } },
            containerColor = Studio.bg2,
        )
    }
}

@Composable
private fun Labeled(label: String, value: String, tag: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = "$label, $value" }, verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Studio.text2, modifier = Modifier.weight(1f))
        Text(value, color = Studio.text1, modifier = Modifier.testTag(tag))
    }
}
