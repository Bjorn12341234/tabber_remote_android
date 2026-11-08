package com.tabberspak.app

import android.content.Intent
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry

/** Starts the app on a fresh install in demo mode, as the iPhone's UI tests pass `-reset -demo`. */
fun launchDemo(vararg extras: Pair<String, Any>): ActivityScenario<MainActivity> {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val intent = Intent(context, MainActivity::class.java).apply {
        putExtra("reset", true)
        putExtra("demo", true)
        for ((key, value) in extras) when (value) {
            is Boolean -> putExtra(key, value)
            is String -> putExtra(key, value)
        }
    }
    return ActivityScenario.launch(intent)
}

/** Waits for a node with this tag, as long as the demo computer may take to answer. */
fun ComposeTestRule.waitForTag(tag: String, timeoutMillis: Long = 10_000): SemanticsNodeInteraction {
    waitUntil(timeoutMillis) { onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }
    return onNodeWithTag(tag)
}

/** Waits until no node has this tag. */
fun ComposeTestRule.waitForNoTag(tag: String, timeoutMillis: Long = 10_000) {
    waitUntil(timeoutMillis) { onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isEmpty() }
}
