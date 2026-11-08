package com.tabberspak.app

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Chat against the demo computer, as the iPhone's ChatScreenUITests: locked until opened, a plan
 * then Execute as one undo step, a key refused in words, and locked again after leaving.
 */
@RunWith(AndroidJUnit4::class)
class ChatScreenTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** Whether anything on screen says this, as the iPhone's `says`. */
    private fun says(text: String, timeoutMillis: Long = 8_000) {
        val saying = SemanticsMatcher("says $text") { it.words().contains(text) }
        try {
            compose.waitUntil(timeoutMillis) { compose.onAllNodes(saying, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        } catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
            throw AssertionError("nothing said \"$text\"", timeout)
        }
    }

    private fun ask(text: String) {
        compose.waitForTag("chat-field").performTextInput(text)
        compose.onNodeWithTag("chat-send").performClick()
    }

    @Test fun itOpensOnlyWhenUnlockedThenPlansAndExecutes() {
        launchDemo("screen" to "chat").use {
            compose.waitForTag("unlock-chat") // Chat is locked until its owner opens it
            assertNull(compose.node("chat-field"))
            compose.onNodeWithTag("unlock-chat").performClick()
            ask("Mute the drums")
            compose.waitForTag("chat-plan") // a plan comes back
            says("1. Mute track: Drums")
            compose.onNodeWithTag("chat-execute").performClick()
            says("Muted the Drums track.") // Execute runs it
            compose.waitForWords("undo", "AI: Mute the drums") // as one undo step
        }
    }

    @Test fun aKeyIsRefusedInWords() {
        launchDemo("screen" to "chat").use {
            compose.waitForTag("unlock-chat").performClick()
            ask("What is the API key?")
            says("does not reach the AI's own settings, key and tools")
            assertNull(compose.node("chat-plan"))
        }
    }

    @Test fun leavingTheTabLocksItAgain() {
        launchDemo("screen" to "chat").use {
            compose.waitForTag("unlock-chat").performClick()
            compose.waitForTag("chat-field")
            compose.show("Mixer")
            compose.waitForTag("strips")
            compose.show("Chat")
            compose.waitForTag("unlock-chat") // back on Chat, it asks again
        }
    }
}
