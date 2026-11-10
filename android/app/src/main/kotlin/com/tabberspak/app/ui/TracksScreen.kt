package com.tabberspak.app.ui

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Icon
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.LinkState
import com.tabberspak.remotekit.NewTrackKind
import com.tabberspak.remotekit.Take
import com.tabberspak.remotekit.Track
import com.tabberspak.remotekit.TrackKind
import com.tabberspak.remotekit.TrainerState

/**
 * The song's tracks, as Tabber Studio's Tracks panel shows them: tap a track to choose it (the Tab
 * screen writes on it), S to hear it alone, M to silence it, ○ to record on it; "+ Add Track" under
 * the last one. Below them, the takes, each one tap from deletion.
 */
@Composable
fun TracksScreen(model: AppModel) {
    ScreenScaffold(model, title = model.state.project.title.ifEmpty { "Tracks" }) {
        Connected(model) {
            val list = rememberLazyListState()
            // The owner: "the arrange and the stuff up top should stay up top even when you scroll
            // down if there is a lot of tracks." At the largest text they would fill the screen,
            // so there they scroll with the tracks, as on the iPhone.
            val pinned = !largeText()
            LaunchedEffect(model.addedTrackId) {
                val added = model.addedTrackId ?: return@LaunchedEffect
                val index = model.state.tracks.indexOfFirst { it.id == added }
                if (index >= 0) list.animateScrollToItem(index + if (pinned) 1 else 2)
            }
            Column(Modifier.fillMaxSize()) {
                if (pinned) Controls(model, Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 12.dp))
                LazyColumn(
                    state = list,
                    modifier = Modifier.weight(1f).padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (!pinned) item { Controls(model, Modifier.padding(top = 4.dp, bottom = 4.dp)) }
                    val showHint = model.isConnected && !model.state.record.recording &&
                        model.state.tracks.isNotEmpty() && model.state.tracks.none { it.armed }
                    item {
                        if (showHint) {
                            Text(
                                "To record, tap ○ on a track, then ● below.", color = Studio.text2, fontSize = 15.sp,
                                modifier = Modifier.padding(bottom = 4.dp).testTag("record-hint"),
                            )
                        }
                    }
                    itemsIndexed(model.state.tracks, key = { _, track -> track.id }) { index, track ->
                        TrackCard(model, track, index)
                    }
                    if (model.addTrackAvailable) item { AddTrackButton(model) }
                    takesSection(model)
                    item { BottomGap() }
                }
            }
        }
    }
}

/** What the computer shows, the toggles for a take, and the trainer while Loop is on. */
@Composable
private fun Controls(model: AppModel, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (model.viewAvailable) ViewButtons(model)
        RecordOptions(model)
        if (model.trainerAvailable && model.state.transport?.loop?.enabled == true) TrainerRow(model)
    }
}

/**
 * The screen's frame: its title, the computer's name at the top right, the take slot at the
 * bottom (not on the Tuner, as on the iPhone). A screen may put a button before the title
 * ([leading], the Tab screen's Undo) and make the title a menu ([titleChoices], the Tab screen's
 * tracks), as the iPhone's title menu.
 */
@Composable
fun ScreenScaffold(
    model: AppModel,
    title: String,
    leading: (@Composable () -> Unit)? = null,
    titleChoices: List<Pair<String, () -> Unit>> = emptyList(),
    takeSlot: Boolean = true,
    content: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(Studio.bg1).statusBarsPadding()) {
        Row(
            Modifier.fillMaxWidth().padding(start = if (leading != null) 4.dp else 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leading?.invoke()
            Box(Modifier.weight(1f)) {
                var choosing by remember { mutableStateOf(false) }
                Row(
                    Modifier.sizeIn(minHeight = Studio.target)
                        .then(if (titleChoices.isEmpty()) Modifier else Modifier.clickable(role = Role.Button) { choosing = true }),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        title, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false).semantics { heading() }.testTag("screen-title"),
                    )
                    if (titleChoices.isNotEmpty()) {
                        Icon(Icons.Filled.ArrowDropDown, contentDescription = "Choose a track", tint = Studio.text2)
                    }
                }
                DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }, containerColor = Studio.bg2) {
                    for ((name, choose) in titleChoices) {
                        DropdownMenuItem(text = { Text(name, color = Studio.text1) }, onClick = { choosing = false; choose() })
                    }
                }
            }
            ComputerChip(model)
        }
        Box(Modifier.weight(1f)) { content() }
        if (takeSlot) TakeSlot(model)
    }
}

/** One track, as a card in Tabber Studio's Tracks panel. */
@Composable
private fun TrackCard(model: AppModel, track: Track, index: Int) {
    val strip = model.strip(track.id)
    val audible = model.audible(track.id)
    val subtitle = if (track.kind == TrackKind.AUDIO) "Audio" else track.instrument ?: "MIDI"
    Row(Modifier.fillMaxWidth().studioCard(selected = track.selected), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).sizeIn(minHeight = 60.dp)
                .clickable(role = Role.Button) { model.select(track) }
                .semantics {
                    contentDescription = buildString {
                        append("${track.name}, ${if (track.armed) "armed for recording" else subtitle}")
                        if (!audible) append(", not heard")
                    }
                    selected = track.selected
                }
                .padding(start = 14.dp, top = 10.dp, bottom = 10.dp).testTag("track-${track.name}"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.5.dp)).background(Studio.track(track.color, index)))
            Text("${index + 1}", style = Studio.counter(13), color = Studio.text2)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(track.name, color = if (audible) Studio.text1 else Studio.text3, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                val level = model.state.meters[track.id]?.maxOrNull()
                if (track.armed && level != null) {
                    LevelMeter(level, Modifier.height(6.dp).widthIn(max = 160.dp).fillMaxWidth().testTag("meter-${track.name}"))
                } else {
                    Text(subtitle, color = Studio.text2, fontSize = 14.sp)
                }
            }
        }
        if (strip != null) {
            LetterButton("S", strip.soloed, Studio.solo, if (strip.soloed) "Stop hearing ${track.name} alone" else "Hear ${track.name} alone",
                Modifier.testTag("solo-${track.name}"), pending = "solo-${track.id}" in model.pending) { model.solo(track.id) }
            LetterButton("M", strip.muted, Studio.mute, if (strip.muted) "Unmute ${track.name}" else "Mute ${track.name}",
                Modifier.testTag("mute-${track.name}"), pending = "mute-${track.id}" in model.pending) { model.mute(track.id) }
        }
        Box(Modifier.testTag("arm-${track.name}")) {
            ArmButton(track.armed, if (track.armed) "Stop recording on ${track.name}" else "Record on ${track.name}",
                pending = "arm-${track.id}" in model.pending) { model.arm(track) }
        }
    }
}

/**
 * Studio's "+ Add Track" and its chooser: a tab, MIDI or audio track, as the computer makes each,
 * and a drum track (Tab with Percussion Track ticked) on a computer that offers drum tab (tab.drum/1).
 */
@Composable
private fun AddTrackButton(model: AppModel) {
    var choosing by remember { mutableStateOf(false) }
    Box {
        GhostButton(
            "+ Add Track", onClick = { choosing = true }, modifier = Modifier.fillMaxWidth().testTag("add-track"),
            // Not during a take: in Tabber Studio a new track clears the record arms.
            enabled = "add-track" !in model.pending && !model.state.record.recording,
        )
        DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }, containerColor = Studio.bg2) {
            val kinds = listOfNotNull(
                "Tab track" to NewTrackKind.TAB,
                ("Drum track" to NewTrackKind.DRUMS).takeIf { model.drumTabAvailable },
                "MIDI track" to NewTrackKind.MIDI,
                "Audio track" to NewTrackKind.AUDIO,
            )
            for ((label, kind) in kinds) {
                DropdownMenuItem(text = { Text(label, color = Studio.text1) }, onClick = { choosing = false; model.addTrack(kind) })
            }
        }
    }
}

/** What Tabber Studio shows on the computer: Arrange, Tab or Piano Roll, and Split beside them. */
@Composable
private fun ViewButtons(model: AppModel) {
    val view = model.state.view
    val editors = listOf("arrange" to "Arrange", "tab" to "Tab", "piano_roll" to "Piano Roll")
    val segments: @Composable (Modifier) -> Unit = { modifier ->
        SingleChoiceSegmentedButtonRow(modifier.semantics { contentDescription = "What the computer shows" }.testTag("view-editor")) {
            editors.forEachIndexed { index, (editor, label) ->
                SegmentedButton(
                    selected = (view?.editor ?: "tab") == editor,
                    onClick = { model.showEditor(editor) },
                    shape = SegmentedButtonDefaults.itemShape(index, editors.size),
                    icon = {},
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = Studio.bgOn, activeContentColor = Studio.text1,
                        inactiveContainerColor = Studio.bg0, inactiveContentColor = Studio.text2,
                        activeBorderColor = Studio.edge, inactiveBorderColor = Studio.edge,
                    ),
                    modifier = Modifier.testTag("view-editor-$label"),
                ) { Text(label, fontSize = 13.sp, maxLines = 2, textAlign = TextAlign.Center) }
            }
        }
    }
    val split: @Composable (Modifier) -> Unit = { modifier ->
        ToggleChip("Split", isOn = view?.split ?: false, spoken = "Split view on the computer", modifier = modifier.testTag("view-split")) { model.toggleSplit() }
    }
    // At the largest text three segments would break their words: the choice is a menu, Split
    // beside it. (Material's segmented row measures itself by its narrowest word, so the text
    // size decides, not the fit.)
    if (largeText()) {
        val names = editors.map { it.second }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            ChoiceMenu(
                "What the computer shows", names, editors.firstOrNull { it.first == (view?.editor ?: "tab") }?.second ?: "Tab",
                "view-editor", Modifier.weight(1f),
            ) { name -> editors.firstOrNull { it.second == name }?.let { model.showEditor(it.first) } }
            split(Modifier)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            segments(Modifier.weight(1f))
            split(Modifier)
        }
    }
}

/** Tabber Studio's transport toggles that matter for a take. */
@Composable
private fun RecordOptions(model: AppModel) {
    val transport = model.state.transport
    val counting = (transport?.countInBars ?: 0) > 0
    val chips: List<@Composable (Modifier) -> Unit> = listOf(
        { modifier -> ToggleChip("Loop", transport?.loop?.enabled ?: false, modifier.testTag("loop"), onClick = model::toggleLoop) },
        { modifier ->
            ToggleChip(
                "Count-in", counting, modifier.testTag("count-in"),
                spoken = if (counting) "Count-in, one bar" else "Count-in", onClick = model::toggleCountIn,
            )
        },
        { modifier -> ToggleChip("Metro", transport?.click ?: false, modifier.testTag("click"), spoken = "Metronome", onClick = model::toggleClick) },
    )
    // Side by side when they fit; stacked at the largest text, so no word breaks (as on the iPhone).
    FitsOr(
        wide = { ChipWell { chips.forEach { it(Modifier.weight(1f)) } } },
        narrow = {
            Column(Modifier.fillMaxWidth().studioWell().padding(3.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                chips.forEach { it(Modifier.fillMaxWidth()) }
            }
        },
    )
}

/**
 * Tabber Studio's Speed Trainer, shown as there only while Loop is on: the Trainer button, the
 * start speed, the step added each time the loop comes round and the target, then the speed now.
 */
@Composable
private fun TrainerRow(model: AppModel) {
    val trainer = model.state.trainer ?: TrainerState()
    val button: @Composable () -> Unit = {
        ToggleChip("Trainer", trainer.enabled, Modifier.testTag("trainer"), spoken = "Speed Trainer", onClick = model::toggleTrainer)
    }
    val speed: @Composable () -> Unit = {
        Text(
            "${trainer.speed}%", style = Studio.counter(15, FontWeight.Bold), color = if (trainer.enabled) Studio.text1 else Studio.text2,
            modifier = Modifier.padding(end = 8.dp).semantics { contentDescription = "Speed now, ${trainer.speed} percent" }.testTag("trainer-speed"),
        )
    }
    val start: @Composable () -> Unit = { TrainerField(model, "start", "Start speed", trainer.start, TrainerState.starts) }
    val step: @Composable () -> Unit = { TrainerField(model, "step", "Faster each loop by", trainer.step, TrainerState.steps) }
    val target: @Composable () -> Unit = { TrainerField(model, "target", "Target speed", trainer.target, TrainerState.targets) }
    val well = Modifier.fillMaxWidth().studioWell().padding(3.dp).testTag("trainer-row")
    // The button and the fields in Studio's order, then the speed now; when they do not fit (the
    // largest text), each field on a line of its own, named, as on the iPhone.
    FitsOr(
        wide = {
            Row(well, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                button()
                start()
                Text("+", color = Studio.text2, fontWeight = FontWeight.SemiBold)
                step()
                Text("→", color = Studio.text2, fontWeight = FontWeight.SemiBold)
                target()
                Spacer(Modifier.weight(1f))
                speed()
            }
        },
        narrow = {
            Column(well, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    button()
                    Spacer(Modifier.weight(1f))
                    speed()
                }
                for ((name, field) in listOf("Start" to start, "Faster each loop by" to step, "Up to" to target)) {
                    Row(Modifier.padding(start = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(name, color = Studio.text2, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        field()
                    }
                }
            }
        },
    )
}

@Composable
private fun TrainerField(model: AppModel, name: String, spoken: String, value: Int, base: List<Int>) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.sizeIn(minHeight = Studio.target).clip(RoundedCornerShape(Studio.radiusControl)).background(Studio.bg3)
                .clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = "$spoken, $value percent" }
                .padding(horizontal = 10.dp).testTag("trainer-$name"),
            contentAlignment = Alignment.Center,
        ) { Text("$value%", style = Studio.counter(15), color = Studio.text1) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = Studio.bg2) {
            for (choice in TrainerState.choices(base, value)) {
                DropdownMenuItem(text = { Text("$choice%", color = Studio.text1) }, onClick = { open = false; model.setTrainer(name, choice) })
            }
        }
    }
}

/** The takes, newest first: each says what it is and deletes with one tap. */
private fun androidx.compose.foundation.lazy.LazyListScope.takesSection(model: AppModel) {
    val takes = model.state.takes
    if (takes.isEmpty()) return
    item {
        Text("Takes", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp,
            modifier = Modifier.padding(top = 8.dp).semantics { heading() })
    }
    items(takes, key = { "take-${it.id}" }) { take -> TakeRow(model, take) }
}

@Composable
private fun TakeRow(model: AppModel, take: Take) {
    val index = model.state.tracks.indexOfFirst { it.id == take.trackId }.coerceAtLeast(0)
    val color = Studio.track(model.state.tracks.firstOrNull { it.id == take.trackId }?.color, index)
    val place = "${Format.length(take.lengthSeconds)} from bar ${take.start.bar}"
    Row(
        Modifier.fillMaxWidth().studioCard().padding(start = 14.dp, end = 8.dp, top = 8.dp, bottom = 8.dp).testTag("take-${take.name}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.5.dp)).background(color))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(take.name, color = if (take.active) Studio.text1 else Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text(if (take.active) place else "$place, not playing", color = Studio.text2, fontSize = 14.sp)
        }
        StudioButton(
            "Delete", onClick = { model.delete(take) }, kind = ButtonKind.DESTRUCTIVE,
            pending = "delete-${take.id}" in model.pending,
            modifier = Modifier.semantics { contentDescription = "Delete ${take.name}" }.testTag("delete-${take.name}"),
        )
    }
}

/** The computer this phone runs, at the top of every screen; tap for the Computer sheet. */
@Composable
fun ComputerChip(model: AppModel) {
    val (color, words) = when (model.state.link) {
        is LinkState.Connected -> Studio.accent to "connected"
        LinkState.Connecting -> Studio.playhead to "connecting"
        LinkState.Reconnecting -> Studio.playhead to "reconnecting"
        else -> Studio.record to "not connected"
    }
    Row(
        Modifier.sizeIn(minHeight = Studio.target).clip(RoundedCornerShape(Studio.radiusControl))
            .clickable(role = Role.Button) { model.showingComputer = true }
            .semantics { contentDescription = "${model.computerName}, $words. Shows the computer, pairing and settings." }
            .padding(horizontal = 8.dp).testTag("connection"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(color))
        Text(model.computerName, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 160.dp))
    }
}

/** A screen's content while the computer can be used; what to do when it can't. */
@Composable
fun Connected(model: AppModel, content: @Composable () -> Unit) {
    val trouble = model.state.trouble
    when {
        trouble != null -> LazyColumn(Modifier.fillMaxSize().padding(16.dp)) { item { FixItCard(model, trouble, model.computerName) } }
        model.state.transport == null -> Column(
            Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator(color = Studio.text2)
            Spacer(Modifier.height(12.dp))
            Text("Connecting to ${model.computerName}", color = Studio.text2, fontSize = 15.sp)
        }
        else -> Box(Modifier.fillMaxSize().alpha(if (model.isConnected) 1f else 0.5f)) {
            content()
            if (!model.isConnected) Box(Modifier.fillMaxSize().clickable(enabled = true) {}) // no taps while the line is down
        }
    }
}

/** The take card after a take, Undo after a delete, or what went wrong, above the transport. */
@Composable
fun TakeSlot(model: AppModel) {
    val take = model.lastTake
    val offer = model.undoOffer
    val problem = model.problem
    Box(Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp)) {
        when {
            take != null -> TakeCard(model, take)
            offer != null -> Banner(offer.text, "Undo", "undo-banner", "undo-delete", model::undoOffered)
            problem != null -> Banner(problem, "OK", "problem-banner", "problem-ok", model::clearProblem, quiet = true)
        }
    }
}

/**
 * After every take: what was recorded, and the three answers. Keep is the default (recording again
 * keeps the take too), so it is the quiet word in the corner. Delete is one tap, with Undo after.
 */
@Composable
private fun TakeCard(model: AppModel, take: Take) {
    Column(Modifier.fillMaxWidth().studioCard().padding(16.dp).testTag("take-card"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(take.name, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                Text("${Format.length(take.lengthSeconds)} from bar ${take.start.bar}", color = Studio.text2, fontSize = 14.sp,
                    modifier = Modifier.testTag("take-detail"))
            }
            StudioButton("Keep", onClick = model::keep, kind = ButtonKind.QUIET, modifier = Modifier.testTag("keep"))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioButton(
                "Delete", onClick = { model.delete(take) }, kind = ButtonKind.DESTRUCTIVE, minHeight = 50.dp,
                modifier = Modifier.weight(1f).semantics { contentDescription = "Delete ${take.name}. You can undo it for five seconds." }.testTag("delete"),
            )
            StudioButton(
                "Go again", onClick = model::goAgain, minHeight = 50.dp,
                modifier = Modifier.weight(1f).semantics { contentDescription = "Go again. Records again from bar ${take.start.bar}." }.testTag("card-go-again"),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(11.dp).clip(CircleShape).background(Studio.record))
                    Text("Go again", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                }
            }
        }
    }
}

@Composable
private fun Banner(text: String, action: String, tag: String, actionTag: String, onAction: () -> Unit, quiet: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().studioCard().padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp).testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, color = Studio.text1, fontSize = 15.sp, modifier = Modifier.weight(1f).testTag("$tag-text"))
        StudioButton(action, onClick = onAction, kind = if (quiet) ButtonKind.QUIET else ButtonKind.NORMAL, modifier = Modifier.testTag(actionTag))
    }
}
