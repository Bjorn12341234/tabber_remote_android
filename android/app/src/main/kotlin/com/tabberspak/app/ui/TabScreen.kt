package com.tabberspak.app.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.DrumMap
import com.tabberspak.remotekit.Json
import com.tabberspak.remotekit.NewTrackKind
import com.tabberspak.remotekit.NoteValue
import com.tabberspak.remotekit.TabBar
import com.tabberspak.remotekit.TabBeat
import com.tabberspak.remotekit.TabState
import com.tabberspak.remotekit.ViewPart
import com.tabberspak.remotekit.jsonObject
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Tabber Studio's Tab view on the phone, as the iPhone's TabScreen.swift: the chosen track's tab
 * around the cursor, the note values, and the fretboard or the piano to write with. A fretboard
 * tap writes that fret at the cursor (tap it again to take it off) and the cursor stays, so more
 * taps make a chord; Next moves on.
 */
@Composable
fun TabScreen(model: AppModel) {
    val tab = model.state.tab
    val title = tab?.let { shown -> model.state.tracks.firstOrNull { it.id == shown.trackId }?.name } ?: "Tab"
    ScreenScaffold(
        model, title,
        leading = { UndoButton(model, available = model.tabAvailable) },
        titleChoices = model.state.tracks.filter { it.hasTab }.map { track -> track.name to { model.select(track) } },
    ) {
        Connected(model) {
            when {
                !model.tabAvailable -> Unavailable("Update Tabber Studio on ${model.computerName} to write tab from this phone.")
                tab != null -> TabEditor(model, tab)
                else -> ChooseTabTrack(model)
            }
        }
    }
}

private fun duration(value: Int, dotted: Boolean, triplet: Boolean): Json =
    jsonObject { put("value", value); put("dotted", dotted); put("triplet", triplet) }

private fun cursor(bar: Int, beat: Int, string: Int): Json =
    jsonObject { put("bar", bar); put("beat", beat); put("string", string) }

@Composable
private fun TabEditor(model: AppModel, tab: TabState) {
    var input by remember { mutableStateOf(model.preference("tabInput") ?: "Fretboard") }
    val value = tab.duration
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 6.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TabStaff(model, tab)
        // Each row side by side when its words fit; at the largest text, in rows of fewer, so a
        // value never reads cut short ("1/1" for 1/16).
        val valueChip: @Composable RowScope.(Int) -> Unit = { choice ->
            ChoiceChip(
                if (choice == 1) "1" else "1/$choice", Format.value(choice), value.value == choice,
                Modifier.weight(1f).testTag("value-$choice"),
            ) { model.tab("tab.set_duration", duration(choice, value.dotted, value.triplet)) }
        }
        FitsOr(
            wide = { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) { NoteValue.values.forEach { valueChip(it) } } },
            narrow = { InRows(NoteValue.values, 3, valueChip) },
        )
        val edits: List<@Composable RowScope.() -> Unit> = listOf(
            {
                EditChip("Dot", Modifier.weight(1f).testTag("dot"), lit = value.dotted, toggles = true, spoken = "Dotted") {
                    model.tab("tab.set_duration", duration(value.value, !value.dotted, value.triplet))
                }
            },
            {
                EditChip("Triplet", Modifier.weight(1f).testTag("triplet"), lit = value.triplet, toggles = true) {
                    model.tab("tab.set_duration", duration(value.value, value.dotted, !value.triplet))
                }
            },
            { EditChip("Rest", Modifier.weight(1f).testTag("rest"), spoken = "Rest, on or off for this beat") { model.tab("tab.rest") } },
            {
                val spoken = if (tab.drum) "Delete the drum on this line" else "Delete the note on this string"
                EditChip("Delete", Modifier.weight(1f).testTag("delete-note"), spoken = spoken) { model.tab("tab.delete") }
            },
        )
        FitsOr(
            wide = { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) { edits.forEach { it() } } },
            narrow = { InRows(edits, 2) { it() } },
        )
        val previous: @Composable RowScope.() -> Unit = {
            HoldButton(
                "Previous beat. Hold to go back fast.",
                tap = { model.tab("tab.move", jsonObject { put("by", -1) }) },
                hold = { bars -> model.fastStep(-1, bars) },
                modifier = Modifier.testTag("previous"),
            ) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = null, modifier = Modifier.width(20.dp)) }
        }
        val next: @Composable RowScope.(Modifier) -> Unit = { modifier ->
            HoldButton(
                "Next beat. Hold to go forward fast.",
                tap = { model.tab("tab.move", jsonObject { put("by", 1) }) },
                hold = { bars -> model.fastStep(1, bars) },
                modifier = modifier.testTag("next"),
                primary = true,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Next", color = LocalContentColor.current, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                }
            }
        }
        val choose: (String) -> Unit = { chosen ->
            input = chosen
            model.setPreference("tabInput", chosen)
        }
        FitsOr(
            Modifier.padding(top = 2.dp),
            wide = {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    previous()
                    if (tab.drum) DrumMapTitle(Modifier.weight(1f)) else InputChoice(input, Modifier.weight(1f), choose)
                    next(Modifier)
                }
            },
            narrow = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (tab.drum) DrumMapTitle(Modifier.fillMaxWidth()) else InputChoice(input, Modifier.fillMaxWidth(), choose)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        previous()
                        next(Modifier.weight(1f))
                    }
                }
            },
        )
        when {
            tab.drum -> DrumMapPad(model, tab)
            input == "Piano" -> Piano(model, tab)
            else -> Fretboard(model, tab)
        }
    }
}

/** Where Fretboard and Piano are on tab: the computer's dock title for a drum track. */
@Composable
private fun DrumMapTitle(modifier: Modifier) {
    Text(
        "Drum Map", color = Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, textAlign = TextAlign.Center,
        modifier = modifier.semantics { heading() }.testTag("drum-map-title"),
    )
}

/**
 * Tabber Studio's Drum Map (ui/fretboard_widget.py DrumGuideCanvas), which it docks where the
 * fretboard is for a drum track: the common kit sounds, GM 35 to 59, by number and name, the
 * cursor beat's drums lit. There one types the number; here a tap writes it on the beat's first
 * free line, as Studio's staff places a drum, and a lit drum comes off again (tab.drum/1), as
 * apple/TabberSpak/TabScreen.swift DrumMapPad.
 */
@Composable
private fun DrumMapPad(model: AppModel, tab: TabState) {
    val lit = tab.cursorBeat?.notes?.map { it.fret }?.toSet() ?: emptySet()
    // Each cell's least width grows with the text size: three a row on a phone, fewer at the largest text.
    val least = 104.dp * LocalDensity.current.fontScale
    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 4.dp).testTag("drum-map")) {
        val columns = max(1, (maxWidth / least).toInt())
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (row in DrumMap.numbers.chunked(columns)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (number in row) DrumCell(number, on = number in lit, Modifier.weight(1f)) {
                        model.tab("tab.put_pitch", jsonObject { put("pitch", number) })
                    }
                    repeat(columns - row.size) { Box(Modifier.weight(1f)) } // the last row keeps the cells' width
                }
            }
        }
    }
}

/** One drum of the Drum Map: its number over its name, lit while the cursor's beat has it. */
@Composable
private fun DrumCell(number: Int, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val name = DrumMap.name(number)
    Column(
        modifier
            .sizeIn(minHeight = 52.dp)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (on) Studio.accent else Studio.bg3)
            .clickable(role = Role.Button, onClickLabel = if (on) "Take it off this beat" else "Write it on this beat", onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = "$number, $name"
                selected = on
            }
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .testTag("drum-$number"),
    ) {
        val colour = if (on) Studio.onAccent else Studio.text1
        Text("$number", color = colour, style = Studio.counter(15, FontWeight.SemiBold))
        Text(name, color = colour, fontSize = 12.sp)
    }
}

/** Items in rows of [size], each row the full width, as the Tab screen's chips at the largest text. */
@Composable
private fun <T> InRows(items: List<T>, size: Int, item: @Composable RowScope.(T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (row in items.chunked(size)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) { row.forEach { item(it) } }
        }
    }
}

/** Write with the fretboard or the piano; the phone remembers which. */
@Composable
private fun InputChoice(input: String, modifier: Modifier, choose: (String) -> Unit) {
    val choices = listOf("Fretboard", "Piano")
    SingleChoiceSegmentedButtonRow(modifier.semantics { contentDescription = "Write with" }.testTag("input")) {
        choices.forEachIndexed { index, choice ->
            SegmentedButton(
                selected = input == choice,
                onClick = { choose(choice) },
                shape = SegmentedButtonDefaults.itemShape(index, choices.size),
                icon = {},
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = Studio.bgOn, activeContentColor = Studio.text1,
                    inactiveContainerColor = Studio.bg0, inactiveContentColor = Studio.text2,
                    activeBorderColor = Studio.edge, inactiveBorderColor = Studio.edge,
                ),
                modifier = Modifier.testTag("input-$choice"),
            ) { Text(choice, fontSize = 13.sp, maxLines = 2, textAlign = TextAlign.Center) }
        }
    }
}

/** A word button in the Tab screen's edit row; teal while its setting is on. */
@Composable
private fun EditChip(title: String, modifier: Modifier, lit: Boolean = false, toggles: Boolean = false, spoken: String = title, onClick: () -> Unit) {
    Box(
        modifier
            .sizeIn(minHeight = Studio.target)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (lit) Studio.accent else Studio.bg3)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = spoken
                if (toggles) selected = lit
            }
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, color = if (lit) Studio.onAccent else Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1)
    }
}

/**
 * When the chosen track has no tab: which tracks do, and "+ Add Tab Track" for a new one, as in a
 * song of only audio (the owner, 2026-11-08). A MIDI track the computer's Tab editor shows gets
 * Tabber Studio's "MIDI part" card first, so the computer never waits on it (TR39).
 */
@Composable
private fun ChooseTabTrack(model: AppModel) {
    val tracks = model.state.tracks
    val tabs = tracks.withIndex().filter { it.value.hasTab }
    val chosen = tracks.firstOrNull { it.selected }
    val part = if (model.partAvailable) model.state.view?.part?.takeIf { chosen?.id == it.trackId } else null
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (part != null && chosen != null) MidiPartCard(model, part, chosen.name)
        Text(
            when {
                tabs.isEmpty() && model.addTrackAvailable -> "This song has no tab tracks yet. Add one to write on it here."
                tabs.isEmpty() -> "This song has no tab tracks yet. Add one in Tabber Studio, then write on it here."
                part != null -> "Tab tracks to write on here:"
                chosen != null -> "${chosen.name} has no tab. Choose a track to write on:"
                else -> "Choose a track to write on:"
            },
            color = Studio.text2, fontSize = 17.sp, modifier = Modifier.testTag("choose-words"),
        )
        for ((index, track) in tabs) {
            Row(
                Modifier.fillMaxWidth().sizeIn(minHeight = 60.dp).studioCard()
                    .clickable(role = Role.Button) { model.select(track) }
                    .padding(14.dp).testTag("write-${track.name}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.5.dp)).background(Studio.track(track.color, index)))
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(track.name, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text(track.instrument ?: "Tab", color = Studio.text2, fontSize = 15.sp)
                }
            }
        }
        if (model.addTrackAvailable) {
            GhostButton(
                "+ Add Tab Track", onClick = { model.addTrack(NewTrackKind.TAB) },
                modifier = Modifier.fillMaxWidth()
                    .semantics { contentDescription = "Add Tab Track. Adds a guitar tab track to the song on the computer, to write on here." }
                    .testTag("add-tab-track"),
                enabled = "add-track" !in model.pending && !model.state.record.recording,
            )
            if (model.drumTabAvailable) {
                GhostButton(
                    "+ Add Drum Track", onClick = { model.addTrack(NewTrackKind.DRUMS) },
                    modifier = Modifier.fillMaxWidth()
                        .semantics { contentDescription = "Add Drum Track. Adds a drum track to the song on the computer, to write drums on here." }
                        .testTag("add-drum-track"),
                    enabled = "add-track" !in model.pending && !model.state.record.recording,
                )
            }
        }
    }
}

/**
 * Tabber Studio's "MIDI part" card for the chosen MIDI track, as the computer's Tab editor shows
 * it: Show standard notation, and for a melodic track Show MIDI tab, pressing the computer's own
 * buttons. Once answered, what the computer shows.
 */
@Composable
private fun MidiPartCard(model: AppModel, part: ViewPart, name: String) {
    val busy = "show-part" in model.pending
    val words = when (part.shows) {
        "midi_tab" -> "The computer shows $name as MIDI tab."
        "notation" -> "The computer shows $name in standard notation."
        else -> "$name is a MIDI part. The computer waits for a choice: how should it show it?"
    }
    Column(
        Modifier.fillMaxWidth().studioCard().padding(14.dp).testTag("midi-part"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("MIDI part", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.semantics { heading() })
        Text(words, color = Studio.text2, fontSize = 15.sp, modifier = Modifier.testTag("part-shows"))
        if (part.shows == "card") {
            StudioButton(
                "Show standard notation", onClick = { model.showPart(part.trackId, "notation") }, kind = ButtonKind.PRIMARY,
                enabled = !busy, modifier = Modifier.testTag("show-notation"),
            )
            if (part.midiTab) {
                StudioButton(
                    "Show MIDI tab", onClick = { model.showPart(part.trackId, "midi_tab") }, enabled = !busy,
                    modifier = Modifier.testTag("show-midi-tab"),
                )
            }
        }
    }
}

// The staff

/** The staff's measures, in dp, as the iPhone's TabStaff: strings 20 apart. */
private object Staff {
    const val GAP = 20f
    const val TOP = 26f
    const val BOTTOM = 14f
    const val LEAD = 14f

    fun height(strings: Int): Float = TOP + GAP * max(1, strings - 1) + BOTTOM

    fun width(beat: TabBeat): Float = max(30f, 40f * beat.duration.quarters.pow(0.6).toFloat())

    fun barWidth(bar: TabBar): Float = LEAD + max(60f, bar.beats.sumOf { width(it).toDouble() }.toFloat()) + 10f
}

/**
 * The tab around the cursor, drawn as Tabber Studio draws it: strings 20 apart, fret numbers on
 * the lines, the cursor as a teal band with a box on its string. Tap a beat on a string to put the
 * cursor there.
 */
@Composable
private fun TabStaff(model: AppModel, tab: TabState) {
    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val height = Staff.height(tab.strings)
    var viewport by remember { mutableIntStateOf(0) }
    var placed by remember { mutableStateOf(false) }
    // The cursor's bar in the middle: at once when the staff appears, then with a short glide.
    LaunchedEffect(tab.cursor, tab.bars, viewport) {
        if (viewport == 0) return@LaunchedEffect
        var x = 0f
        var width = 0f
        for (bar in tab.bars) {
            val w = Staff.barWidth(bar)
            if (bar.bar == tab.cursor.bar) {
                width = w
                break
            }
            x += w
        }
        val target = (with(density) { (x + width / 2).dp.toPx() } - viewport / 2f).roundToInt().coerceIn(0, scroll.maxValue)
        if (placed) scroll.animateScrollTo(target, tween(200, easing = FastOutSlowInEasing)) else scroll.scrollTo(target)
        placed = true
    }
    Row(
        Modifier.fillMaxWidth().height(height.dp)
            .clip(RoundedCornerShape(Studio.radiusCard)).background(Studio.editor)
            .onSizeChanged { viewport = it.width }
            .testTag("staff")
            .horizontalScroll(scroll),
    ) {
        for (bar in tab.bars) key(bar.bar) { BarView(model, tab, bar, height) }
    }
}

@Composable
private fun BarView(model: AppModel, tab: TabState, bar: TabBar, height: Float) {
    val measurer = rememberTextMeasurer()
    val widths = bar.beats.map(Staff::width)
    val strings = max(1, tab.strings)
    val spoken = bar.beats.withIndex().joinToString("; ") { (index, beat) ->
        val notes = if (beat.notes.isEmpty()) "rest" else beat.notes.joinToString(", ") {
            if (tab.drum) "line ${it.string}, ${it.fret} ${DrumMap.name(it.fret)}" else "string ${it.string} fret ${it.fret}"
        }
        val here = if (tab.cursor.bar == bar.bar && tab.cursor.beat == index + 1) ", cursor" else ""
        "beat ${index + 1}: $notes$here"
    }
    Canvas(
        Modifier.width(Staff.barWidth(bar).dp).height(height.dp)
            .pointerInput(bar, strings) {
                detectTapGestures { tap ->
                    val x = tap.x / density
                    val y = tap.y / density
                    var left = Staff.LEAD
                    var beat = max(1, bar.beats.size)
                    for ((index, w) in widths.withIndex()) {
                        if (x < left + w) {
                            beat = index + 1
                            break
                        }
                        left += w
                    }
                    val string = (((y - Staff.TOP) / Staff.GAP).roundToInt() + 1).coerceIn(1, strings)
                    model.tab("tab.set_cursor", cursor(bar.bar, beat, string))
                }
            }
            .semantics {
                contentDescription = "Bar ${bar.bar}"
                stateDescription = spoken
                role = Role.Button
                onClick { model.tab("tab.set_cursor", cursor(bar.bar, 1, 1)); true }
            }
            .testTag("bar-${bar.bar}"),
    ) {
        fun y(string: Int) = (Staff.TOP + (string - 1) * Staff.GAP).dp.toPx()
        for (s in 1..strings) drawLine(Studio.staffLine, Offset(0f, y(s)), Offset(size.width, y(s)), 1.dp.toPx())
        val edge = size.width - 0.75.dp.toPx()
        drawLine(Studio.barLine, Offset(edge, y(1)), Offset(edge, y(strings)), 1.5.dp.toPx())
        drawText(measurer, "${bar.bar}", Offset(4.dp.toPx(), 6.dp.toPx()), Studio.counter(11).copy(color = Studio.text3))
        var x = Staff.LEAD.dp.toPx()
        bar.beats.forEachIndexed { index, beat ->
            val w = widths[index].dp.toPx()
            val centre = x + w / 2
            if (beat.notes.isEmpty()) {
                val mid = (y(1) + y(strings)) / 2
                drawRoundRect(
                    Studio.text3, Offset(centre - 5.dp.toPx(), mid - 1.5.dp.toPx()), Size(10.dp.toPx(), 3.dp.toPx()), CornerRadius(1.dp.toPx()),
                )
            }
            for (note in beat.notes) {
                val label = measurer.measure("${note.fret}", FRET_NUMBER)
                val lw = label.size.width.toFloat()
                val lh = label.size.height.toFloat()
                drawRect(Studio.editor, Offset(centre - lw / 2 - 2.dp.toPx(), y(note.string) - lh / 2), Size(lw + 4.dp.toPx(), lh))
                drawText(label, topLeft = Offset(centre - lw / 2, y(note.string) - lh / 2))
            }
            if (tab.cursor.bar == bar.bar && tab.cursor.beat == index + 1) {
                drawRoundRect(
                    Studio.accent.copy(alpha = 0.16f), Offset(x + 1.dp.toPx(), y(1) - 12.dp.toPx()),
                    Size(w - 2.dp.toPx(), y(strings) - y(1) + 24.dp.toPx()), CornerRadius(3.dp.toPx()),
                )
                drawRoundRect(
                    Studio.accent, Offset(centre - 13.dp.toPx(), y(tab.cursor.string) - 10.dp.toPx()), Size(26.dp.toPx(), 20.dp.toPx()),
                    CornerRadius(3.dp.toPx()), style = Stroke(1.5.dp.toPx()),
                )
            }
            x += w
        }
    }
}

private val FRET_NUMBER = TextStyle(color = Studio.text1, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")

// The fretboard

/** The fretboard's measures, in dp, as the iPhone's: the open strings, the nut, 24 frets 58 wide. */
private object Board {
    const val OPEN = 38f
    const val NUT = 6f
    const val FRET = 58f
    const val GAP = 34f
    const val FRETS = 24
    const val WIDTH = OPEN + NUT + FRET * FRETS

    fun x(fret: Int): Float = if (fret == 0) OPEN / 2 else OPEN + NUT + (fret - 0.5f) * FRET

    fun y(string: Int): Float = (string - 0.5f) * GAP
}

/**
 * Tabber Studio's fretboard: rosewood with nickel frets, inlays at 3, 5, 7, 9, 12, 15, 17, 19, 21
 * and 24, strings thicker toward the bottom, and the cursor beat's notes as teal circles. Tap a fret
 * on a string to write it.
 */
@Composable
private fun Fretboard(model: AppModel, tab: TabState) {
    val measurer = rememberTextMeasurer()
    var spokenFret by remember { mutableIntStateOf(0) }
    val strings = max(1, tab.strings)
    val neck = Board.GAP * tab.strings
    fun stringName(string: Int): String = tab.tuning.getOrNull(string - 1)?.let { Format.noteNames[it.mod(12)] } ?: ""
    fun moveString(by: Int) = model.tab("tab.set_cursor", cursor(tab.cursor.bar, tab.cursor.beat, (tab.cursor.string + by).coerceIn(1, strings)))
    // The semantics belong to the board in view, so they come before the scrolling: after it they
    // would describe the scrolled content, whose overscroll margin reaches over the row above.
    Box(
        Modifier.fillMaxWidth()
            .semantics {
                contentDescription = "Fretboard"
                stateDescription = "String ${tab.cursor.string}, ${stringName(tab.cursor.string)}, fret $spokenFret"
                progressBarRangeInfo = ProgressBarRangeInfo(spokenFret.toFloat(), 0f..Board.FRETS.toFloat(), steps = Board.FRETS - 1)
                setProgress { value -> spokenFret = value.roundToInt().coerceIn(0, Board.FRETS); true }
                onClick(label = "Write fret $spokenFret") {
                    model.tab("tab.put", jsonObject { put("string", tab.cursor.string); put("fret", spokenFret) })
                    true
                }
                customActions = listOf(
                    CustomAccessibilityAction("Higher string") { moveString(-1); true },
                    CustomAccessibilityAction("Lower string") { moveString(1); true },
                )
            }
            .testTag("fretboard")
            .horizontalScroll(rememberScrollState()),
    ) {
        Canvas(
            Modifier.width(Board.WIDTH.dp).height((neck + 22).dp)
                .pointerInput(strings) {
                    detectTapGestures { tap ->
                        val x = tap.x / density
                        val y = tap.y / density
                        if (y >= neck) return@detectTapGestures
                        val string = ((y / Board.GAP).toInt() + 1).coerceIn(1, strings)
                        val fret = if (x < Board.OPEN + Board.NUT) 0 else ((x - Board.OPEN - Board.NUT) / Board.FRET).toInt().plus(1).coerceIn(1, Board.FRETS)
                        model.tab("tab.put", jsonObject { put("string", string); put("fret", fret) })
                    }
                },
        ) { drawFretboard(measurer, tab, strings, neck, ::stringName) }
    }
}

private fun DrawScope.drawFretboard(measurer: TextMeasurer, tab: TabState, strings: Int, neck: Float, stringName: (Int) -> String) {
    fun px(dp: Float) = dp.dp.toPx()
    val left = px(Board.OPEN + Board.NUT)
    val neckPx = px(neck)
    drawRoundRect(
        Brush.verticalGradient(listOf(Studio.woodEdge, Studio.woodCentre, Studio.wood, Studio.woodEdge), startY = 0f, endY = neckPx),
        Offset(left, 0f), Size(size.width - left, neckPx), CornerRadius(px(2f)),
    )
    drawRect(Studio.nut, Offset(px(Board.OPEN), 0f), Size(px(Board.NUT), neckPx))
    for (fret in 1..Board.FRETS) {
        val fx = left + px(fret * Board.FRET)
        drawRect(Studio.fret, Offset(fx - px(0.75f), 0f), Size(px(1.5f), neckPx))
    }
    for (fret in listOf(3, 5, 7, 9, 15, 17, 19, 21)) drawCircle(Studio.inlay, px(5f), Offset(px(Board.x(fret)), neckPx / 2))
    for (fret in listOf(12, 24)) for (fraction in listOf(0.3f, 0.7f)) {
        drawCircle(Studio.inlay, px(5f), Offset(px(Board.x(fret)), neckPx * fraction))
    }
    for (string in 1..strings) {
        val thickness = px(0.8f + 0.3f * (string - 1))
        drawRect(Studio.string, Offset(left - px(Board.NUT), px(Board.y(string)) - thickness / 2), Size(size.width - left + px(Board.NUT), thickness))
    }
    val notes = tab.cursorBeat?.notes ?: emptyList()
    for (string in 1..strings) {
        val centre = Offset(px(Board.x(0)), px(Board.y(string)))
        val open = notes.any { it.string == string && it.fret == 0 }
        val colour = when {
            open -> Studio.onAccent
            string == tab.cursor.string -> Studio.accent
            else -> Studio.text3
        }
        if (open) drawCircle(Studio.openNote, px(12f), centre)
        drawCentred(measurer, stringName(string), centre, Studio.counter(13, FontWeight.SemiBold).copy(color = colour))
        if (string == tab.cursor.string) drawCircle(Studio.accent, px(13f), centre, style = Stroke(px(1.5f)))
    }
    for (note in notes) {
        if (note.fret <= 0) continue
        val centre = Offset(px(Board.x(note.fret)), px(Board.y(note.string)))
        drawCircle(Studio.accent, px(12f), centre)
        drawCentred(measurer, "${note.fret}", centre, TextStyle(color = Studio.onAccent, fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"))
    }
    for (fret in listOf(1, 3, 5, 7, 9, 12, 15, 17, 19, 21, 24)) {
        drawCentred(measurer, "$fret", Offset(px(Board.x(fret)), neckPx + px(12f)), Studio.counter(11).copy(color = Studio.text3))
    }
}

private fun DrawScope.drawCentred(measurer: TextMeasurer, text: String, centre: Offset, style: TextStyle) {
    if (text.isEmpty()) return
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(centre.x - layout.size.width / 2f, centre.y - layout.size.height / 2f))
}

// The piano

/** Tabber Studio's piano's measures: 88 keys, A0 to C8, white keys 38 dp wide. */
private object Keys {
    const val LOWEST = 21
    const val HIGHEST = 108
    const val WHITE = 38f
    const val HEIGHT = 170f
    private val whiteSteps = setOf(0, 2, 4, 5, 7, 9, 11)
    val whites = (LOWEST..HIGHEST).filter { it % 12 in whiteSteps }
    val blacks = (LOWEST..HIGHEST).filter { it % 12 !in whiteSteps }

    fun whiteIndex(pitch: Int): Int = whites.indexOf(pitch).coerceAtLeast(0)

    /** A black key sits on the line between its white neighbours. */
    fun blackCentre(pitch: Int): Float = whiteIndex(pitch + 1) * WHITE

    fun pitch(x: Float, y: Float): Int? {
        val bw = WHITE * 0.58f
        if (y < HEIGHT * 0.6f) blacks.firstOrNull { abs(blackCentre(it) - x) <= bw / 2 }?.let { return it }
        return whites.getOrNull((x / WHITE).toInt())
    }
}

/**
 * Tabber Studio's piano: 88 keys, A0 to C8, C keys named, the cursor beat's pitches lit teal. A
 * key writes its pitch at the cursor on the string that plays it lowest.
 */
@Composable
private fun Piano(model: AppModel, tab: TabState) {
    val measurer = rememberTextMeasurer()
    val scroll = rememberScrollState()
    val screen = LocalDensity.current
    var spokenPitch by remember { mutableIntStateOf(60) }
    val lit = (tab.cursorBeat?.notes ?: emptyList()).mapNotNull { tab.pitch(it.string, it.fret) }.toSet()
    // Open at the instrument's low octave, a key before its C.
    LaunchedEffect(Unit) {
        val low = tab.tuning.minOrNull() ?: 40
        val x = max(0f, Keys.whiteIndex(low - low % 12) * Keys.WHITE - Keys.WHITE)
        scroll.scrollTo(with(screen) { x.dp.toPx() }.roundToInt())
    }
    Box(
        Modifier.fillMaxWidth()
            .semantics {
                contentDescription = "Piano"
                stateDescription = Format.note(spokenPitch)
                progressBarRangeInfo = ProgressBarRangeInfo(spokenPitch.toFloat(), Keys.LOWEST.toFloat()..Keys.HIGHEST.toFloat(), steps = Keys.HIGHEST - Keys.LOWEST - 1)
                setProgress { value -> spokenPitch = value.roundToInt().coerceIn(Keys.LOWEST, Keys.HIGHEST); true }
                onClick(label = "Write ${Format.note(spokenPitch)}") {
                    model.tab("tab.put_pitch", jsonObject { put("pitch", spokenPitch) })
                    true
                }
            }
            .testTag("piano")
            .horizontalScroll(scroll),
    ) {
        Canvas(
            Modifier.width((Keys.whites.size * Keys.WHITE).dp).height(Keys.HEIGHT.dp)
                .pointerInput(Unit) {
                    detectTapGestures { tap ->
                        Keys.pitch(tap.x / density, tap.y / density)?.let { pitch -> model.tab("tab.put_pitch", jsonObject { put("pitch", pitch) }) }
                    }
                },
        ) {
            fun px(dp: Float) = dp.dp.toPx()
            val height = px(Keys.HEIGHT)
            for (pitch in Keys.whites) {
                val topLeft = Offset(px(Keys.whiteIndex(pitch) * Keys.WHITE), 0f)
                val keySize = Size(px(Keys.WHITE - 1), height)
                if (pitch in lit) {
                    drawRoundRect(Studio.accent, topLeft, keySize, CornerRadius(px(2f)))
                } else {
                    drawRoundRect(Brush.verticalGradient(listOf(Studio.keyTop, Studio.keyBottom), 0f, height), topLeft, keySize, CornerRadius(px(2f)))
                }
                drawRoundRect(Studio.keyBorder, topLeft, keySize, CornerRadius(px(2f)), style = Stroke(px(1f)))
                if (pitch % 12 == 0) {
                    drawCentred(
                        measurer, Format.note(pitch), Offset(topLeft.x + keySize.width / 2, height - px(12f)),
                        TextStyle(color = Color(90, 90, 110), fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                    )
                }
            }
            val bw = px(Keys.WHITE * 0.58f)
            val bh = height * 0.6f
            for (pitch in Keys.blacks) {
                val topLeft = Offset(px(Keys.blackCentre(pitch)) - bw / 2, 0f)
                if (pitch in lit) {
                    drawRoundRect(Studio.accent, topLeft, Size(bw, bh), CornerRadius(px(2f)))
                } else {
                    drawRoundRect(Brush.verticalGradient(listOf(Studio.blackTop, Studio.blackBottom), 0f, bh), topLeft, Size(bw, bh), CornerRadius(px(2f)))
                }
            }
        }
    }
}
