package com.tabberspak.app

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode

/** What a control says, as the iPhone's tests read label and value: its description, its state and its text. */
fun SemanticsNode.words(): String {
    val parts = ArrayList<String>()
    config.getOrNull(SemanticsProperties.ContentDescription)?.let(parts::addAll)
    config.getOrNull(SemanticsProperties.StateDescription)?.let(parts::add)
    config.getOrNull(SemanticsProperties.Text)?.let { texts -> texts.mapTo(parts) { it.text } }
    return parts.joinToString(" ")
}

/** The first node with this tag, in the tree TalkBack reads, or else among the merged-away children. */
fun ComposeTestRule.node(tag: String): SemanticsNode? =
    onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().firstOrNull()
        ?: onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()

fun ComposeTestRule.words(tag: String): String = node(tag)?.words() ?: ""

/** Waits until the control's words say this, as the iPhone's `waitFor(id, text)`. */
fun ComposeTestRule.waitForWords(tag: String, text: String, timeoutMillis: Long = 8_000) {
    try {
        waitUntil(timeoutMillis) { words(tag).contains(text) }
    } catch (timeout: ComposeTimeoutException) {
        throw AssertionError("$tag never said \"$text\"; it says \"${words(tag)}\"", timeout)
    }
}

/** Waits until the control is (or is not) the selected one, as the iPhone's `waitSelected`. */
fun ComposeTestRule.waitSelected(tag: String, selected: Boolean = true, timeoutMillis: Long = 8_000) {
    try {
        waitUntil(timeoutMillis) { node(tag)?.config?.getOrNull(SemanticsProperties.Selected) == selected }
    } catch (timeout: ComposeTimeoutException) {
        throw AssertionError("$tag never became ${if (selected) "selected" else "unselected"}", timeout)
    }
}

/** Scrolls the screen's list until the control is in view, as a thumb would (the iPhone's `reveal`). */
fun ComposeTestRule.reveal(tag: String) {
    waitUntil(8_000) { runCatching { onNode(hasScrollToNodeAction()).performScrollToNode(hasTestTag(tag)) }.isSuccess }
}

/** One of the bottom bar's screens. */
fun ComposeTestRule.show(screen: String) {
    onNodeWithTag("tab-${screen.lowercase()}").performClick()
}

/** Every node whose tag starts so. */
fun tagStarts(prefix: String) = SemanticsMatcher("tag starts with $prefix") {
    it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true
}

/** Starts the app on a fresh install with these launch options and no demo (the iPhone's launch arguments). */
fun launchApp(vararg extras: Pair<String, Any>): ActivityScenario<MainActivity> {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val intent = Intent(context, MainActivity::class.java).apply {
        putExtra("reset", true)
        for ((key, value) in extras) when (value) {
            is Boolean -> putExtra(key, value)
            is String -> putExtra(key, value)
        }
    }
    return ActivityScenario.launch(intent)
}
