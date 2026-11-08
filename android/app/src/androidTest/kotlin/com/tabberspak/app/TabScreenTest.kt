package com.tabberspak.app

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Tab screen against the demo computer, as the iPhone's TabScreenUITests: the fretboard and the
 * piano write at the cursor as Tabber Studio's do, Next moves on, Undo takes it back.
 */
@RunWith(AndroidJUnit4::class)
class TabScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** A tap on the fretboard: a fret on a string, measured as the iPhone's (the board starts at fret 0). */
    private fun fret(fret: Int, string: Int) {
        val x = if (fret == 0) 19f else 38f + 6f + (fret - 0.5f) * 58f
        val y = (string - 0.5f) * 34f
        compose.onNodeWithTag("fretboard").performScrollTo().performTouchInput { click(Offset(x.dp.toPx(), y.dp.toPx())) }
    }

    /** TR36 and the owner's song of only audio files: the Tab screen adds a tab track, and writes on it at once. */
    @Test fun aSongOfOnlyAudioGetsATabTrackToWriteOn() {
        launchDemo("demo_only_audio" to true, "screen" to "tab").use {
            compose.waitForWords("choose-words", "This song has no tab tracks yet. Add one to write on it here.")
            compose.onNodeWithTag("add-tab-track").performClick()
            compose.waitForTag("fretboard") // the new track's tab, at once
            compose.waitForWords("screen-title", "Track 1")
            fret(3, string = 2)
            compose.waitForWords("bar-1", "string 2 fret 3") // the fretboard writes on it
        }
    }

    /**
     * TR39 and TR40: a MIDI track chosen while the computer shows Tab waits on Tabber Studio's "MIDI
     * part" card; the phone answers it, so the computer is never left waiting, and then writes on
     * the MIDI tab. Drums offer only standard notation.
     */
    @Test fun theMidiPartCardFromThePhone() {
        launchDemo("screen" to "tab").use {
            compose.waitForTag("tab-tracks")
            compose.show("Tracks")
            compose.reveal("add-track")
            compose.onNodeWithTag("add-track").performClick()
            compose.onNodeWithText("MIDI track").performClick()
            compose.waitSelected("track-MIDI Track 4")
            compose.show("Tab")
            compose.waitForTag("midi-part") // the computer's card, on the phone
            compose.waitForTag("show-notation")
            compose.waitForTag("show-midi-tab").performClick()
            compose.waitForTag("fretboard") // the computer shows MIDI tab, and the phone writes on it
            compose.waitForWords("screen-title", "MIDI Track 4")
            fret(3, string = 2)
            compose.waitForWords("bar-1", "string 2 fret 3") // a fret on the MIDI track's tab
            compose.show("Tracks")
            compose.reveal("track-Drums")
            compose.onNodeWithTag("track-Drums").performClick()
            compose.waitSelected("track-Drums")
            compose.show("Tab")
            compose.waitForTag("show-notation")
            compose.waitForNoTag("show-midi-tab") // drums cannot show MIDI tab
            compose.onNodeWithTag("show-notation").performClick()
            compose.waitForWords("part-shows", "in standard notation")
        }
    }

    @Test fun aFretboardTapWritesAndASecondTakesItOff() {
        launchDemo("screen" to "tab").use {
            compose.waitForWords("bar-1", "beat 1: string 6 fret 0, cursor")
            fret(3, string = 2)
            compose.waitForWords("bar-1", "beat 1: string 2 fret 3, string 6 fret 0") // the note joins the beat
            fret(3, string = 2)
            compose.waitForWords("bar-1", "beat 1: string 6 fret 0, cursor") // the same fret again takes it off
        }
    }

    @Test fun nextValuesAndUndo() {
        launchDemo("screen" to "tab").use {
            compose.waitForTag("next").performClick()
            compose.waitForWords("bar-1", "beat 2: string 4 fret 2, cursor")
            compose.onNodeWithTag("value-16").performClick()
            compose.waitSelected("value-16")
            compose.waitForWords("undo", "Undo Set duration")
            compose.onNodeWithTag("undo").performClick()
            compose.waitUntil(8_000) { compose.words("undo").startsWith("Undo") && !compose.words("undo").contains("Set duration") }
        }
    }

    @Test fun thePianoWritesThePitchOnItsLowestFret() {
        launchDemo("screen" to "tab").use {
            compose.waitForTag("input-Piano").performClick()
            compose.waitForTag("piano").performScrollTo()
            // The piano opens at the guitar's low octave, a key before C2: G2 is the sixth key shown.
            compose.onNodeWithTag("piano").performTouchInput { click(Offset((5.5f * 38f).dp.toPx(), 150.dp.toPx())) }
            compose.waitForWords("bar-1", "beat 1: string 6 fret 3") // G2 lands on the low E string, fret 3
        }
    }

    @Test fun anAudioTrackOffersTheTabTracks() {
        launchDemo("screen" to "tab").use {
            compose.waitForTag("tab-tracks")
            compose.show("Tracks")
            compose.waitForTag("track-Vocals").performClick()
            compose.waitSelected("track-Vocals")
            compose.show("Tab")
            compose.waitForTag("write-Bass").performClick()
            compose.waitForTag("fretboard")
            compose.waitForWords("bar-1", "string 4 fret 0") // the bass's tab, on four strings
        }
    }

    /** The bar the cursor is in, from the staff's bars. */
    private fun cursorBar(): Int? = compose.onAllNodes(tagStarts("bar-")).fetchSemanticsNodes()
        .firstOrNull { it.words().contains("cursor") }
        ?.let { node -> node.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].removePrefix("bar-").toIntOrNull() }

    @Test fun holdingNextFastForwardsAndPreviousGoesBack() {
        launchDemo("screen" to "tab").use {
            compose.waitForWords("bar-1", "cursor")
            compose.onNodeWithTag("next").performTouchInput { down(center) }
            compose.waitUntil(8_000) { (cursorBar() ?: 0) >= 4 } // a held Next goes on by itself, then bar by bar
            compose.onNodeWithTag("next").performTouchInput { up() }
            val reached = cursorBar() ?: 0
            assertTrue("the hold went on to bar $reached", reached >= 4)
            compose.onNodeWithTag("previous").performTouchInput { down(center) }
            compose.waitForWords("bar-1", "beat 1: string 6 fret 0, cursor", timeoutMillis = 10_000) // back to the start
            compose.onNodeWithTag("previous").performTouchInput { up() }
            assertFalse("Previous stops at the first beat", compose.words("bar-1").isEmpty())
            compose.onNodeWithTag("staff").assertIsDisplayed()
        }
    }
}
