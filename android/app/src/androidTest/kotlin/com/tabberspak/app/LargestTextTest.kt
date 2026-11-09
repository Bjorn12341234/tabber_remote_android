package com.tabberspak.app

import android.os.ParcelFileDescriptor
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The largest text Android offers (200 %), as the iPhone's tests at its accessibility sizes: rows
 * that would cut or break their words stack, fields grow, and nothing reads cut short.
 */
@RunWith(AndroidJUnit4::class)
class LargestTextTest {
    @get:Rule val compose = createEmptyComposeRule()

    private fun fontScale(value: String) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("settings put system font_scale $value")).use { it.readBytes() }
        Thread.sleep(500) // the new size reaches the app's next configuration
    }

    @Before fun largest() = fontScale("2.0")

    @After fun normal() = fontScale("1.0")

    /** The control on screen: a layout that did not fit is measured from a copy that is never placed. */
    private fun placed(tag: String) =
        compose.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first { it.layoutInfo.isPlaced }

    private fun bounds(tag: String) = placed(tag).boundsInRoot

    private fun density() = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density

    /** What under the control does not fit its room (a word cut or ellipsized), or null when all of it does. */
    private fun cut(tag: String): String? {
        val node = placed(tag)
        val texts = (listOf(node) + node.children).mapNotNull { child ->
            val results = ArrayList<TextLayoutResult>()
            child.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(results)
            results.firstOrNull()
        }
        // Cut: the words need more lines than the text may use ("1/16" on one line left "1/1"), or
        // they end in an ellipsis. (A narrow text in a wide room reports a width "overflow".)
        return texts.firstOrNull { it.multiParagraph.didExceedMaxLines || (0 until it.lineCount).any { line -> it.isLineEllipsized(line) } }?.let {
            "\"${it.layoutInput.text}\" in ${it.size}, lines ${it.lineCount} of at most ${it.layoutInput.maxLines}"
        }
    }

    private fun assertWhole(tag: String) {
        val problem = cut(tag)
        assertTrue("$tag is cut: $problem", problem == null)
    }

    /** At the largest text the toggles stack and the trainer's fields go one to a line, whole, within the screen. */
    @Test fun theTogglesAndTrainerAtTheLargestText() {
        launchDemo().use {
            compose.waitForTag("loop").performClick()
            compose.reveal("trainer")
            compose.onNodeWithTag("trainer").performClick()
            compose.waitSelected("trainer")
            assertTrue("stacked, not side by side", bounds("count-in").top >= bounds("loop").bottom - 1)
            val start = bounds("trainer-start")
            val step = bounds("trainer-step")
            // Android's 200 % is not the iPhone's largest (about 300 %): the field holds its words
            // within its 48 dp, whole.
            assertTrue("the field is a full control", start.height / density() >= 48)
            assertWhole("trainer-start")
            assertTrue("one field to a line", step.top >= start.bottom - 1)
            val screen = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.widthPixels
            assertTrue("within the screen", start.right <= screen)
            for (tag in listOf("loop", "count-in", "click", "trainer")) assertWhole(tag)
        }
    }

    /** The note values never read cut short: "1/1" for 1/16 would be another value. */
    @Test fun theTabScreenKeepsEveryValueWhole() {
        launchDemo("screen" to "tab").use {
            compose.waitForTag("value-32")
            for (tag in listOf("value-1", "value-2", "value-4", "value-8", "value-16", "value-32", "dot", "triplet", "rest", "delete-note")) {
                compose.onNodeWithTag(tag).performScrollTo()
                assertWhole(tag)
            }
            assertTrue("the values in rows of fewer", bounds("value-8").top >= bounds("value-1").bottom - 1)
            compose.waitForTag("previous")
            compose.onNodeWithTag("input-Piano").performScrollTo()
            assertWhole("input-Piano")
        }
    }

    /** The Computer sheet's rows grow and wrap rather than clip. */
    @Test fun theResponseRowsGrowWithTheText() {
        launchDemo().use {
            compose.waitForTag("play").performClick()
            compose.waitForWords("play", "Pause")
            compose.onNodeWithTag("connection").performClick()
            compose.waitForTag("response-again").performScrollTo()
            compose.waitForWords("response-typical", " ms")
            // Android's 200 % is not the iPhone's largest (about 300 %): "Start again" still fits
            // its 48 dp, so the check is that its words are whole, and the note's lines grow.
            assertTrue("Start again is a full control", bounds("response-again").height / density() >= 48)
            assertWhole("response-again")
            assertTrue("the note wraps over more lines", bounds("response-note").height / density() > 70)
            assertWhole("response-note")
        }
    }

    /** The choices that would break their words are a menu at the largest text, and still choose. */
    @Test fun theComputersViewIsAMenu() {
        launchDemo().use {
            compose.waitForWords("view-editor", "Tab")
            compose.onNodeWithTag("view-editor").performClick()
            compose.waitForTag("view-editor-Arrange").performClick()
            compose.waitForWords("view-editor", "Arrange")
            compose.onAllNodes(hasTestTag("view-split")).fetchSemanticsNodes().isNotEmpty().let { assertTrue("Split beside it", it) }
        }
    }
}
