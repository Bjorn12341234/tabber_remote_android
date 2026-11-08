package com.tabberspak.app.ui

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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
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
            .sizeIn(minHeight = 44.dp, minWidth = 44.dp)
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
            .sizeIn(minHeight = 44.dp)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (chosen) Studio.accent else Studio.bg3)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = spoken; selected = chosen },
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
        Modifier.size(44.dp).clip(RoundedCornerShape(Studio.radiusControl))
            .clickable(enabled = enabled, role = Role.Button) { model.undo() }
            .semantics { contentDescription = step?.let { "Undo ${it.label}" } ?: "Undo" }
            .testTag("undo"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null, tint = if (enabled) Studio.text1 else Studio.text3)
    }
}
