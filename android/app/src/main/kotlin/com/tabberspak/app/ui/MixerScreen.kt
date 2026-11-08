package com.tabberspak.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.MixerState
import com.tabberspak.remotekit.ScaleMark
import com.tabberspak.remotekit.Strip
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Tabber Studio's mixer, as the iPhone's MixerScreen.swift: a strip for every track, then the buses
 * and the master, each with pan, S and M, a fader on Tabber Studio's scale and its meter. Double-tap
 * a fader for 0 dB, a pan knob for the centre. Routing is the Mixer's other view, as Tabber Studio's
 * Routing panel can be a tab beside its Mixer, and Flow draws it as Studio's Flow tab does.
 */
@Composable
fun MixerScreen(model: AppModel) {
    var page by rememberSaveable { mutableStateOf("Mixer") }
    // The meters, only while the mixer is on screen (plan: TR25).
    DisposableEffect(Unit) {
        model.watchMixerMeters(true)
        onDispose { model.watchMixerMeters(false) }
    }
    ScreenScaffold(
        model, title = if (model.routingAvailable) "" else "Mixer",
        leading = { UndoButton(model, available = model.mixerAvailable) },
    ) {
        Column(Modifier.fillMaxSize()) {
            // Mixer or Routing, under the title and always in view (the owner, 2026-11-08).
            if (model.mixerAvailable && model.isConnected && (model.routingAvailable || model.addBusAvailable)) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (model.routingAvailable) PagePicker(page, Modifier.weight(1f)) { page = it }
                    if (model.addBusAvailable) AddBusButton(model)
                }
            }
            Box(Modifier.weight(1f)) {
                Connected(model) {
                    val routing = model.state.routing
                    val mixer = model.state.mixer
                    when {
                        !model.mixerAvailable -> Unavailable("Update Tabber Studio on ${model.computerName} to use its mixer from this phone.")
                        page == "Routing" && model.routingAvailable -> routing?.let { RoutingView(model, it) }
                        page == "Flow" && model.routingAvailable -> routing?.let { FlowView(model, it) }
                        mixer != null -> Strips(model, mixer)
                    }
                }
            }
        }
    }
}

@Composable
private fun PagePicker(page: String, modifier: Modifier, choose: (String) -> Unit) {
    val pages = listOf("Mixer", "Routing", "Flow")
    SingleChoiceSegmentedButtonRow(modifier.semantics { contentDescription = "View" }.testTag("mixer-page")) {
        pages.forEachIndexed { index, name ->
            SegmentedButton(
                selected = page == name,
                onClick = { choose(name) },
                shape = SegmentedButtonDefaults.itemShape(index, pages.size),
                icon = {},
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = Studio.bgOn, activeContentColor = Studio.text1,
                    inactiveContainerColor = Studio.bg0, inactiveContentColor = Studio.text2,
                    activeBorderColor = Studio.edge, inactiveBorderColor = Studio.edge,
                ),
                modifier = Modifier.testTag("mixer-page-$name"),
            ) { Text(name, fontSize = 13.sp, maxLines = 1) }
        }
    }
}

/** The strips side by side; a bus added from here comes into view. */
@Composable
private fun Strips(model: AppModel, mixer: MixerState) {
    val list = rememberLazyListState()
    LaunchedEffect(model.addedBusId) {
        val added = model.addedBusId ?: return@LaunchedEffect
        val index = mixer.strips.indexOfFirst { it.id == added }
        if (index >= 0) list.animateScrollToItem(index)
    }
    LazyRow(
        state = list,
        modifier = Modifier.fillMaxSize().testTag("strips"),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(mixer.strips, key = { _, strip -> strip.id }) { index, strip ->
            StripView(model, strip, mixer.scale, mixer.unity, index)
        }
    }
}

/**
 * Tabber Studio's mixer "+ Bus" and its New Bus dialog: name the bus, and it joins the mixer and the
 * routing at once (not an undo step, as there).
 */
@Composable
private fun AddBusButton(model: AppModel) {
    var naming by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    GhostButton(
        "+ Bus", onClick = { name = ""; naming = true },
        modifier = Modifier.semantics { contentDescription = "Add Bus. Adds a bus to the mixer on the computer." }.testTag("add-bus"),
        enabled = "add-bus" !in model.pending,
    )
    if (naming) {
        AlertDialog(
            onDismissRequest = { naming = false },
            containerColor = Studio.bg2,
            title = { Text("New Bus", color = Studio.text1) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Bus name:", color = Studio.text2)
                    OutlinedTextField(
                        value = name, onValueChange = { name = it }, singleLine = true,
                        placeholder = { Text("Bus name", color = Studio.text3) },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = Studio.text1, unfocusedTextColor = Studio.text1, cursorColor = Studio.text1,
                            focusedBorderColor = Studio.text2, unfocusedBorderColor = Studio.text3,
                        ),
                        modifier = Modifier.testTag("bus-name"),
                    )
                }
            },
            // Plain words, as Studio's dialog: teal is for what is selected.
            confirmButton = {
                TextButton(
                    onClick = { naming = false; model.addBus(name.trim()) }, enabled = name.isNotBlank(),
                    modifier = Modifier.testTag("add-bus-confirm"),
                ) { Text("Add Bus", color = if (name.isNotBlank()) Studio.text1 else Studio.text3) }
            },
            dismissButton = { TextButton(onClick = { naming = false }) { Text("Cancel", color = Studio.text1) } },
        )
    }
}

/** One channel strip, top to bottom as in Tabber Studio's mixer. */
@Composable
private fun StripView(model: AppModel, strip: Strip, scale: List<ScaleMark>, unity: Double, index: Int) {
    val scope = rememberCoroutineScope()
    var dragVolume by remember { mutableStateOf<Double?>(null) }
    var dragPan by remember { mutableStateOf<Double?>(null) }
    val volume = dragVolume ?: strip.volume
    val pan = dragPan ?: strip.pan
    val tint = if (strip.isBus) Studio.text3 else Studio.track(strip.color, index)
    Column(
        Modifier.width(96.dp).fillMaxHeight().studioCard()
            .alpha(if (model.audible(strip.id) || strip.isMaster || strip.isBus) 1f else 0.55f)
            .padding(8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.fillMaxWidth().heightIn(min = 34.dp).clip(RoundedCornerShape(5.dp))
                .background(if (strip.isMaster) Studio.bg3 else tint.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                strip.name, color = Studio.text1, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp).semantics { heading() },
            )
        }
        if (!strip.isMaster) {
            var panStart by remember { mutableStateOf(0.0) }
            var panMoved by remember { mutableStateOf(Offset.Zero) }
            PanKnob(
                pan, dragPan?.let(::panLabel) ?: strip.panLabel,
                Modifier
                    .pointerInput(strip.id) {
                        detectDragGestures(
                            onDragStart = { panStart = strip.pan; panMoved = Offset.Zero },
                            onDragEnd = { scope.launch { delay(400); dragPan = null } },
                            onDragCancel = { scope.launch { delay(400); dragPan = null } },
                        ) { change, amount ->
                            change.consume()
                            panMoved += amount
                            val next = (panStart + (panMoved.x - panMoved.y) / 120.dp.toPx()).coerceIn(-1.0, 1.0)
                            dragPan = next
                            model.setPan(strip.id, next)
                        }
                    }
                    .pointerInput(strip.id) { detectTapGestures(onDoubleTap = { model.setPan(strip.id, 0.0) }) }
                    .semantics {
                        contentDescription = "Pan ${strip.name}"
                        stateDescription = spokenPan(strip.panLabel)
                        progressBarRangeInfo = ProgressBarRangeInfo(strip.pan.toFloat(), -1f..1f, steps = 19)
                        setProgress { value -> model.setPan(strip.id, (Math.round(value * 10) / 10.0).coerceIn(-1.0, 1.0)); true }
                    }
                    .testTag("pan-${strip.name}"),
            )
            Row {
                LetterButton(
                    "S", strip.soloed, Studio.solo, if (strip.soloed) "Stop hearing ${strip.name} alone" else "Hear ${strip.name} alone",
                    Modifier.testTag("strip-solo-${strip.name}"), pending = "solo-${strip.id}" in model.pending,
                ) { model.solo(strip.id) }
                LetterButton(
                    "M", strip.muted, Studio.mute, if (strip.muted) "Unmute ${strip.name}" else "Mute ${strip.name}",
                    Modifier.testTag("strip-mute-${strip.name}"), pending = "mute-${strip.id}" in model.pending,
                ) { model.mute(strip.id) }
            }
        } else {
            Spacer(Modifier.height(98.dp))
        }
        // The fader, its meter and its level are one control for TalkBack: "Guitar level, 0 decibels".
        Column(
            Modifier.weight(1f).fillMaxWidth()
                .semantics(mergeDescendants = true) {
                    contentDescription = "${strip.name} level"
                    stateDescription = spokenDb(strip.volumeDb)
                    progressBarRangeInfo = ProgressBarRangeInfo(strip.volume.toFloat(), 0f..1f, steps = 49)
                    setProgress { value -> model.setVolume(strip.id, value.toDouble().coerceIn(0.0, 1.0)); true }
                }
                .testTag("fader-${strip.name}"),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            var start by remember { mutableStateOf(0.0) }
            var moved by remember { mutableStateOf(0f) }
            Box(
                Modifier.weight(1f).heightIn(min = 140.dp).fillMaxWidth()
                    .pointerInput(strip.id) {
                        detectVerticalDragGestures(
                            onDragStart = { start = strip.volume; moved = 0f },
                            onDragEnd = { scope.launch { delay(400); dragVolume = null } },
                            onDragCancel = { scope.launch { delay(400); dragVolume = null } },
                        ) { change, amount ->
                            change.consume()
                            moved += amount
                            val next = (start - moved / size.height.coerceAtLeast(1)).coerceIn(0.0, 1.0)
                            dragVolume = next
                            model.setVolume(strip.id, next)
                        }
                    }
                    .pointerInput(strip.id, unity) { detectTapGestures(onDoubleTap = { model.setVolume(strip.id, unity) }) },
            ) {
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally)) {
                    FaderTrack(volume, scale, Modifier.fillMaxHeight())
                    VerticalMeter(model.state.stripMeters[strip.id]?.maxOrNull() ?: 0.0, Modifier.width(6.dp).fillMaxHeight())
                }
            }
            Text(
                if (dragVolume != null) "…" else Format.db(strip.volumeDb),
                style = Studio.counter(13, FontWeight.SemiBold), color = Studio.text1, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().heightIn(min = 26.dp).studioWell(4.dp).padding(vertical = 4.dp),
            )
        }
    }
}

private fun spokenDb(db: Double?): String {
    db ?: return "silent"
    return if (db == 0.0) "0 decibels" else String.format(java.util.Locale.ROOT, "%s%.1f decibels", if (db > 0) "plus " else "minus ", abs(db))
}

private fun spokenPan(label: String): String {
    if (label == "C") return "centre"
    val side = if (label.startsWith("L")) "left" else "right"
    return "${label.drop(1)} $side"
}

/** The pan label while a finger moves the knob, before the computer answers. */
private fun panLabel(pan: Double): String {
    val value = Math.round(64 + pan * (if (pan < 0) 64 else 63)).toInt()
    return when {
        value == 64 -> "C"
        value < 64 -> "L${64 - value}"
        else -> "R${value - 64}"
    }
}

/** Tabber Studio's pan knob: a dial with a pointer, and its L/C/R value, drawn. */
@Composable
private fun PanKnob(pan: Double, label: String, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.size(76.dp, 44.dp)) {
        val r = 15.dp.toPx()
        val centre = Offset(r, size.height / 2)
        drawCircle(Studio.bg3, r, centre)
        drawCircle(Studio.edge, r - 0.5.dp.toPx(), centre, style = Stroke(1.dp.toPx()))
        val angle = Math.toRadians(pan * 135 - 90)
        val inner = Offset(centre.x + (cos(angle) * 4.dp.toPx()).toFloat(), centre.y + (sin(angle) * 4.dp.toPx()).toFloat())
        val outer = Offset(centre.x + (cos(angle) * 11.dp.toPx()).toFloat(), centre.y + (sin(angle) * 11.dp.toPx()).toFloat())
        drawLine(Studio.text1, inner, outer, 2.5.dp.toPx(), StrokeCap.Round)
        val text = measurer.measure(label, Studio.counter(13, FontWeight.SemiBold).copy(color = Studio.text1))
        drawText(text, topLeft = Offset(38.dp.toPx(), size.height / 2 - text.size.height / 2f))
    }
}

/** The fader: Tabber Studio's dB marks, then the groove with its cap, drawn. */
@Composable
private fun FaderTrack(volume: Double, scale: List<ScaleMark>, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    val cap = 18f
    val marks = 22f
    val capWidth = 30f
    val groove = marks + 6 + capWidth / 2
    Canvas(modifier.width((groove + capWidth / 2).dp)) {
        val capPx = cap.dp.toPx()
        val travel = (size.height - capPx).coerceAtLeast(1f)
        val grooveX = groove.dp.toPx()
        for (mark in scale) {
            val y = capPx / 2 + travel * (1 - mark.volume).toFloat()
            val text = measurer.measure(
                if (mark.db == 0.0) "0" else "${mark.db.toInt()}",
                TextStyle(color = Studio.text2, fontSize = 9.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"),
            )
            drawText(text, topLeft = Offset(marks.dp.toPx() - text.size.width, y - text.size.height / 2f))
        }
        drawRoundRect(Studio.bg0, Offset(grooveX - 2.dp.toPx(), 0f), Size(4.dp.toPx(), size.height), CornerRadius(2.dp.toPx()))
        val top = travel * (1 - volume).toFloat()
        val half = capWidth.dp.toPx() / 2
        drawRoundRect(Studio.text2, Offset(grooveX - half, top), Size(half * 2, capPx), CornerRadius(3.dp.toPx()))
        drawRect(Studio.bg0, Offset(grooveX - half, top + capPx / 2 - 0.75.dp.toPx()), Size(half * 2, 1.5.dp.toPx()))
    }
}

/** A strip's meter, upright: green, amber near the top, red at the top, as Studio draws it. */
@Composable
private fun VerticalMeter(level: Double, modifier: Modifier) {
    val fraction = level.coerceIn(0.0, 1.0).toFloat()
    Canvas(modifier.clip(RoundedCornerShape(2.dp))) {
        drawRect(Studio.bg0)
        if (fraction <= 0f) return@Canvas
        val top = size.height * (1 - fraction)
        drawRect(
            Brush.verticalGradient(
                0f to Studio.record, 0.12f to Studio.meterMid, 0.3f to Studio.meterLow, 1f to Studio.meterLow,
                startY = 0f, endY = size.height,
            ),
            Offset(0f, top), Size(size.width, size.height - top),
        )
    }
}
