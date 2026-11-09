package com.tabberspak.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.MixerState
import com.tabberspak.remotekit.RoutingSend
import com.tabberspak.remotekit.RoutingSource
import com.tabberspak.remotekit.RoutingState
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Tabber Studio's routing Flow, as its Routing window's Flow tab lays it out
 * (ui/routing_graph_view.py, ui/routing_flow_items.py) and the iPhone's FlowView.swift: the tracks
 * in mixer order in the first column, the buses in columns by how deep they cascade, and the
 * master, the Output, last, centred on the tracks. Routes and sends run from a card's output port
 * to another's input port, Studio's teal; a send's level rides on a pill; the default route to the
 * master is dimmed, and so is a muted card.
 *
 * Wiring by hand, as Studio's Flow does it: drag from a card's output port onto a bus or the
 * Master. On the Master the output goes back to the master; on a bus a track chooses its output or
 * a send there (Studio's plain or Option drag), and a bus moves its output, refused in Studio's
 * words when that would loop. Nothing is gesture-only: press and hold a card for the same as a
 * menu, with its sends to take away, and TalkBack offers them as actions. Each change is one undo
 * step on the computer.
 */
@Composable
fun FlowView(model: AppModel, routing: RoutingState) {
    val layout = remember(routing, model.state.mixer) { FlowLayout(routing, model.state.mixer) }
    // null: fitted to the screen, as Studio's Flow opens fitted to its window.
    var zoom by remember { mutableStateOf<Float?>(null) }
    var pinch by remember { mutableFloatStateOf(1f) }
    val hand = remember { FlowHand() }
    // Only whether a wire is in the hand, and which card it is over, compose the diagram again;
    // the wire itself is redrawn as the finger moves.
    val wiring by remember { derivedStateOf { hand.dragging != null } }
    val hovered by remember(layout) { derivedStateOf { hand.dragging?.let { target(layout, it.location, it.sourceId) } } }
    val haptics = LocalHapticFeedback.current
    Column(Modifier.fillMaxSize().background(Studio.bg0).testTag("flow")) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val fit = min(1f, min((maxWidth.value - 8) / layout.width, (maxHeight.value - 8) / layout.height))
            val scale = min(2f, max(fit, 0.3f) * (zoom ?: 1f) * pinch)
            Box(
                Modifier.fillMaxSize()
                    // Pinch to zoom in, as the wheel zooms Studio's Flow; two fingers only, before the
                    // scrolling sees them. A double tap fits it again.
                    .pointerInput(fit) {
                        awaitEachGesture {
                            awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                            var pinched = false
                            while (true) {
                                val event = awaitPointerEvent(PointerEventPass.Initial)
                                if (event.changes.none { it.pressed }) break
                                if (event.changes.count { it.pressed } >= 2) {
                                    pinched = true
                                    pinch *= event.calculateZoom()
                                    event.changes.forEach { it.consume() }
                                }
                            }
                            if (pinched) {
                                zoom = min(2f / max(fit, 0.3f), max(1f, (zoom ?: 1f) * pinch))
                                pinch = 1f
                            }
                        }
                    }
                    .pointerInput(Unit) { detectTapGestures(onDoubleTap = { zoom = null }) }
                    // A wire in the hand never scrolls the diagram (its port takes the drag, too).
                    .horizontalScroll(rememberScrollState(), enabled = !wiring)
                    .verticalScroll(rememberScrollState(), enabled = !wiring),
            ) {
                Box {
                    Graph(
                        layout, routing, scale, hand, hovered,
                        hold = { node ->
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            hand.hold(node.id)
                        },
                        land = { sourceId, point -> hand.land(model, routing, layout, sourceId, point) },
                        actions = { node -> actions(model, routing, node) },
                    )
                    hand.menuAt?.let { id -> layout.nodes.firstOrNull { it.id == id } }?.let { node -> CardMenuAnchor(model, routing, node, scale, hand) }
                }
            }
        }
        Text(
            "Drag from a teal port to a bus or the Master. Hold a card for its menu.",
            color = Studio.text2, fontSize = 12.sp, lineHeight = 16.sp,
            modifier = Modifier.fillMaxWidth().background(Studio.bg0).padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
    hand.dropped?.let { drop ->
        AlertDialog(
            onDismissRequest = { hand.dropped = null },
            containerColor = Studio.bg2,
            title = { Text("${drop.sourceName} to ${drop.busName}", color = Studio.text1) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (drop.canOutput) {
                        StudioButton(
                            "Output to ${drop.busName}", modifier = Modifier.fillMaxWidth(),
                            onClick = { hand.dropped = null; output(model, routing, drop.sourceId, drop.busId) },
                        )
                    }
                    if (drop.canSend) {
                        StudioButton(
                            "Send to ${drop.busName}", modifier = Modifier.fillMaxWidth(),
                            onClick = { hand.dropped = null; model.addSend(drop.sourceId, drop.busId) },
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { hand.dropped = null }) { Text("Cancel", color = Studio.text1) } },
        )
    }
    hand.refusal?.let { why ->
        AlertDialog(
            onDismissRequest = { hand.refusal = null },
            containerColor = Studio.bg2,
            title = { Text("Not routed", color = Studio.text1) },
            text = { Text(why, color = Studio.text2) },
            confirmButton = { TextButton(onClick = { hand.refusal = null }) { Text("OK", color = Studio.text1) } },
        )
    }
}

/**
 * What the hand is doing in the Flow, as the iPhone's FlowView keeps it: the wire being dragged, a
 * track's wire dropped on a bus and waiting for its choice, why a drop was refused, and the card
 * held for its menu.
 */
@Stable
private class FlowHand {
    /** The wire being dragged out of a card's output port, in the graph's dp. */
    var dragging by mutableStateOf<WireDrag?>(null)

    /** A track's wire dropped on a bus, waiting for its choice: output or send. */
    var dropped by mutableStateOf<WireDrop?>(null)

    /** Why a drop was refused, in Tabber Studio's words. */
    var refusal by mutableStateOf<String?>(null)

    /** The card whose menu is open. */
    var held by mutableStateOf<String?>(null)

    /** The card the menu is drawn at, kept while it closes. */
    var menuAt by mutableStateOf<String?>(null)

    /** Which of the menu's own menus is open in its place, "output" or "send"; null for the menu itself. */
    var submenu by mutableStateOf<String?>(null)

    fun hold(id: String) {
        held = id
        menuAt = id
        submenu = null
    }

    fun close() {
        held = null
    }

    /**
     * A wire let go: on the Master, the output goes back there; on a bus, a bus moves its output
     * (unless it would loop) and a track chooses.
     */
    fun land(model: AppModel, routing: RoutingState, layout: FlowLayout, sourceId: String, point: Offset) {
        val source = routing.source(sourceId) ?: return
        val id = target(layout, point, sourceId) ?: return
        if (id == RoutingState.MASTER) {
            output(model, routing, sourceId, id)
            return
        }
        val bus = routing.source(id) ?: return
        if (source.isBus) {
            val loop = routing.wouldLoop(sourceId, id)
            if (loop != null) refusal = "${bus.name} would loop: ${loop.joinToString(" → ")}." else output(model, routing, sourceId, id)
            return
        }
        val sends = routing.sendsFrom(sourceId).any { it.busId == id }
        val canOutput = source.output != id
        if (!canOutput && sends) return
        dropped = WireDrop(sourceId, source.name, id, bus.name, canOutput, canSend = !sends)
    }
}

/** A wire in the hand: from its source's output port to the finger. */
private data class WireDrag(val sourceId: String, val start: Offset, val location: Offset)

/** A track's wire let go on a bus: Studio's plain drag makes it the output, its Option drag a send; the phone asks which. */
private data class WireDrop(
    val sourceId: String,
    val sourceName: String,
    val busId: String,
    val busName: String,
    val canOutput: Boolean,
    val canSend: Boolean,
)

/** The bus or Master card under a dragged wire's end, never its own. */
private fun target(layout: FlowLayout, point: Offset, sourceId: String): String? =
    layout.nodes.firstOrNull { it.kind != "track" && it.id != sourceId && it.frame.inflate(8f).contains(point) }?.id

private fun output(model: AppModel, routing: RoutingState, sourceId: String, output: String) {
    val source = routing.source(sourceId) ?: return
    model.setOutput(source, output)
}

/** The menu's edits as TalkBack actions, without the dragging. */
private fun actions(model: AppModel, routing: RoutingState, node: FlowLayout.Node): List<CustomAccessibilityAction> {
    val source = routing.source(node.id) ?: return emptyList()
    val list = ArrayList<CustomAccessibilityAction>()
    fun action(label: String, edit: () -> Unit) = list.add(CustomAccessibilityAction(label) { edit(); true })
    if (source.output != RoutingState.MASTER) action("Output to Master") { output(model, routing, source.stripId, RoutingState.MASTER) }
    for (bus in routing.outputsFor(source)) {
        if (source.output == bus.stripId || (source.isBus && routing.wouldLoop(source.stripId, bus.stripId) != null)) continue
        action("Output to ${bus.name}") { output(model, routing, source.stripId, bus.stripId) }
    }
    if (!source.isBus) {
        val sends = routing.sendsFrom(source.stripId)
        for (bus in routing.buses) {
            if (sends.none { it.busId == bus.stripId }) action("Send to ${bus.name}") { model.addSend(source.stripId, bus.stripId) }
        }
        for (send in sends) action("Remove send to ${routing.source(send.busId)?.name ?: "the bus"}") { model.removeSend(send) }
    }
    return list
}

/** The graph at its own size, drawn at [scale]: the wires, the send pills, the cards, then the ports to drag from. */
@Composable
private fun Graph(
    layout: FlowLayout,
    routing: RoutingState,
    scale: Float,
    hand: FlowHand,
    hovered: String?,
    hold: (FlowLayout.Node) -> Unit,
    land: (String, Offset) -> Unit,
    actions: (FlowLayout.Node) -> List<CustomAccessibilityAction>,
) {
    Box(
        Modifier.layout { measurable, _ ->
            val w = layout.width.dp.roundToPx()
            val h = layout.height.dp.roundToPx()
            val placeable = measurable.measure(Constraints.fixed(w, h))
            layout((w * scale).roundToInt(), (h * scale).roundToInt()) {
                placeable.placeWithLayer(0, 0) {
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(0f, 0f)
                }
            }
        },
    ) {
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
            for (wire in layout.wires) {
                val path = Path().apply {
                    moveTo(wire.start.x.dp.toPx(), wire.start.y.dp.toPx())
                    cubicTo(
                        wire.control1.x.dp.toPx(), wire.control1.y.dp.toPx(),
                        wire.control2.x.dp.toPx(), wire.control2.y.dp.toPx(),
                        wire.end.x.dp.toPx(), wire.end.y.dp.toPx(),
                    )
                }
                drawPath(
                    path, Studio.accent.copy(alpha = wire.strength),
                    style = Stroke(width = (if (wire.send == null) 2.2f else 1.8f).dp.toPx(), cap = StrokeCap.Round),
                )
            }
            // The wire in the hand, from its port to the finger.
            hand.dragging?.let { drag ->
                drawLine(
                    Studio.accent, Offset(drag.start.x.dp.toPx(), drag.start.y.dp.toPx()), Offset(drag.location.x.dp.toPx(), drag.location.y.dp.toPx()),
                    strokeWidth = 2.2f.dp.toPx(), cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 5.dp.toPx())),
                )
            }
        }
        for (wire in layout.wires) {
            val send = wire.send ?: continue
            SendPill(send, sendWords(routing, send), wire.middle, if (wire.strength < 1f) 0.6f else 1f)
        }
        for (node in layout.nodes) {
            key(node.id) {
                val edits = remember(routing, node) { actions(node) }
                NodeCard(node, summary(routing, node), node.id == hovered, edits, if (routing.source(node.id) != null) ({ hold(node) }) else null)
            }
        }
        for (node in layout.nodes) {
            if (node.kind != "master") key(node.id) { PortHandle(node, scale, hand, land) }
        }
    }
}

/**
 * Where a wire can be dragged from: the output port, a thumb's width on screen at any zoom, and no
 * taller than a card and its gap. The drag starts at the touch, and the port keeps it: the
 * scrolling under it never sees it move. TalkBack has the card's actions instead.
 */
@Composable
private fun PortHandle(node: FlowLayout.Node, scale: Float, hand: FlowHand, land: (String, Offset) -> Unit) {
    val port = Offset(node.frame.right + 5f, node.frame.center.y)
    val side = Studio.target.value / max(scale, 0.3f)
    val tall = min(side, FlowLayout.NODE_HEIGHT + FlowLayout.ROW_GAP)
    val corner = Offset(port.x - side / 2, port.y - tall / 2)
    val at by rememberUpdatedState(corner)
    val from by rememberUpdatedState(port)
    val letGo by rememberUpdatedState(land)
    Box(
        Modifier.offset { IntOffset(corner.x.dp.roundToPx(), corner.y.dp.roundToPx()) }
            .size(side.dp, tall.dp)
            .pointerInput(node.id) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    down.consume()
                    // The finger in the graph's dp: the port's own corner, as placed, and the touch on it.
                    fun graph(position: Offset) = Offset(at.x.dp.roundToPx() + position.x, at.y.dp.roundToPx() + position.y) / density
                    hand.dragging = WireDrag(node.id, from, graph(down.position))
                    try {
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (change.isConsumed) break // a second finger made it a pinch, or the touch was cancelled
                            change.consume()
                            if (!change.pressed) {
                                hand.dragging = null
                                letGo(node.id, graph(change.position))
                                break
                            }
                            hand.dragging = WireDrag(node.id, from, graph(change.position))
                        }
                    } finally {
                        if (hand.dragging?.sourceId == node.id) hand.dragging = null
                    }
                }
            },
    )
}

/**
 * The held card's menu, at the card as drawn. It sits beside the graph, not in it: a menu is placed
 * by its anchor's size, and in the graph drawn to scale that is the card's size before scaling.
 */
@Composable
private fun CardMenuAnchor(model: AppModel, routing: RoutingState, node: FlowLayout.Node, scale: Float, hand: FlowHand) {
    Box(
        Modifier.offset { IntOffset((node.frame.left * scale).dp.roundToPx(), (node.frame.top * scale).dp.roundToPx()) }
            .size((node.frame.width * scale).dp, (node.frame.height * scale).dp),
    ) {
        DropdownMenu(expanded = hand.held == node.id, onDismissRequest = hand::close, containerColor = Studio.bg2) {
            routing.source(node.id)?.let { source -> CardMenu(model, routing, source, hand) }
        }
    }
}

/**
 * A card's menu, as Studio's Flow keeps every edit in a context menu too: its output, a send to each
 * bus it doesn't send to yet, and each send to take away. Output and Send to open in the menu's
 * place, as the iPhone's menus within a menu do, with a row back.
 */
@Composable
private fun CardMenu(model: AppModel, routing: RoutingState, source: RoutingSource, hand: FlowHand) {
    val outputTitle = "Output: ${routing.outputName(source)}"
    val sends = routing.sendsFrom(source.stripId)
    val open = if (source.isBus) emptyList() else routing.buses.filter { bus -> sends.none { it.busId == bus.stripId } }
    when (hand.submenu) {
        "output" -> {
            MenuBack(outputTitle) { hand.submenu = null }
            MenuChoice("Master", on = source.output == RoutingState.MASTER) { hand.close(); output(model, routing, source.stripId, RoutingState.MASTER) }
            for (bus in routing.outputsFor(source)) {
                val loop = if (source.isBus) routing.wouldLoop(source.stripId, bus.stripId) else null
                if (loop != null) {
                    MenuChoice("${bus.name}, would loop: ${loop.joinToString(" → ")}", on = false, enabled = false) {}
                } else {
                    MenuChoice(bus.name, on = source.output == bus.stripId) { hand.close(); output(model, routing, source.stripId, bus.stripId) }
                }
            }
        }
        "send" -> {
            MenuBack("Send to") { hand.submenu = null }
            for (bus in open) {
                DropdownMenuItem(text = { Text(bus.name, color = Studio.text1) }, onClick = { hand.close(); model.addSend(source.stripId, bus.stripId) })
            }
        }
        else -> {
            MenuOpens(outputTitle) { hand.submenu = "output" }
            if (!source.isBus) {
                if (open.isNotEmpty()) MenuOpens("Send to") { hand.submenu = "send" }
                for (send in sends) {
                    DropdownMenuItem(
                        text = { Text("Remove send to ${routing.source(send.busId)?.name ?: "the bus"}", color = Studio.record) },
                        onClick = { hand.close(); model.removeSend(send) },
                    )
                }
            }
        }
    }
}

/** A row that opens its own menu in this one's place. */
@Composable
private fun MenuOpens(text: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text, color = Studio.text1) }, onClick = onClick,
        trailingIcon = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Studio.text2) },
    )
}

/** The open menu's title, back to the menu it opened from. */
@Composable
private fun MenuBack(text: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text, color = Studio.text2, fontWeight = FontWeight.SemiBold) }, onClick = onClick,
        leadingIcon = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Back", tint = Studio.text2) },
    )
}

/** One of the places a sound can go, checked when it goes there. */
@Composable
private fun MenuChoice(text: String, on: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text, color = if (enabled) Studio.text1 else Studio.text3) }, onClick = onClick, enabled = enabled,
        leadingIcon = { if (on) Icon(Icons.Filled.Check, contentDescription = null, tint = Studio.text1) },
        modifier = Modifier.semantics { selected = on },
    )
}

/** What TalkBack says for a card: where it goes; each send is its pill. */
private fun summary(routing: RoutingState, node: FlowLayout.Node): String {
    val source = routing.source(node.id) ?: return "${node.name}, the output"
    val words = "${node.name}, ${if (source.isBus) "bus" else "track"}, out to ${routing.outputName(source)}"
    return if (node.muted) "$words, muted" else words
}

private fun sendWords(routing: RoutingState, send: RoutingSend): String {
    val from = routing.source(send.stripId)?.name ?: "A track"
    val bus = routing.source(send.busId)?.name ?: "a bus"
    return "$from sends to $bus at ${send.levelLabel}${if (send.preFader) ", pre-fader" else ""}"
}

/** Studio's Flow layout, in dp, as the iPhone's FlowLayout in points. */
class FlowLayout(routing: RoutingState, mixer: MixerState?) {
    data class Node(val id: String, val kind: String, val name: String, val color: String?, val index: Int, val muted: Boolean, val frame: Rect)

    data class Wire(
        val id: String,
        val start: Offset,
        val control1: Offset,
        val control2: Offset,
        val end: Offset,
        val middle: Offset,
        val send: RoutingSend?,
        val strength: Float,
    )

    val nodes = ArrayList<Node>()
    val wires = ArrayList<Wire>()
    var width = 0f
        private set
    var height = 0f
        private set

    init {
        val strips = mixer?.strips ?: emptyList()
        fun strip(id: String) = strips.firstOrNull { it.id == id }

        // Bus columns by cascade depth, as Studio relaxes them, bounded.
        val buses = routing.buses
        val depth = HashMap<String, Int>().apply { buses.forEach { put(it.stripId, 1) } }
        val cascades = buses.mapNotNull { bus -> if (depth.containsKey(bus.output)) bus.stripId to bus.output else null }
        for (round in 0 until max(1, buses.size)) {
            var changed = false
            for ((source, dest) in cascades) {
                val next = (depth[source] ?: 1) + 1
                if (next > (depth[dest] ?: 1) && next <= buses.size) {
                    depth[dest] = next
                    changed = true
                }
            }
            if (!changed) break
        }
        val maxDepth = depth.values.maxOrNull() ?: 0
        fun x(column: Int) = MARGIN + column * (NODE_WIDTH + COLUMN_GAP)

        val columnY = HashMap<Int, Float>()
        fun place(id: String, kind: String, name: String, index: Int, column: Int) {
            val y = columnY[column] ?: MARGIN
            nodes.add(Node(id, kind, name, strip(id)?.color, index, strip(id)?.muted ?: false, Rect(x(column), y, x(column) + NODE_WIDTH, y + NODE_HEIGHT)))
            columnY[column] = y + NODE_HEIGHT + ROW_GAP
        }
        routing.tracks.forEachIndexed { index, track -> place(track.stripId, "track", track.name, index, 0) }
        buses.forEachIndexed { index, bus -> place(bus.stripId, "bus", bus.name, index, depth[bus.stripId] ?: 1) }
        // The master: last column, centred on the tracks.
        val tracksHeight = max(NODE_HEIGHT, (columnY[0] ?: MARGIN) - MARGIN - ROW_GAP)
        val masterY = MARGIN + max(0f, (tracksHeight - NODE_HEIGHT) / 2)
        val masterX = x(maxDepth + 1)
        nodes.add(Node(RoutingState.MASTER, "master", "Master", null, 0, false, Rect(masterX, masterY, masterX + NODE_WIDTH, masterY + NODE_HEIGHT)))

        val frames = nodes.associate { it.id to it.frame }
        fun wire(id: String, from: String, to: String, send: RoutingSend?, strength: Float) {
            val a = frames[from] ?: return
            val b = frames[to] ?: return
            val start = Offset(a.right, a.center.y)
            val end = Offset(b.left, b.center.y)
            val pull = max(30f, (end.x - start.x) / 2)
            wires.add(
                Wire(
                    id, start, Offset(start.x + pull, start.y), Offset(end.x - pull, end.y), end,
                    Offset((start.x + end.x) / 2, (start.y + end.y) / 2), send, strength,
                ),
            )
        }
        for (source in routing.sources) {
            val muted = strip(source.stripId)?.muted ?: false
            val toMaster = source.output == RoutingState.MASTER
            // The default route, dimmed.
            wire("route:${source.stripId}", source.stripId, source.output, null, if (toMaster) 0.35f else if (muted) 0.45f else 1f)
        }
        for (send in routing.sends) {
            val muted = strip(send.stripId)?.muted ?: false
            wire("send:${send.id}", send.stripId, send.busId, send, if (muted) 0.45f else 1f)
        }
        width = (nodes.maxOfOrNull { it.frame.right } ?: 0f) + MARGIN
        height = (nodes.maxOfOrNull { it.frame.bottom } ?: 0f) + MARGIN
    }

    companion object {
        const val NODE_WIDTH = 132f
        const val NODE_HEIGHT = 56f
        const val COLUMN_GAP = 76f // room for a send's pill
        const val ROW_GAP = 14f
        const val MARGIN = 20f
    }
}

/** One card: the name on its colour, as the mixer's strip header, and what it is. */
@Composable
private fun NodeCard(
    node: FlowLayout.Node,
    summary: String,
    /** A dragged wire's end is over this card. */
    targeted: Boolean,
    actions: List<CustomAccessibilityAction>,
    /** Press and hold: the card's menu. The Master has none. */
    hold: (() -> Unit)?,
) {
    val shape = RoundedCornerShape(Studio.radiusCard)
    // Darker than the mixer's chip: at the fitted size the name is small, and small text needs more contrast.
    val header = if (node.kind == "track") Studio.track(node.color, node.index).copy(alpha = 0.4f) else Studio.bg3
    val onHold by rememberUpdatedState(hold)
    Box(
        Modifier.offset { IntOffset(node.frame.left.dp.roundToPx(), node.frame.top.dp.roundToPx()) }
            .size(FlowLayout.NODE_WIDTH.dp, FlowLayout.NODE_HEIGHT.dp)
            .alpha(if (node.muted) 0.45f else 1f)
            // One element for TalkBack (the card says where it goes, and offers the menu's edits);
            // the tag must be set here, as clearing the card's semantics clears a tag set after it too.
            .clearAndSetSemantics {
                contentDescription = summary
                testTag = "flow-${node.name}"
                if (actions.isNotEmpty()) customActions = actions
            }
            .then(
                if (hold == null) {
                    Modifier
                } else {
                    // The hold leaves the touch to the scrolling and the double tap until it is a
                    // hold; from then on the touch is the menu's.
                    Modifier.pointerInput(node.id) {
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            val held = awaitLongPressOrCancellation(down.id) ?: return@awaitEachGesture
                            held.consume()
                            onHold?.invoke()
                            do {
                                val event = awaitPointerEvent()
                                event.changes.forEach { it.consume() }
                            } while (event.changes.any { it.pressed })
                        }
                    }
                },
            ),
    ) {
        Column(
            Modifier.fillMaxSize().clip(shape).background(if (node.kind == "master") Studio.bg3 else Studio.bg2)
                .border(if (targeted) 2.dp else 1.dp, if (targeted) Studio.accent else Studio.edge, shape).padding(6.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // Lines as tall as the words need, so what the card is fits under its name (Material's
            // own lines are 24 sp, and left the caption a sliver).
            Text(
                node.name, color = Studio.text1, fontSize = 15.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Studio.radiusControl)).background(header).padding(horizontal = 8.dp, vertical = 3.dp),
            )
            Text(
                when (node.kind) {
                    "track" -> "Track"
                    "bus" -> "Bus"
                    else -> "Output"
                },
                color = Studio.text2, fontSize = 12.sp, lineHeight = 16.sp, modifier = Modifier.padding(start = 8.dp),
            )
        }
        // Studio's ports: outputs teal, inputs light, ringed in the canvas colour.
        if (node.kind != "track") Port(Studio.text2, Modifier.align(Alignment.CenterStart).offset(x = (-5).dp))
        if (node.kind != "master") Port(Studio.accent, Modifier.align(Alignment.CenterEnd).offset(x = 5.dp))
    }
}

@Composable
private fun Port(fill: Color, modifier: Modifier) {
    Box(modifier.size(10.dp).clip(CircleShape).background(fill).border(2.dp, Studio.bg0, CircleShape))
}

/** A send's level on its wire, as Studio's pill shows it, with Pre-fader. */
@Composable
private fun SendPill(send: RoutingSend, spoken: String, middle: Offset, alpha: Float) {
    Text(
        if (send.preFader) "${send.levelLabel} pre" else send.levelLabel,
        style = Studio.counter(11), color = Studio.text1, maxLines = 1,
        modifier = Modifier
            // Centred on the middle of its wire.
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
                layout(placeable.width, placeable.height) {
                    placeable.place(middle.x.dp.roundToPx() - placeable.width / 2, middle.y.dp.roundToPx() - placeable.height / 2)
                }
            }
            .alpha(alpha)
            .clip(CircleShape).background(Studio.bg3).border(1.dp, Studio.accent.copy(alpha = 0.6f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .semantics { contentDescription = spoken },
    )
}
