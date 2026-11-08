package com.tabberspak.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.RoutingSend
import com.tabberspak.remotekit.RoutingSource
import com.tabberspak.remotekit.RoutingState
import com.tabberspak.remotekit.SendLevel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Tabber Studio's Routing panel as a list for one thumb, as the iPhone's RoutingScreen.swift: each
 * track with its Output and its Sends, then each bus with its Output and what feeds it. In Tabber
 * Studio the Routing panel can sit as a tab beside the Mixer; here it is the Mixer's other view.
 */
@Composable
fun RoutingView(model: AppModel, routing: RoutingState) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (routing.buses.isEmpty()) {
            Text(
                "No buses yet. Add one with the mixer's + Bus button in Tabber Studio, and route to it here.",
                color = Studio.text2, fontSize = 15.sp, modifier = Modifier.padding(vertical = 8.dp).testTag("no-buses"),
            )
        }
        Heading("Tracks")
        routing.tracks.forEachIndexed { index, track -> TrackRouting(model, routing, track, index) }
        if (routing.buses.isNotEmpty()) {
            Heading("Buses")
            routing.buses.forEach { bus -> BusRouting(model, routing, bus) }
        }
    }
}

@Composable
private fun Heading(text: String) {
    Text(text, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
}

/** A track: its colour and name, where its sound goes, and its sends. */
@Composable
private fun TrackRouting(model: AppModel, routing: RoutingState, source: RoutingSource, index: Int) {
    val sends = routing.sendsFrom(source.stripId)
    val unsent = routing.buses.filter { bus -> sends.none { it.busId == bus.stripId } }
    val colour = Studio.track(model.state.tracks.firstOrNull { it.id == source.stripId }?.color, index)
    Column(
        Modifier.fillMaxWidth().studioCard().padding(horizontal = 14.dp, vertical = 10.dp).testTag("route-${source.name}"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(Modifier.padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.5.dp)).background(colour))
            Text(source.name, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.semantics { heading() })
        }
        OutputMenu(model, routing, source)
        for (send in sends) SendRow(model, send, source.name, routing.source(send.busId)?.name ?: "Bus")
        if (unsent.isNotEmpty()) {
            var adding by remember { mutableStateOf(false) }
            Box {
                Row(
                    Modifier.fillMaxWidth().sizeIn(minHeight = 44.dp).clickable(role = Role.Button) { adding = true }.testTag("add-send-${source.name}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, tint = Studio.text1, modifier = Modifier.size(18.dp))
                    Text("Add send", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                }
                DropdownMenu(expanded = adding, onDismissRequest = { adding = false }, containerColor = Studio.bg2) {
                    for (bus in unsent) {
                        DropdownMenuItem(
                            text = { Text("Send to ${bus.name}", color = Studio.text1) },
                            onClick = { adding = false; model.addSend(source.stripId, bus.stripId) },
                        )
                    }
                }
            }
        }
    }
}

/** A bus: where its sound goes, and what feeds it. */
@Composable
private fun BusRouting(model: AppModel, routing: RoutingState, bus: RoutingSource) {
    val (outputs, sends) = routing.feeding(bus.stripId)
    val fedBy = listOfNotNull(
        outputs.map { it.name }.takeIf { it.isNotEmpty() }?.let { "Output from ${names(it)}" },
        sends.mapNotNull { routing.source(it.stripId)?.name }.takeIf { it.isNotEmpty() }?.let { "Sends from ${names(it)}" },
    ).joinToString("\n").ifEmpty { "Nothing feeds it yet." }
    Column(
        Modifier.fillMaxWidth().studioCard().padding(horizontal = 14.dp, vertical = 10.dp).testTag("route-${bus.name}"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(bus.name, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(bottom = 2.dp).semantics { heading() })
        OutputMenu(model, routing, bus)
        Text(fedBy, color = Studio.text2, fontSize = 15.sp, modifier = Modifier.padding(vertical = 6.dp).testTag("fed-${bus.name}"))
    }
}

/** "A", "A and B", "A, B and C", as Tabber Studio lists names. */
private fun names(list: List<String>): String =
    if (list.size < 2) list.joinToString("") else list.dropLast(1).joinToString(", ") + " and " + list.last()

/**
 * Where a source's sound goes: the master or a bus, chosen from a menu as Tabber Studio's header
 * Output menu offers them. A bus that would feed back into this one is shown, and can't be chosen.
 */
@Composable
private fun OutputMenu(model: AppModel, routing: RoutingState, source: RoutingSource) {
    var open by remember { mutableStateOf(false) }
    val current = routing.outputName(source)
    Box {
        Row(
            Modifier.fillMaxWidth().sizeIn(minHeight = 44.dp)
                .clickable(role = Role.Button) { open = true }
                .alpha(if ("output-${source.stripId}" in model.pending) 0.5f else 1f)
                .semantics(mergeDescendants = true) { contentDescription = "Output of ${source.name}"; stateDescription = current }
                .testTag("output-${source.name}"),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Output", color = Studio.text2, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Text(
                current, color = if (source.output == RoutingState.MASTER) Studio.text1 else Studio.accent,
                fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
            )
            Icon(Icons.Filled.UnfoldMore, contentDescription = null, tint = Studio.text2, modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = Studio.bg2) {
            OutputChoice("Master", chosen = source.output == RoutingState.MASTER, enabled = true) {
                open = false
                model.setOutput(source, RoutingState.MASTER)
            }
            for (bus in routing.outputsFor(source)) {
                val loop = if (source.isBus) routing.wouldLoop(source.stripId, bus.stripId) else null
                OutputChoice(
                    if (loop != null) "${bus.name}, would loop: ${loop.joinToString(" → ")}" else bus.name,
                    chosen = source.output == bus.stripId, enabled = loop == null, tag = "choose-output-${bus.name}",
                ) {
                    open = false
                    model.setOutput(source, bus.stripId)
                }
            }
        }
    }
}

@Composable
private fun OutputChoice(text: String, chosen: Boolean, enabled: Boolean, tag: String = "choose-output-$text", onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text, color = if (enabled) Studio.text1 else Studio.text3) },
        onClick = onClick, enabled = enabled,
        leadingIcon = { if (chosen) Icon(Icons.Filled.Check, contentDescription = "Chosen", tint = Studio.text1) },
        modifier = Modifier.semantics { if (chosen) stateDescription = "Chosen" }.testTag(tag),
    )
}

/**
 * One send, as Tabber Studio's mixer draws it: the bus name, a thin track with the thumb at the
 * level, and PRE when it taps before the fader. Drag from where it is (no jump on touch);
 * double-tap for silence, as Tabber Studio's double-click does.
 */
@Composable
private fun SendRow(model: AppModel, send: RoutingSend, trackName: String, busName: String) {
    val scope = rememberCoroutineScope()
    var dragLevel by remember { mutableStateOf<Double?>(null) }
    val large = LocalDensity.current.fontScale >= 1.5f
    // The bus, the level and the bar are one control for TalkBack: "Send to Reverb, -12.0 decibels".
    val adjustable = Modifier
        .semantics(mergeDescendants = true) {
            contentDescription = "Send to $busName"
            stateDescription = send.levelDb?.let { String.format(java.util.Locale.ROOT, "%.1f decibels", it) } ?: "silent"
            progressBarRangeInfo = ProgressBarRangeInfo(send.level.toFloat(), 0f..1f, steps = 19)
            setProgress { value -> model.setSendLevel(send, value.toDouble().coerceIn(0.0, 1.0)); true }
        }
        .testTag("send-$trackName-$busName")

    @Composable
    fun Name() = Column(Modifier.widthIn(min = 72.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(busName, color = Studio.text2, fontSize = 15.sp, maxLines = 1)
        Text(dragLevel?.let(SendLevel::label) ?: send.levelLabel, style = Studio.counter(12), color = Studio.text2, maxLines = 1)
    }

    @Composable
    fun Bar(modifier: Modifier) {
        var start by remember { mutableStateOf(0.0) }
        var moved by remember { mutableStateOf(0f) }
        SendTrack(
            dragLevel ?: send.level,
            modifier.sizeIn(minWidth = 60.dp).height(44.dp)
                .pointerInput(send.id) {
                    detectHorizontalDragGestures(
                        onDragStart = { start = send.level; moved = 0f },
                        onDragEnd = { scope.launch { delay(400); dragLevel = null } },
                        onDragCancel = { scope.launch { delay(400); dragLevel = null } },
                    ) { change, amount ->
                        change.consume()
                        moved += amount
                        val next = (start + moved / size.width.coerceAtLeast(1)).coerceIn(0.0, 1.0)
                        dragLevel = next
                        model.setSendLevel(send, next)
                    }
                }
                .pointerInput(send.id) { detectTapGestures(onDoubleTap = { model.setSendLevel(send, 0.0) }) },
        )
    }

    @Composable
    fun RowScope.Pre() = LetterButton(
        "PRE", send.preFader, Studio.text2, "Pre-fader, send to $busName", Modifier.testTag("pre-$trackName-$busName"),
        pending = "pre-${send.id}" in model.pending,
    ) { model.setPreFader(send, !send.preFader) }

    @Composable
    fun Remove() = Box(
        Modifier.size(44.dp).clickable(role = Role.Button) { model.removeSend(send) }
            .semantics { contentDescription = "Remove send to $busName" }.testTag("remove-send-$trackName-$busName"),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Outlined.RemoveCircleOutline, contentDescription = null, tint = Studio.text2) }

    if (large) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Column(adjustable, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Name()
                Bar(Modifier.fillMaxWidth())
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Pre()
                Remove()
            }
        }
    } else {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(adjustable.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Name()
                Bar(Modifier.weight(1f))
            }
            Pre()
            Remove()
        }
    }
}

/** The send's track: a thin neutral line, filled to the thumb. */
@Composable
private fun SendTrack(level: Double, modifier: Modifier) {
    Canvas(modifier) {
        val thumb = 7.dp.toPx()
        val track = 4.dp.toPx()
        val mid = size.height / 2
        val x = thumb + level.toFloat() * (size.width - 2 * thumb).coerceAtLeast(0f)
        drawRoundRect(Studio.bg0, Offset(0f, mid - track / 2), Size(size.width, track), CornerRadius(track / 2))
        if (level > 0) drawRoundRect(Studio.text3, Offset(0f, mid - track / 2), Size(x, track), CornerRadius(track / 2))
        drawCircle(if (level > 0) Studio.text1 else Studio.text3, thumb, Offset(x, mid))
    }
}
