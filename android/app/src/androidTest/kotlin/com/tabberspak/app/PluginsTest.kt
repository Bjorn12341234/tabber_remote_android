package com.tabberspak.app

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Plug-ins on the Mixer's strips against the demo computer (TR44), as the iPhone's PluginsUITests.
 * The owner: "should you be able to insert plugins on tracks from the app?", then "yes". Each
 * strip's INSERTS, as Tabber Studio's strip lists them; its "＋ Plugin" opens Studio's Insert
 * Plugin browser, with its tabs, format filter and search; a plug-in goes in at the end of the
 * chain, and its menu bypasses and removes it; an instrument becomes a MIDI track's sound source.
 */
@RunWith(AndroidJUnit4::class)
class PluginsTest {
    @get:Rule val compose = createEmptyComposeRule()

    /** A strip's control, the row scrolled to it first: the row makes only the strips in view. */
    private fun tapOnStrip(tag: String) {
        compose.waitForTag("strips")
        compose.onNodeWithTag("strips").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performClick()
    }

    @Test fun anEffectIsInsertedBypassedAndRemoved() {
        launchDemo("screen" to "mixer").use {
            compose.waitForWords("insert-Guitar-Tabber Amp", "Tabber Amp on Guitar, on") // the guitar plays through Tabber Amp
            tapOnStrip("add-plugin-Bass")
            compose.waitForTag("insert-plugin-title")
            compose.waitForTag("plugin-Tabber Compressor").performClick()
            compose.waitForWords("insert-Bass-Tabber Compressor", "Tabber Compressor on Bass, on") // it goes in
            compose.waitForNoTag("insert-plugin-title") // the browser closes once it is in
            tapOnStrip("insert-Bass-Tabber Compressor")
            compose.waitForTag("insert-bypass").performClick()
            compose.waitForWords("insert-Bass-Tabber Compressor", "bypassed") // the hollow dot
            tapOnStrip("insert-Bass-Tabber Compressor")
            compose.waitForTag("insert-remove").performClick()
            compose.waitForNoTag("insert-Bass-Tabber Compressor") // and it is gone
        }
    }

    @Test fun theBrowsersTabsFormatsAndSearch() {
        launchDemo("screen" to "mixer").use {
            tapOnStrip("add-plugin-Guitar")
            compose.waitForTag("plugin-Tabber Amp") // Tabber Plugins first, as in Tabber Studio
            assertNull(compose.node("plugin-Plate Reverb"))
            compose.onNodeWithTag("plugin-source-Plugins").performClick()
            compose.waitForTag("plugin-Plate Reverb")
            compose.waitForTag("plugin-Tape Echo")
            compose.onNodeWithTag("plugin-format-CLAP").performClick()
            compose.waitForNoTag("plugin-Plate Reverb") // the format filter
            compose.waitForTag("plugin-Tape Echo")
            compose.onNodeWithTag("plugin-format-All").performClick()
            compose.onNodeWithTag("plugin-source-Tabber Plugins").performClick()
            compose.waitForTag("plugin-search").performTextInput("lim")
            compose.waitForTag("plugin-Tabber Limiter") // the search
            compose.waitForNoTag("plugin-Tabber Amp")
        }
    }

    @Test fun anInstrumentBecomesAMidiTracksSoundSource() {
        launchDemo("screen" to "mixer").use {
            tapOnStrip("add-plugin-Guitar")
            compose.waitForTag("plugin-Tabber Synth").performClick()
            compose.waitForWords("plugin-notice", "Tabber Synth is now the sound source of Guitar.")
            assertNull("an instrument is no insert", compose.node("insert-Guitar-Tabber Synth"))
        }
    }
}
