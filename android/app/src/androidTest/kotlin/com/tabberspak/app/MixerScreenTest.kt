package com.tabberspak.app

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The Mixer against the demo computer, as the iPhone's MixerScreenUITests: S, M, a fader drag and a double tap back to 0 dB. */
@RunWith(AndroidJUnit4::class)
class MixerScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** A strip's control, scrolled into the row first: the row makes only the strips in view. */
    private fun strip(tag: String) = compose.onNodeWithTag("strips").performScrollToNode(hasTestTag(tag)).let { compose.onNodeWithTag(tag) }

    /** TR41: the mixer header's "+ Bus" asks for the bus's name, as Tabber Studio's New Bus does, and the bus joins the mixer at once. */
    @Test fun addBusAsksForItsName() {
        launchDemo("screen" to "mixer").use {
            compose.waitForTag("add-bus").performClick()
            compose.waitForTag("bus-name") // New Bus asks for a name
            compose.onNodeWithText("New Bus").assertExists()
            compose.onNodeWithTag("add-bus-confirm").assertIsNotEnabled() // not without one
            compose.onNodeWithTag("bus-name").performTextInput("Delay")
            compose.onNodeWithTag("add-bus-confirm").assertIsEnabled().performClick()
            compose.waitForTag("fader-Delay") // the bus joins the mixer, and comes into view
        }
    }

    @Test fun soloMuteAndTheFader() {
        launchDemo("screen" to "mixer").use {
            compose.waitForTag("strips")
            strip("strip-solo-Lead guitar").performClick()
            compose.waitSelected("strip-solo-Lead guitar")
            strip("strip-solo-Lead guitar").performClick()
            compose.waitSelected("strip-solo-Lead guitar", selected = false)
            strip("strip-mute-Bass").performClick()
            compose.waitSelected("strip-mute-Bass")

            compose.onNodeWithTag("strips").performScrollToNode(hasTestTag("fader-Guitar"))
            compose.waitForWords("fader-Guitar", "0 decibels")
            compose.onNodeWithTag("fader-Guitar").performTouchInput {
                swipe(Offset(centerX, height * 0.3f), Offset(centerX, height * 0.6f), durationMillis = 300)
            }
            compose.waitForWords("fader-Guitar", "minus") // dragging down lowers the level
            compose.onNodeWithTag("fader-Guitar").performTouchInput { doubleClick(Offset(centerX, height * 0.4f)) }
            compose.waitForWords("fader-Guitar", "0 decibels") // a double tap is 0 dB
        }
    }
}

/**
 * The Mixer's Routing view against the demo computer, as the iPhone's RoutingScreenUITests: move a
 * track's output to a bus and back, add a send, set it to Pre-fader, take it away, and Undo.
 */
@RunWith(AndroidJUnit4::class)
class RoutingScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun open() {
        compose.waitForTag("mixer-page-Routing").performClick()
        compose.waitForTag("route-Vocals")
    }

    /** A control in the routing list, scrolled into view first, as a thumb would. */
    private fun tap(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo().performClick()
    }

    @Test fun anOutputMovesToABusAndBack() {
        launchDemo("screen" to "mixer").use {
            open()
            compose.waitForWords("output-Vocals", "Master")
            tap("output-Vocals")
            compose.waitForTag("choose-output-Reverb").performClick()
            compose.waitForWords("output-Vocals", "Reverb") // the computer confirms the new output
            compose.waitForWords("fed-Reverb", "Output from Vocals")
            tap("output-Vocals")
            compose.waitForTag("choose-output-Master").performClick()
            compose.waitForWords("output-Vocals", "Master")
        }
    }

    @Test fun aSendIsAddedSetAndTakenAwayAndUndoBringsItBack() {
        launchDemo("screen" to "mixer").use {
            open()
            compose.waitForWords("fed-Reverb", "Sends from Lead guitar and Vocals")
            tap("add-send-Guitar")
            compose.onNodeWithText("Send to Reverb").performClick()
            compose.waitForWords("fed-Reverb", "Sends from Guitar, Lead guitar and Vocals") // the new send shows
            compose.waitForWords("send-Guitar-Reverb", "-6.0 decibels") // a new send starts at -6 dB, as in Tabber Studio
            tap("pre-Guitar-Reverb")
            compose.waitSelected("pre-Guitar-Reverb") // Pre-fader is on
            tap("remove-send-Guitar-Reverb")
            compose.waitForWords("fed-Reverb", "Sends from Lead guitar and Vocals") // the send is gone
            compose.waitForWords("undo", "Remove send → Reverb")
            compose.onNodeWithTag("undo").performClick()
            compose.waitForWords("fed-Reverb", "Sends from Guitar, Lead guitar and Vocals") // Undo brings it back
            compose.waitSelected("pre-Guitar-Reverb") // as it was, Pre-fader and all
        }
    }

    /** Flow draws the same routing, read only: each card says where it goes, each send rides its wire. */
    @Test fun flowDrawsTheRouting() {
        launchDemo("screen" to "mixer").use {
            compose.waitForTag("mixer-page-Flow").performClick()
            compose.waitForTag("flow")
            compose.waitForWords("flow-Vocals", "Vocals, track, out to Master")
            compose.waitForWords("flow-Reverb", "Reverb, bus, out to")
            compose.waitForWords("flow-Master", "Master, the output")
            compose.waitUntil(8_000) {
                compose.onAllNodes(hasContentDescription("Vocals sends to Reverb at", substring = true)).fetchSemanticsNodes().isNotEmpty()
            }
        }
    }
}
