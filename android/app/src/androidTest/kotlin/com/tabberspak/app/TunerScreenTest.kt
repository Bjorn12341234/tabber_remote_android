package com.tabberspak.app

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Tabber Tuner against the demo computer, as the iPhone's TunerScreenUITests: in the demo a guitar
 * is tuned string by string, so the dial names notes and says how far off they are, against the
 * chosen track's strings. The demo never opens the microphone.
 */
@RunWith(AndroidJUnit4::class)
class TunerScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** What the dial tells TalkBack: "A2, 24 cents flat". */
    private fun dial(): String = runCatching {
        compose.onNodeWithTag("tuner-dial").fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)
    }.getOrNull() ?: ""

    /** The note the dial names: "A2" from "A2, 24 cents flat". */
    private fun note(): String = dial().substringBefore(",")

    private fun text(tag: String): String = runCatching {
        compose.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text }
    }.getOrNull() ?: ""

    private fun selected(tag: String): Boolean = runCatching {
        compose.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Selected)
    }.getOrNull() == true

    /**
     * Choose a track on the Tracks tab, scrolled to as a thumb would: the list composes only the
     * rows in view, and a take card below it can leave the last tracks out of view.
     */
    private fun choose(track: String) {
        compose.onNodeWithTag("tab-tracks").performClick()
        compose.waitUntil(10_000) {
            runCatching { compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasTestTag("track-$track")) }.isSuccess
        }
        compose.onNodeWithTag("track-$track").performClick()
    }

    @Test fun theDialNamesTheStringAndHowFarOff() {
        launchDemo("screen" to "tuner").use {
            compose.waitForTag("tuner-dial")
            compose.waitUntil(6_000) { dial().contains("in tune") } // a string settles in tune
            val first = note()
            assertTrue("a string of the guitar, not $first", first in listOf("E2", "A2", "D3", "G3", "B3", "E4"))
            compose.waitUntil(6_000) { note() != first } // then the next string
            compose.waitUntil(8_000) { text("tuner-strings").contains("Strings of Guitar") }
        }
    }

    @Test fun anAudioTrackTunesToAStandardGuitar() {
        launchDemo("screen" to "tuner").use {
            compose.waitForTag("tuner-dial")
            choose("Bass")
            compose.waitUntil(8_000) { selected("track-Bass") }
            compose.onNodeWithTag("tab-tuner").performClick()
            compose.waitUntil(8_000) { text("tuner-strings").contains("Strings of Bass") } // the bass's four strings
            choose("Vocals")
            compose.onNodeWithTag("tab-tuner").performClick()
            compose.waitUntil(8_000) { text("tuner-strings").contains("Standard tuning") }
        }
    }
}
