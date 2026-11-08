package com.tabberspak.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
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
 * master is dimmed, and so is a muted card. Read only: the Routing page changes it.
 */
@Composable
fun FlowView(model: AppModel, routing: RoutingState) {
    val layout = remember(routing, model.state.mixer) { FlowLayout(routing, model.state.mixer) }
    // null: fitted to the screen, as Studio's Flow opens fitted to its window.
    var zoom by remember { mutableStateOf<Float?>(null) }
    var pinch by remember { mutableFloatStateOf(1f) }
    BoxWithConstraints(Modifier.fillMaxSize().background(Studio.bg0).testTag("flow")) {
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
                .horizontalScroll(rememberScrollState())
                .verticalScroll(rememberScrollState()),
        ) {
            Graph(layout, routing, scale)
        }
    }
}

/** The graph at its own size, drawn at [scale]: the wires, the send pills, then the cards on top. */
@Composable
private fun Graph(layout: FlowLayout, routing: RoutingState, scale: Float) {
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
        }
        for (wire in layout.wires) {
            val send = wire.send ?: continue
            SendPill(send, sendWords(routing, send), wire.middle, if (wire.strength < 1f) 0.6f else 1f)
        }
        for (node in layout.nodes) NodeCard(node, summary(routing, node))
    }
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
private fun NodeCard(node: FlowLayout.Node, summary: String) {
    val shape = RoundedCornerShape(Studio.radiusCard)
    // Darker than the mixer's chip: at the fitted size the name is small, and small text needs more contrast.
    val header = if (node.kind == "track") Studio.track(node.color, node.index).copy(alpha = 0.4f) else Studio.bg3
    Box(
        Modifier.offset { IntOffset(node.frame.left.dp.roundToPx(), node.frame.top.dp.roundToPx()) }
            .size(FlowLayout.NODE_WIDTH.dp, FlowLayout.NODE_HEIGHT.dp)
            .alpha(if (node.muted) 0.45f else 1f)
            // One element for TalkBack (the card says where it goes); the tag must be set here, as
            // clearing the card's semantics clears a tag set after it too.
            .clearAndSetSemantics { contentDescription = summary; testTag = "flow-${node.name}" },
    ) {
        Column(
            Modifier.fillMaxSize().clip(shape).background(if (node.kind == "master") Studio.bg3 else Studio.bg2)
                .border(1.dp, Studio.edge, shape).padding(6.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                node.name, color = Studio.text1, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Studio.radiusControl)).background(header).padding(horizontal = 8.dp, vertical = 3.dp),
            )
            Text(
                when (node.kind) {
                    "track" -> "Track"
                    "bus" -> "Bus"
                    else -> "Output"
                },
                color = Studio.text2, fontSize = 12.sp, modifier = Modifier.padding(start = 8.dp),
            )
        }
        // Studio's ports: outputs teal, inputs light, ringed in the canvas colour.
        if (node.kind != "track") Port(Studio.text2, Modifier.align(Alignment.CenterStart).offset(x = (-5).dp))
        if (node.kind != "master") Port(Studio.accent, Modifier.align(Alignment.CenterEnd).offset(x = 5.dp))
    }
}

@Composable
private fun Port(fill: androidx.compose.ui.graphics.Color, modifier: Modifier) {
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
