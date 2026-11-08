package com.tabberspak.app

import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Tracks screen and the transport against the demo computer, as the iPhone's
 * TracksScreenUITests: choose a track, hear one alone, mute, arm, record, and Studio's toggles.
 */
@RunWith(AndroidJUnit4::class)
class TracksScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** Tap a control; one the list has not made yet (below the fold) is scrolled to first, as a thumb would. */
    private fun tap(tag: String) {
        if (compose.node(tag) == null) compose.reveal(tag)
        compose.waitForTag(tag).performClick()
    }

    @Test fun chooseHearAloneAndMute() {
        launchDemo().use {
            compose.waitSelected("track-Guitar")
            tap("track-Bass")
            compose.waitSelected("track-Bass")
            compose.waitSelected("track-Guitar", selected = false)
            tap("solo-Bass")
            compose.waitSelected("solo-Bass")
            compose.waitForWords("track-Guitar", "not heard") // a solo silences the other tracks
            tap("solo-Bass")
            compose.waitSelected("solo-Bass", selected = false)
            tap("mute-Drums")
            compose.waitSelected("mute-Drums")
            compose.waitForWords("track-Drums", "not heard")
        }
    }

    @Test fun theToggles() {
        launchDemo().use {
            for (tag in listOf("loop", "count-in", "click")) {
                tap(tag)
                compose.waitSelected(tag)
                tap(tag)
                compose.waitSelected(tag, selected = false)
            }
        }
    }

    @Test fun armRecordAndStop() {
        launchDemo().use {
            compose.waitForTag("record-hint")
            compose.waitForWords("record", "Record")
            tap("arm-Vocals")
            compose.waitForWords("record", "Record on Vocals")
            tap("record")
            compose.waitForWords("readout", "Recording", timeoutMillis = 10_000)
            Thread.sleep(1500)
            tap("stop")
            compose.waitForTag("take-card")
            compose.waitForNoTag("record-hint") // with a track armed the hint goes
            compose.reveal("take-Vocals take 1") // the take joins the list
        }
    }

    @Test fun recordWithNothingArmedSaysWhatToDo() {
        launchDemo().use {
            tap("record")
            compose.waitForWords("problem-banner-text", "Arm a track first")
        }
    }

    @Test fun playStopAndBackToTheStart() {
        launchDemo().use {
            compose.waitForWords("play", "Play")
            tap("play")
            compose.waitSelected("play")
            compose.waitForWords("play", "Pause") // Play turns into Pause while playing, as in Tabber Studio
            tap("play")
            compose.waitSelected("play", selected = false)
            compose.waitForWords("play", "Play") // and back
            tap("play")
            compose.waitSelected("play")
            tap("stop")
            compose.waitSelected("play", selected = false)
            compose.waitForWords("stop", "Go to the start")
            tap("stop")
            compose.waitForWords("readout", "Bar 1, beat 1")
        }
    }

    @Test fun theComputersViewButtons() {
        launchDemo().use {
            compose.waitSelected("view-editor-Tab") // the demo computer shows Tab
            tap("view-editor-Arrange")
            compose.waitSelected("view-editor-Arrange")
            tap("view-split")
            compose.waitSelected("view-split") // Split is on
            compose.waitSelected("view-editor-Tab") // beside Arrange, the Tab
            tap("view-split")
            compose.waitSelected("view-split", selected = false)
            compose.waitSelected("view-editor-Arrange") // Split off goes back to Arrange
            tap("view-editor-Piano Roll")
            compose.waitSelected("view-editor-Piano Roll")
        }
    }

    /** S6: the Speed Trainer shows only with Loop on, as in Tabber Studio; a field's menu sets it, and Loop off turns it off. */
    @Test fun theSpeedTrainerShowsWithLoop() {
        launchDemo().use {
            compose.waitForTag("loop")
            compose.waitForNoTag("trainer") // no trainer while Loop is off
            tap("loop")
            compose.waitForTag("trainer") // Loop on shows the trainer
            compose.waitForWords("trainer-speed", "100")
            tap("trainer")
            compose.waitSelected("trainer") // the trainer is on
            compose.waitForWords("trainer-speed", "50") // it starts at the start speed, 50% in the demo
            tap("trainer-start")
            compose.waitUntil(8_000) { compose.onAllNodesWithText("70%").fetchSemanticsNodes().isNotEmpty() }
            compose.onAllNodesWithText("70%").onLast().performClick()
            compose.waitForWords("trainer-start", "70")
            compose.waitForWords("trainer-speed", "70") // a changed start starts the ramp again
            tap("loop")
            compose.waitForNoTag("trainer") // Loop off hides the trainer
            tap("loop")
            compose.waitForTag("trainer")
            compose.waitSelected("trainer", selected = false) // and Loop off turned it off
        }
    }

    /**
     * TR36: "+ Add Track" under the last track asks what kind, as Tabber Studio's chooser does. A
     * tab track comes in after the last tab or MIDI track, selected, with Undo for a moment; an
     * audio track goes last, and the computer turns from Tab to Arrange to show it.
     */
    @Test fun addATrackOfEachKind() {
        launchDemo().use {
            tap("add-track")
            compose.waitUntil(8_000) { compose.onAllNodesWithText("Tab track").fetchSemanticsNodes().isNotEmpty() } // the chooser asks what kind
            compose.onNodeWithText("MIDI track").assertExistsCompat()
            compose.onNodeWithText("Audio track").assertExistsCompat()
            compose.onNodeWithText("Tab track").performClick()
            compose.waitSelected("track-Track 4") // the new tab track comes selected
            compose.waitForWords("undo-banner-text", "Track 4 added")
            compose.onNodeWithTag("track-Lead guitar").performScrollTo()
            val added = compose.onNodeWithTag("track-Track 4").fetchSemanticsNode().boundsInRoot.top
            val audio = compose.onNodeWithTag("track-Lead guitar").fetchSemanticsNode().boundsInRoot.top
            assertTrue("before the audio tracks, as the computer lists them", added < audio)
            tap("undo-delete")
            compose.waitForNoTag("track-Track 4") // Undo takes it back
            compose.waitSelected("view-editor-Tab")
            tap("add-track")
            compose.waitUntil(8_000) { compose.onAllNodesWithText("Audio track").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("Audio track").performClick()
            compose.waitUntil(8_000) { runCatching { compose.reveal("track-Audio 3") }.isSuccess }
            compose.waitSelected("view-editor-Arrange") // the computer turns from Tab to Arrange to show the new audio track
        }
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertExistsCompat() = assertExists()
}

/**
 * TR7's gate on a phone, as the iPhone's ComputerSheetUITests: the Computer sheet shows how long
 * the computer took to answer this phone's taps, and starts again for a second run.
 */
@RunWith(AndroidJUnit4::class)
class ComputerSheetTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun openSheet() {
        compose.waitForTag("connection").performClick()
        compose.waitForTag("response-again").performScrollTo()
    }

    @Test fun theSheetMeasuresHowLongTheComputerTakesToAnswer() {
        launchDemo().use {
            compose.waitForWords("connection", "Demo Studio")
            openSheet()
            compose.waitForWords("response-typical", "Not yet") // nothing tapped yet
            compose.waitForWords("response-note", "Tap a control, like Play")
            compose.onNodeWithTag("response-again").assertIsNotEnabled() // nothing to start again
            compose.onNodeWithTag("done").performScrollTo().performClick()
            compose.waitForNoTag("response-again")
            compose.onNodeWithTag("play").performClick()
            compose.waitForWords("play", "Pause")
            openSheet()
            compose.waitForWords("response-typical", " ms") // the tap on Play was timed
            compose.waitForWords("response-p95", " ms")
            compose.waitForWords("response-note", "over 1 tap")
            compose.onNodeWithTag("response-again").performClick()
            compose.waitForWords("response-typical", "Not yet") // Start again forgets the times
        }
    }
}
