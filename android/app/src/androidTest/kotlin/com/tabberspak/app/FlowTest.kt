package com.tabberspak.app

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.lerp
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.pinch
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Wiring by hand in the routing Flow, against the demo computer, as the iPhone's FlowUITests
 * (TR43). The owner: "in flow, i dont seem to be able to move by hand the connections manually".
 * As in Studio's Flow: a wire dragged from a card's output port onto a bus makes a track's output
 * or a send there (Studio's plain or Option drag), onto the Master it goes back there, and a bus
 * that would loop is refused in Studio's words. A card's menu takes a send away.
 */
@RunWith(AndroidJUnit4::class)
class FlowTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun openFlow() {
        compose.waitForTag("mixer-page-Flow").performClick()
        compose.waitForTag("flow-Master")
    }

    private fun bounds(card: String) = compose.onNodeWithTag("flow-$card").fetchSemanticsNode().boundsInRoot

    /** Drag a wire from the source card's output port (its right edge) to the target card. */
    private fun wire(source: String, target: String) {
        val from = bounds(source)
        val to = bounds(target)
        compose.onNodeWithTag("flow-$source").performTouchInput {
            val end = to.center - from.topLeft
            down(centerRight)
            for (step in 1..10) moveTo(lerp(centerRight, end, step / 10f))
            up()
        }
    }

    /** Waits until [condition] holds, failing with [why], as the iPhone's assertions say. */
    private fun waitFor(why: String, condition: () -> Boolean) {
        try {
            compose.waitUntil(8_000, condition)
        } catch (timeout: ComposeTimeoutException) {
            throw AssertionError(why, timeout)
        }
    }

    /** Words on screen: a dialog's title, text or button, or a row of a menu. */
    private fun shows(text: String) = compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    /** A send's pill, by what TalkBack says for it. */
    private fun pill(words: String) = compose.onAllNodes(hasContentDescription(words, substring = true)).fetchSemanticsNodes().isNotEmpty()

    /** What TalkBack offers on a card, by name. */
    private fun actions(card: String) = compose.node("flow-$card")?.config?.getOrNull(SemanticsActions.CustomActions)?.map { it.label } ?: emptyList()

    @Test fun aTracksOutputIsWiredToABusAndBackToTheMaster() {
        launchDemo("screen" to "mixer").use {
            openFlow()
            compose.waitForWords("flow-Guitar", "out to Master")
            wire("Guitar", "Reverb")
            waitFor("a track's wire on a bus asks: output or send") { shows("Output to Reverb") }
            compose.onNodeWithText("Output to Reverb").performClick()
            compose.waitForWords("flow-Guitar", "out to Reverb") // the computer confirms the new output
            wire("Guitar", "Master")
            compose.waitForWords("flow-Guitar", "out to Master") // on the Master, the output goes back there
        }
    }

    @Test fun aSendIsWiredByHandAndTheCardsMenuTakesItAway() {
        launchDemo("screen" to "mixer").use {
            openFlow()
            assertTrue("Bass sends nothing yet", !pill("Bass sends to Reverb"))
            wire("Bass", "Reverb")
            waitFor("a track's wire on a bus asks: output or send") { shows("Send to Reverb") }
            compose.onNodeWithText("Send to Reverb").performClick()
            waitFor("the new send's wire and pill, at Studio's -6 dB") { pill("Bass sends to Reverb at -6.0 dB") }
            compose.waitForWords("flow-Bass", "out to Master") // a send leaves the output where it was
            compose.onNodeWithTag("flow-Bass").performTouchInput { longClick() }
            waitFor("holding a card opens its menu") { shows("Remove send to Reverb") }
            compose.onNodeWithText("Remove send to Reverb").performClick()
            waitFor("the send is gone") { !pill("Bass sends to Reverb") }
        }
    }

    @Test fun aBusThatWouldLoopIsRefusedInStudiosWords() {
        launchDemo("screen" to "mixer").use {
            compose.waitForTag("add-bus").performClick()
            compose.waitForTag("bus-name").performTextInput("Delay")
            compose.onNodeWithTag("add-bus-confirm").performClick()
            compose.waitForTag("fader-Delay")
            openFlow()
            compose.waitForTag("flow-Delay")
            wire("Reverb", "Delay")
            compose.waitForWords("flow-Reverb", "out to Delay") // a bus's wire moves its output, no question
            wire("Delay", "Reverb")
            waitFor("a loop is refused") { shows("Not routed") }
            compose.onNodeWithText("Reverb would loop: Delay → Reverb → Delay.").assertExists()
            compose.onNodeWithText("OK").performClick()
            compose.waitForWords("flow-Delay", "out to Master") // and nothing changed
        }
    }

    /**
     * Android's own: zoomed in, the diagram scrolls, but a wire dragged from a port moves only the
     * wire, as the iPhone's Flow turns its scrolling off while a wire is in the hand.
     */
    @Test fun aWireDraggedWhileZoomedInLeavesTheDiagramWhereItIs() {
        launchDemo("screen" to "mixer").use {
            openFlow()
            val fitted = bounds("Guitar")
            compose.onNodeWithTag("flow").performTouchInput {
                val middle = Offset(centerX, height * 0.3f)
                pinch(middle - Offset(20f, 0f), middle - Offset(200f, 0f), middle + Offset(20f, 0f), middle + Offset(200f, 0f))
            }
            waitFor("a pinch zooms in") { bounds("Guitar").width > fitted.width * 1.5f }
            val zoomed = bounds("Guitar")
            compose.onNodeWithTag("flow-Guitar").performTouchInput {
                down(centerRight)
                for (step in 1..10) moveTo(centerRight - Offset(15f * step, 15f * step))
                up()
            }
            compose.waitForIdle()
            assertEquals("the diagram stays where it was", zoomed, bounds("Guitar"))
            compose.waitForWords("flow-Guitar", "out to Master") // let go on nothing, nothing changes
        }
    }

    /** Android's own: TalkBack gets the menu's edits as each card's actions, as VoiceOver does, without the dragging. */
    @Test fun talkBackGetsTheMenusEditsAsTheCardsActions() {
        launchDemo("screen" to "mixer").use {
            openFlow()
            compose.waitForWords("flow-Guitar", "out to Master")
            assertEquals(listOf("Output to Reverb", "Send to Reverb"), actions("Guitar"))
            assertEquals(listOf("Output to Reverb", "Remove send to Reverb"), actions("Vocals"))
            assertEquals(emptyList<String>(), actions("Master"))
            val output = compose.onNodeWithTag("flow-Guitar").fetchSemanticsNode().config[SemanticsActions.CustomActions].first { it.label == "Output to Reverb" }
            compose.runOnUiThread { output.action() }
            compose.waitForWords("flow-Guitar", "out to Reverb") // the computer confirms it
            waitFor("the actions follow the new output") { actions("Guitar") == listOf("Output to Master", "Send to Reverb") }
        }
    }
}
