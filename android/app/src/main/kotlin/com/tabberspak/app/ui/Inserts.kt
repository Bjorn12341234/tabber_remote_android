package com.tabberspak.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.Insert
import com.tabberspak.remotekit.PluginRow
import com.tabberspak.remotekit.Strip
import kotlinx.coroutines.launch

/**
 * A strip's INSERTS, as Tabber Studio's mixer strip draws them (ui/mixer_dock.py
 * PluginChainWidget) and the iPhone's Inserts.swift: a dot for a plug-in that plays, a hollow one
 * for a bypassed one, then "＋ Plugin". The zone keeps one height on every strip, as Studio's
 * does, so the faders stay level: a long chain shows its first plug-in and "+k more…". Tap a
 * plug-in for Studio's slot menu: Open on the computer, Bypass or Un-bypass, Remove (TR44).
 *
 * [tallest] is the tallest zone's natural height on the mixer, in pixels; [natural] reports this
 * one's, so the mixer can give every strip the tallest (the iPhone's preference key).
 */
@Composable
fun InsertsZone(model: AppModel, strip: Strip, tallest: Int, natural: (Int) -> Unit) {
    var adding by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf<Insert?>(null) }
    var listingAll by remember { mutableStateOf(false) }
    val inserts = strip.inserts
    val shown = if (inserts.size > 2) inserts.take(1) else inserts
    val loading = model.loadingPlugin
    Column(
        Modifier.fillMaxWidth()
            // Its own height, then at least the tallest zone's: the strips' faders start level.
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints.copy(minHeight = 0))
                natural(placeable.height)
                layout(placeable.width, maxOf(placeable.height, tallest).coerceAtMost(constraints.maxHeight)) { placeable.place(0, 0) }
            },
        verticalArrangement = Arrangement.spacedBy(SPACING),
    ) {
        for (insert in shown) {
            InsertRow(
                Modifier.alpha(if ("remove-${insert.id}" in model.pending) 0.4f else 1f)
                    .clickable(role = Role.Button) { chosen = insert }
                    .semantics { contentDescription = spoken(insert, strip) }
                    .testTag("insert-${strip.name}-${insert.name}"),
            ) { Text(slotLabel(insert), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 2) }
        }
        if (inserts.size > 2) {
            InsertRow(
                Modifier.clickable(role = Role.Button) { listingAll = true }
                    .semantics { contentDescription = "All ${inserts.size} plug-ins on ${strip.name}" }
                    .testTag("inserts-more-${strip.name}"),
            ) { Text("+${inserts.size - 1} more…", color = Studio.text2, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 2) }
        }
        if (loading != null && loading.first == strip.id) {
            InsertRow(Modifier.clearAndSetSemantics { contentDescription = "Loading ${loading.second} on the computer" }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    CircularProgressIndicator(color = Studio.text2, strokeWidth = 1.5.dp, modifier = Modifier.size(12.dp))
                    Text("Loading…", color = Studio.text2, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        } else {
            InsertRow(
                Modifier.alpha(if (loading == null) 1f else 0.4f)
                    .clickable(enabled = loading == null, role = Role.Button) { adding = true }
                    .semantics { contentDescription = "Insert a plug-in on ${strip.name}" }
                    .testTag("add-plugin-${strip.name}"),
                dashed = true,
            ) { Text("＋ Plugin", color = Studio.text2, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
        }
    }
    if (adding) InsertPluginSheet(model, strip) { adding = false }
    if (listingAll) {
        ActionSheet("Plug-ins on ${strip.name}", { listingAll = false }) { close ->
            inserts.forEachIndexed { index, insert ->
                SheetAction(String.format(java.util.Locale.ROOT, "%02d  %s%s", index + 1, insert.name, if (insert.bypassed) "  BYP" else "")) {
                    close()
                    chosen = insert
                }
            }
        }
    }
    chosen?.let { insert ->
        ActionSheet(insert.name, { chosen = null }) { close ->
            SheetAction("Open on the computer", "insert-open") { close(); model.openInsert(insert, strip) }
            SheetAction(if (insert.bypassed) "Un-bypass" else "Bypass", "insert-bypass") { close(); model.bypassInsert(insert, strip) }
            SheetAction("Remove", "insert-remove", destructive = true) { close(); model.removeInsert(insert, strip) }
        }
    }
}

private val SPACING = 4.dp

/** Studio's slot, one label (so TalkBack reads it as one): "● Name", or "○ Name" bypassed. */
private fun slotLabel(insert: Insert) = buildAnnotatedString {
    val dot = when {
        insert.autoBypassed -> Studio.record
        insert.bypassed -> Studio.text3
        else -> Studio.accent
    }
    withStyle(SpanStyle(color = dot)) { append(if (insert.bypassed) "○ " else "● ") }
    withStyle(SpanStyle(color = if (insert.bypassed) Studio.text2 else Studio.text1)) { append(insert.name) }
}

private fun spoken(insert: Insert, strip: Strip): String {
    val state = when {
        insert.autoBypassed -> "bypassed by Tabber Studio, it took too long"
        insert.bypassed -> "bypassed"
        else -> "on"
    }
    return "${insert.name} on ${strip.name}, $state"
}

/** One row of the zone: a finger's height (Android's 48 dp), dashed for "＋ Plugin" as the "+ Bus" outline. */
@Composable
private fun InsertRow(modifier: Modifier, dashed: Boolean = false, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(4.dp)
    Box(
        Modifier.fillMaxWidth().heightIn(min = Studio.target).clip(shape)
            .then(if (dashed) Modifier.border(BorderStroke(1.dp, Studio.dashes), shape) else Modifier.background(Studio.bg0.copy(alpha = 0.6f)))
            .then(modifier)
            .padding(horizontal = 6.dp, vertical = 1.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

/** A sheet of choices, as the iPhone's confirmation dialogs: a title, the choices, then Cancel. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActionSheet(title: String, dismiss: () -> Unit, actions: @Composable (close: () -> Unit) -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val close: () -> Unit = { scope.launch { state.hide() }.invokeOnCompletion { dismiss() } }
    ModalBottomSheet(dragHandle = { BottomSheetDefaults.DragHandle(width = Studio.target) }, onDismissRequest = dismiss, sheetState = state, containerColor = Studio.bg2) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp).padding(bottom = 12.dp)) {
            Text(title, color = Studio.text2, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
            actions(close)
            HorizontalDivider(color = Studio.edge, modifier = Modifier.padding(vertical = 4.dp))
            SheetAction("Cancel", "sheet-cancel") { close() }
        }
    }
}

@Composable
private fun SheetAction(text: String, tag: String? = null, destructive: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().sizeIn(minHeight = Studio.target).clip(RoundedCornerShape(Studio.radiusControl))
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.CenterStart,
    ) { Text(text, color = if (destructive) Studio.record else Studio.text1, fontSize = 17.sp) }
}

/**
 * Tabber Studio's Insert Plugin browser, for one strip (ui/plugin_browser_panel.py), as the
 * iPhone's InsertPluginSheet: its Tabber Plugins and Plugins tabs, the format filter, and a search
 * over name, vendor, category, type and format. A greyed row says why it can't go in. Tap a row
 * to insert it at the end of the strip's chain.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InsertPluginSheet(model: AppModel, strip: Strip, dismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val close: () -> Unit = { scope.launch { state.hide() }.invokeOnCompletion { dismiss() } }
    var tab by remember { mutableStateOf("Tabber Plugins") }
    var format by remember { mutableStateOf("All") }
    var search by remember { mutableStateOf("") }
    /** Why the last insert did not go in, in Tabber Studio's words; the browser stays open. */
    var refused by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { model.loadCatalog() }
    val query = search.trim().lowercase()
    val rows = model.catalog.filter { row ->
        row.tabber == (tab == "Tabber Plugins") && (format == "All" || row.format == format.lowercase()) &&
            (query.isEmpty() || listOf(row.name, row.vendor, row.category, row.typeLabel, row.formatLabel).any { it.lowercase().contains(query) })
    }
    ModalBottomSheet(dragHandle = { BottomSheetDefaults.DragHandle(width = Studio.target) }, onDismissRequest = dismiss, sheetState = state, containerColor = Studio.bg1) {
        Column(Modifier.fillMaxSize().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                StudioButton("Cancel", onClick = close, kind = ButtonKind.QUIET, modifier = Modifier.testTag("cancel"))
                Text(
                    "Insert Plugin", color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 17.sp,
                    modifier = Modifier.weight(1f).padding(end = 56.dp).semantics { heading() }.testTag("insert-plugin-title"),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Segments("Plugin source", listOf("Tabber Plugins", "Plugins"), tab, "plugin-source") { tab = it }
                Segments("Plugin format", listOf("All", "VST3", "CLAP"), format, "plugin-format") { format = it }
                OutlinedTextField(
                    value = search, onValueChange = { search = it }, singleLine = true,
                    placeholder = { Text("Search plugins", color = Studio.text3) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = Studio.text1, unfocusedTextColor = Studio.text1, cursorColor = Studio.text1,
                        focusedBorderColor = Studio.text2, unfocusedBorderColor = Studio.text3,
                    ),
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search plugins" }.testTag("plugin-search"),
                )
            }
            LazyColumn(Modifier.weight(1f).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                when {
                    model.catalogLoading && model.catalog.isEmpty() -> item {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 8.dp)) {
                            CircularProgressIndicator(color = Studio.text2, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                            Text("Reading the plug-ins on ${model.computerName}…", color = Studio.text2)
                        }
                    }
                    rows.isEmpty() -> item {
                        Text(
                            when {
                                search.isNotEmpty() -> "No plug-in matches “$search”."
                                tab == "Tabber Plugins" -> "No Tabber plug-ins on ${model.computerName}."
                                else -> "No other plug-ins on ${model.computerName}. Tabber Studio finds them when it scans for plug-ins."
                            },
                            color = Studio.text2, modifier = Modifier.padding(vertical = 8.dp),
                        )
                    }
                }
                items(rows, key = { it.id }) { row ->
                    PluginRowItem(row, enabled = row.available && model.loadingPlugin == null) {
                        refused = null
                        model.insertPlugin(row, strip) { inserted -> if (inserted) close() else refused = model.problem }
                    }
                }
            }
            val loading = model.loadingPlugin
            val notice = refused
            when {
                notice != null && loading == null -> Text(
                    notice, color = Studio.text1, fontSize = 15.sp,
                    modifier = Modifier.fillMaxWidth().padding(16.dp).studioCard().padding(horizontal = 16.dp, vertical = 12.dp).testTag("plugin-refused"),
                )
                loading != null && loading.first == strip.id -> Row(
                    Modifier.fillMaxWidth().padding(16.dp).studioCard().padding(horizontal = 16.dp, vertical = 12.dp)
                        .semantics(mergeDescendants = true) {}.testTag("plugin-loading"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircularProgressIndicator(color = Studio.text2, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                    Text("Loading ${loading.second} on ${model.computerName}…", color = Studio.text1, fontSize = 15.sp)
                }
            }
        }
    }
}

/** The browser's segmented choices; a label takes two lines at the largest text rather than being cut. */
@Composable
private fun Segments(spoken: String, choices: List<String>, chosen: String, tag: String, choose: (String) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().semantics { contentDescription = spoken }.testTag(tag)) {
        choices.forEachIndexed { index, choice ->
            SegmentedButton(
                selected = chosen == choice,
                onClick = { choose(choice) },
                shape = SegmentedButtonDefaults.itemShape(index, choices.size),
                icon = {},
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = Studio.bgOn, activeContentColor = Studio.text1,
                    inactiveContainerColor = Studio.bg0, inactiveContentColor = Studio.text2,
                    activeBorderColor = Studio.edge, inactiveBorderColor = Studio.edge,
                ),
                modifier = Modifier.heightIn(min = Studio.target).testTag("$tag-$choice"),
            ) { Text(choice, fontSize = 13.sp, maxLines = 2, textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
        }
    }
}

/** One row of the browser: the name, its vendor and category (or why it can't go in), then its type and format. */
@Composable
private fun PluginRowItem(row: PluginRow, enabled: Boolean, insert: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().sizeIn(minHeight = Studio.target).clip(RoundedCornerShape(Studio.radiusCard)).background(Studio.bg2)
            .clickable(enabled = enabled, role = Role.Button, onClick = insert)
            .semantics {
                role = Role.Button
                contentDescription = if (row.available) {
                    "${row.name}, ${row.vendor}, ${row.category}, ${row.typeLabel}, ${row.formatLabel}"
                } else {
                    "${row.name}, ${row.reason ?: "Unavailable"}"
                }
            }
            .testTag("plugin-${row.name}")
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.name, color = if (row.available) Studio.text1 else Studio.text3, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(
                if (row.available) "${row.vendor}, ${row.category}" else row.reason ?: "Unavailable",
                color = if (row.available) Studio.text2 else Studio.text3, fontSize = 13.sp,
            )
        }
        Spacer(Modifier.size(8.dp))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.typeLabel, color = Studio.text2, fontSize = 12.sp)
            Text(row.formatLabel, color = Studio.text2, fontSize = 12.sp)
        }
    }
}
