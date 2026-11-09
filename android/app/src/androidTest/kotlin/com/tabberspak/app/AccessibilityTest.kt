package com.tabberspak.app

import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckPreset
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResult.AccessibilityCheckResultType
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityViewCheckResult
import com.google.android.apps.common.testing.accessibility.framework.integrations.espresso.AccessibilityValidator
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Locale

/**
 * TR9 on Android, as the iPhone's AccessibilityUITests: Google's Accessibility Test Framework on
 * every screen against the demo computer (touch targets, contrast, labels, duplicate controls),
 * as Xcode's accessibility audit there. Every finding of a run is listed at its end.
 */
@RunWith(AndroidJUnit4::class)
class AccessibilityTest {
    @get:Rule val compose = createEmptyComposeRule()

    private val findings = ArrayList<String>()

    /** The framework's checks on the whole window, now. Errors are kept for the end. */
    private fun audit(scenario: ActivityScenario<MainActivity>, screen: String) {
        compose.waitForIdle()
        var results: List<AccessibilityViewCheckResult> = emptyList()
        scenario.onActivity { activity ->
            results = AccessibilityValidator()
                .setCheckPreset(AccessibilityCheckPreset.LATEST)
                .setRunChecksFromRootView(true)
                .setThrowExceptionForErrors(false)
                .checkAndReturnResults(activity.window.decorView)
        }
        for (result in results.filter { it.type == AccessibilityCheckResultType.ERROR }) {
            val element = result.element
            val what = listOfNotNull(
                element?.resourceName?.substringAfter(":id/"),
                element?.contentDescription?.toString()?.take(60),
                element?.text?.toString()?.take(60),
                element?.boundsInScreen?.toString(),
            ).joinToString(" | ")
            findings.add("$screen: ${result.accessibilityHierarchyCheck.simpleName}: ${result.getMessage(Locale.ENGLISH)} [$what]")
        }
    }

    private fun report() {
        assertTrue("${findings.size} findings:\n" + findings.joinToString("\n"), findings.isEmpty())
    }

    private fun tap(tag: String) {
        if (compose.node(tag) == null) compose.reveal(tag)
        compose.waitForTag(tag).performClick()
    }

    @Test fun welcome() {
        launchApp().use { scenario ->
            compose.waitForTag("get-started")
            audit(scenario, "Welcome")
            compose.onNodeWithTag("get-started").performClick()
            // Searching, or a computer found already (another test's may still be advertised).
            compose.waitUntil(10_000) { compose.node("searching") != null || compose.node("found-computer") != null }
            audit(scenario, "Find my computer")
            report()
        }
    }

    /** A song of only audio: the Tab screen's "+ Add Tab Track" (TR36). */
    @Test fun aSongOfOnlyAudio() {
        launchDemo("demo_only_audio" to true, "screen" to "tab").use { scenario ->
            compose.waitForTag("add-tab-track")
            audit(scenario, "Tab, no tab tracks")
            report()
        }
    }

    /** The Tab screen with Tabber Studio's "MIDI part" card (TR39). */
    @Test fun theMidiPartCard() {
        launchDemo().use { scenario ->
            tap("track-Drums")
            compose.waitSelected("track-Drums")
            compose.show("Tab")
            compose.waitForTag("midi-part")
            audit(scenario, "Tab, a MIDI part")
            report()
        }
    }

    @Test fun everyScreen() {
        launchDemo().use { scenario ->
            compose.waitForWords("connection", "Demo Studio")
            audit(scenario, "Tracks")
            tap("loop") // Loop on shows the Speed Trainer
            tap("trainer")
            compose.waitSelected("trainer")
            audit(scenario, "Tracks with the trainer")
            tap("loop")
            tap("arm-Vocals")
            tap("record")
            compose.waitForWords("readout", "Recording", timeoutMillis = 12_000)
            Thread.sleep(1200)
            tap("record")
            compose.waitForTag("take-card")
            audit(scenario, "Take card")
            tap("keep")
            compose.show("Tab")
            compose.waitForTag("fretboard")
            audit(scenario, "Tab")
            tap("input-Piano")
            compose.waitForTag("piano")
            audit(scenario, "Piano")
            compose.show("Mixer")
            compose.waitForTag("fader-Guitar")
            audit(scenario, "Mixer")
            tap("mixer-page-Routing")
            compose.waitForTag("route-Vocals")
            audit(scenario, "Routing")
            tap("mixer-page-Flow")
            compose.waitForTag("flow-Master")
            audit(scenario, "Flow")
            tap("mixer-page-Mixer")
            compose.show("Tuner")
            compose.waitForTag("tuner-dial")
            audit(scenario, "Tuner")
            compose.show("Chat")
            compose.waitForTag("unlock-chat")
            audit(scenario, "Chat locked")
            tap("unlock-chat")
            compose.waitForTag("chat-field").performTextInput("Mute the drums")
            tap("chat-send")
            compose.waitForTag("chat-plan")
            audit(scenario, "Chat")
            compose.onNodeWithTag("connection").performClick()
            compose.waitForTag("done")
            compose.onNodeWithTag("response-again").performScrollTo()
            audit(scenario, "Computer")
            report()
        }
    }
}
