package com.tabberspak.app.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tabberspak.app.AppModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * A Studio button that repeats while held, as the iPhone's HoldButton: a tap is one step; held,
 * it steps by itself, faster, then a whole bar at a time, until it is let go or [hold] says there
 * is nowhere further to go.
 */
@Composable
fun HoldButton(
    spoken: String,
    tap: () -> Unit,
    /** One held step; `bars` once it has run a while. False ends the hold. */
    hold: suspend (bars: Boolean) -> Boolean,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    content: @Composable () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val onTap by rememberUpdatedState(tap)
    val onHold by rememberUpdatedState(hold)
    var holding by remember { mutableStateOf(false) }
    Box(
        modifier
            .sizeIn(minHeight = Studio.target, minWidth = Studio.target)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (primary) Studio.accent else Studio.bg3)
            .alpha(if (holding) 0.7f else 1f)
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    holding = true
                    var held = false
                    val steps = scope.launch {
                        delay(400)
                        held = true
                        var count = 0
                        while (isActive && onHold(count >= 12)) {
                            count += 1
                            delay(if (count < 6) 140L else 70L)
                        }
                    }
                    val up = waitForUpOrCancellation()
                    steps.cancel()
                    holding = false
                    if (up != null && !held) onTap()
                }
            }
            .semantics {
                role = Role.Button
                contentDescription = spoken
                onClick { onTap(); true }
            }
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(LocalContentColor provides if (primary) Studio.onAccent else Studio.text1) { content() }
    }
}

/** A choice among several (note values): the chosen one is teal, as in Tabber Studio's toolbar. */
@Composable
fun ChoiceChip(title: String, spoken: String, chosen: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .sizeIn(minHeight = Studio.target)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (chosen) Studio.accent else Studio.bg3)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = spoken; selected = chosen }
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = Studio.counter(15, FontWeight.SemiBold), color = if (chosen) Studio.onAccent else Studio.text1, maxLines = 1)
    }
}

/** A screen the computer cannot serve yet, in plain words. */
@Composable
fun Unavailable(text: String) {
    Text(text, color = Studio.text2, fontSize = 17.sp, modifier = Modifier.fillMaxSize().padding(24.dp).testTag("unavailable"))
}

/**
 * Undo the computer's newest step, named, so nothing else is undone (spec 9): the Tab and Mixer
 * screens' button before the title, as the iPhone's toolbar button.
 */
@Composable
fun UndoButton(model: AppModel, available: Boolean) {
    val step = model.state.undo.undo
    val enabled = step != null && available
    Box(
        Modifier.size(Studio.target).clip(RoundedCornerShape(Studio.radiusControl))
            .clickable(enabled = enabled, role = Role.Button) { model.undo() }
            .semantics { contentDescription = step?.let { "Undo ${it.label}" } ?: "Undo" }
            .testTag("undo"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, tint = if (enabled) Studio.text1 else Studio.text3)
    }
}

/**
 * The first of two layouts whose content fits the width, as SwiftUI's ViewThatFits(in: .horizontal)
 * on the iPhone: side by side when the words fit, stacked when the text is large or the phone
 * narrow, so no word is cut or broken. Each layout emits one root; the wide one is asked for its
 * width (an intrinsic measurement, not a second layout pass).
 */
@Composable
fun FitsOr(modifier: Modifier = Modifier, wide: @Composable () -> Unit, narrow: @Composable () -> Unit) {
    SubcomposeLayout(modifier) { constraints ->
        // The wide layout's need, from a copy with no semantics: only the chosen layout may be
        // composed for real, or TalkBack and the tests would find every control twice.
        val needed = subcompose("measure") { Box(Modifier.clearAndSetSemantics {}) { wide() } }
            .maxOfOrNull { it.maxIntrinsicWidth(constraints.maxHeight) } ?: 0
        val fits = needed <= constraints.maxWidth
        val chosen = subcompose(if (fits) "wide" else "narrow", if (fits) wide else narrow)
        val placeables = chosen.map { it.measure(constraints.copy(minHeight = 0)) }
        layout(placeables.maxOfOrNull { it.width } ?: 0, placeables.maxOfOrNull { it.height } ?: 0) {
            placeables.forEach { it.place(0, 0) }
        }
    }
}

/** The largest text sizes (the iPhone's accessibility sizes): some screens rearrange for them. */
@Composable
fun largeText(): Boolean = LocalDensity.current.fontScale >= 1.5f

/** Text that grows with the phone's text size up to [most] times, as the iPhone caps its tab bar. */
@Composable
fun LimitedScale(most: Float, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, minOf(density.fontScale, most)), content = content)
}

/**
 * One of a few choices as a button that opens them, for the largest text, where a segmented row
 * would break its words: the current choice's name and a mark, then the choices in a menu, the
 * current one checked. Each choice is tagged "[tag]-[name]", as the segments are.
 */
@Composable
fun ChoiceMenu(spoken: String, choices: List<String>, chosen: String, tag: String, modifier: Modifier = Modifier, choose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().sizeIn(minHeight = Studio.target).clip(RoundedCornerShape(Studio.radiusControl)).background(Studio.bg0)
                .clickable(role = Role.Button) { open = true }
                .semantics { contentDescription = "$spoken, $chosen" }
                .padding(horizontal = 14.dp).testTag(tag),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(chosen, color = Studio.text1, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = Studio.text2)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = Studio.bg2) {
            for (choice in choices) {
                DropdownMenuItem(
                    text = { Text(choice, color = Studio.text1) },
                    onClick = { open = false; choose(choice) },
                    leadingIcon = { if (choice == chosen) Icon(Icons.Filled.Check, contentDescription = null, tint = Studio.text1) },
                    modifier = Modifier.semantics { selected = choice == chosen }.testTag("$tag-$choice"),
                )
            }
        }
    }
}
