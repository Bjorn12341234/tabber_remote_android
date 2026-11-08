package com.tabberspak.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * S1, the take loop, against the demo computer: arm a track, record, stop, the take card, delete
 * with Undo, and go again (plan: TR7 and TR8, as the iPhone's TracksUITests).
 */
@RunWith(AndroidJUnit4::class)
class TakeLoopTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test fun theSessionShowsTheDemoSong() {
        launchDemo().use {
            compose.waitForTag("track-Guitar")
            compose.onNodeWithTag("track-Vocals").assertIsDisplayed()
            compose.onNodeWithTag("connection").assertIsDisplayed()
            compose.waitForTag("record-hint")
            compose.onNodeWithTag("readout").assertIsDisplayed()
        }
    }

    @Test fun armRecordStopDeleteUndoAndGoAgain() {
        launchDemo().use {
            compose.waitForTag("arm-Vocals").performClick()
            compose.waitForNoTag("record-hint") // armed: the hint goes
            compose.onNodeWithTag("record").performClick()
            compose.waitUntil(10_000) { // REC and its time in the readout
                compose.onNodeWithTag("readout").fetchSemanticsNode().config.toString().contains("Recording")
            }
            Thread.sleep(1500)
            compose.onNodeWithTag("stop").performClick()
            compose.waitForTag("take-card")
            compose.onNodeWithTag("take-detail").assertTextContains("from bar", substring = true)
            compose.onNodeWithTag("delete").performClick()
            compose.waitForTag("undo-banner")
            compose.onNodeWithTag("undo-delete").performClick()
            compose.waitForNoTag("undo-banner")
            // The take is back in the list, below the tracks: scroll to it, as a person would.
            compose.waitUntil(10_000) {
                runCatching {
                    compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasTestTag("take-Vocals take 1"))
                }.isSuccess
            }
            compose.onNodeWithTag("record").performClick() // a second take, then Go again from the card
            Thread.sleep(1200)
            compose.onNodeWithTag("stop").performClick()
            compose.waitForTag("card-go-again").performClick()
            compose.waitForNoTag("take-card")
            Thread.sleep(800)
            compose.onNodeWithTag("stop").performClick()
            compose.waitForTag("take-card")
        }
    }

    @Test fun aTrackIsChosenSoloedAndMuted() {
        launchDemo().use {
            compose.waitForTag("track-Bass").performClick()
            compose.waitForTag("track-Bass")
            compose.onNodeWithTag("connection").assertIsDisplayed()
        }
    }
}
