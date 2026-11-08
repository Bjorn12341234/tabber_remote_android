package com.tabberspak.app

import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * TR6, as the iPhone's WelcomeUITests: a fresh install, the paste fallback for a camera app that
 * copies the link, and the fix-it cards. On Android the phone's own camera app opens the pairing
 * link, so "Pair again" leads back to the welcome and its camera steps, not to a scanner.
 */
@RunWith(AndroidJUnit4::class)
class WelcomeTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** A computer nobody answers for: port 1 on this phone. */
    private val nowhere = """{"id":"h-nowhere","name":"Nowhere Mac","pin":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","routes":[{"host":"127.0.0.1","port":1}]}"""
    private val nowhereLink = "tabber-remote://pair?v=1&id=h-nowhere&name=Nowhere%20Mac&spki=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&tok=AAAAAAAAAAAAAAAAAAAAAA&hosts=127.0.0.1:1"

    @Test fun aFreshInstallWelcomesAndOffersTheDemo() {
        launchApp().use {
            compose.waitForTag("get-started")
            compose.onNodeWithTag("demo").performScrollTo().performClick()
            compose.waitForWords("connection", "Demo Studio")
            compose.waitForTag("tab-tracks")
        }
    }

    @Test fun aPastedLinkIsCheckedAndAFailedPairingSaysWhy() {
        launchApp().use {
            compose.waitForTag("paste-link").performScrollTo().performClick()
            compose.waitForTag("link-field").performTextInput("https://example.com")
            compose.onNodeWithTag("pair-link-button").performClick()
            compose.waitForTag("not-a-code")
            compose.onNodeWithTag("link-field").performTextReplacement(nowhereLink)
            compose.onNodeWithTag("pair-link-button").performClick()
            compose.waitUntil(20_000) { compose.node("get-started") != null && runCatching { compose.onNodeWithText("Pairing did not work").assertExists() }.isSuccess }
            compose.onNodeWithText("Can't reach Nowhere Mac", substring = true).assertExists()
            compose.onNodeWithText("OK").performClick()
            compose.waitForTag("get-started") // still on the welcome, not paired
            compose.waitForNoTag("tab-tracks")
        }
    }

    @Test fun anUnreachableComputerSaysWhatToCheck() {
        launchApp("known_host" to nowhere).use {
            compose.waitForWords("fix-it-title", "Can't reach Nowhere Mac", timeoutMillis = 15_000)
            compose.waitForTag("fix-it-retry")
            compose.onNodeWithTag("fix-it-pair").performClick()
            compose.waitForTag("get-started") // Pair again goes back to the camera steps
        }
    }

    @Test fun anOlderTabberStudioIsNamed() {
        launchApp("demo_speaks" to "0.9").use {
            compose.waitForWords("fix-it-title", "Update Tabber Studio", timeoutMillis = 10_000)
            compose.onNodeWithTag("fix-it-retry").performClick()
            compose.waitForWords("fix-it-title", "Update Tabber Studio", timeoutMillis = 10_000)
        }
    }

    @Test fun aNewerTabberStudioAsksToUpdateThePhone() {
        launchApp("demo_speaks" to "2.0").use {
            compose.waitForWords("fix-it-title", "Update Tabber Spak", timeoutMillis = 10_000)
        }
    }
}
