package com.tabberspak.remotekit

import kotlin.math.max
import kotlin.math.min

/**
 * One tab track's notes in the demo computer, edited as Tabber Studio's Tab view edits them
 * (remote_host/tablature.py, ui/main_window.py _on_fretboard_click, ui/piano_staff_input.py,
 * ui/score_scene.py), as apple/RemoteKit/DemoTab.swift:
 * - a fretboard tap writes that fret on that string at the cursor's beat, or takes it away if it
 *   is already there; the cursor stays, so more taps build a chord; the chosen duration applies
 *   only to an empty beat;
 * - a piano key does the same with the lowest fret that plays the pitch;
 * - R toggles a rest; Delete takes the note on the cursor's string, and a beat left with none is a
 *   rest;
 * - moving on past the last beat fills the bar with a rest beat, or starts the next bar, adding
 *   one at the end of the song.
 *
 * A value, as the Swift struct is: the editing functions change this one, so edit a [copy] of a
 * tab that a song holds. Its lists are never changed in place, only replaced, so a copy shares
 * nothing that changes.
 */
internal class DemoTab(
    val tuning: List<Int>,
    bars: List<List<TabBeat>>,
    val timeSignature: TimeSignature = TimeSignature(4, 4),
) {
    var bars: List<List<TabBeat>> = bars
        private set

    /** The same tab, to edit without changing this one. */
    fun copy(): DemoTab = DemoTab(tuning, bars, timeSignature)

    val capacity: Double get() = timeSignature.beats * 4.0 / timeSignature.unit

    fun filled(bar: Int): Double = bars[bar - 1].fold(0.0) { sum, beat -> sum + beat.duration.quarters }

    fun clamp(cursor: TabCursor): TabCursor {
        val bar = max(1, min(bars.size, cursor.bar))
        val beat = max(1, min(max(1, bars[bar - 1].size), cursor.beat))
        val string = max(1, min(tuning.size, cursor.string))
        return TabCursor(bar, beat, string)
    }

    private fun setBar(bar: Int, beats: List<TabBeat>) {
        bars = bars.toMutableList().also { it[bar - 1] = beats }
    }

    private fun setBeat(bar: Int, index: Int, beat: TabBeat) {
        setBar(bar, bars[bar - 1].toMutableList().also { it[index] = beat })
    }

    private fun hasBeat(cursor: TabCursor): Boolean =
        cursor.bar - 1 in bars.indices && cursor.beat - 1 in bars[cursor.bar - 1].indices

    /** The bar's beat at the cursor, made if the bar has none yet. */
    private fun beatIndex(cursor: TabCursor, duration: NoteValue): Int {
        if (bars[cursor.bar - 1].isEmpty()) {
            setBar(cursor.bar, listOf(TabBeat(duration, rest = true, notes = emptyList())))
        }
        return min(cursor.beat, bars[cursor.bar - 1].size) - 1
    }

    /** A fretboard tap. Returns whether the song changed. */
    fun put(string: Int, fret: Int, at: TabCursor, duration: NoteValue): Boolean {
        if (string !in 1..tuning.size || fret !in 0..MAX_FRET) return false
        val i = beatIndex(at, duration)
        var beat = bars[at.bar - 1][i]
        val same = beat.notes.indexOfFirst { it.string == string && it.fret == fret }
        beat = if (same >= 0) {
            // Tapping the same fret again takes it away.
            val notes = beat.notes.filterIndexed { index, _ -> index != same }
            beat.copy(notes = notes, rest = notes.isEmpty())
        } else {
            // An empty beat takes the chosen value; one note per string.
            val value = if (beat.rest && beat.notes.isEmpty()) duration else beat.duration
            val notes = (beat.notes.filter { it.string != string } + TabNote(string, fret)).sortedBy { it.string }
            beat.copy(duration = value, notes = notes, rest = false)
        }
        setBeat(at.bar, i, beat)
        return true
    }

    /** Where a piano key lands. */
    data class Spot(val string: Int, val fret: Int)

    /** Where a piano key lands: the lowest fret that plays it, then the higher string. */
    fun place(pitch: Int): Spot? {
        var best: Spot? = null
        for ((index, open) in tuning.withIndex()) {
            val fret = pitch - open
            if (fret !in 0..MAX_FRET) continue
            val current = best
            if (current == null || fret < current.fret) best = Spot(index + 1, fret)
        }
        return best
    }

    /** What a piano key did: the string it landed on, and whether the song changed. */
    data class PitchPut(val string: Int, val changed: Boolean)

    /** A piano key: takes the pitch away if the beat has it, else writes it. */
    fun put(pitch: Int, at: TabCursor, duration: NoteValue): PitchPut {
        if (hasBeat(at)) {
            val beat = bars[at.bar - 1][at.beat - 1]
            val note = beat.notes.firstOrNull { tuning[it.string - 1] + it.fret == pitch }
            if (note != null) return PitchPut(note.string, put(string = note.string, fret = note.fret, at = at, duration = duration))
        }
        val spot = place(pitch) ?: return PitchPut(at.string, false)
        return PitchPut(spot.string, put(string = spot.string, fret = spot.fret, at = at, duration = duration))
    }

    fun setDuration(duration: NoteValue, at: TabCursor): Boolean {
        if (!hasBeat(at) || bars[at.bar - 1][at.beat - 1].duration == duration) return false
        setBeat(at.bar, at.beat - 1, bars[at.bar - 1][at.beat - 1].copy(duration = duration))
        return true
    }

    /** R: a beat with notes becomes a rest; a rest becomes an empty beat. */
    fun rest(at: TabCursor): Boolean {
        if (!hasBeat(at)) return false
        val beat = bars[at.bar - 1][at.beat - 1]
        setBeat(at.bar, at.beat - 1, TabBeat(beat.duration, rest = !beat.rest || beat.notes.isNotEmpty(), notes = emptyList()))
        return true
    }

    /** Delete: the note on the cursor's string, and nothing else. */
    fun delete(at: TabCursor): Boolean {
        if (!hasBeat(at)) return false
        val beat = bars[at.bar - 1][at.beat - 1]
        if (beat.notes.none { it.string == at.string }) return false
        val notes = beat.notes.filter { it.string != at.string }
        setBeat(at.bar, at.beat - 1, beat.copy(notes = notes, rest = notes.isEmpty()))
        return true
    }

    /** The beat under the cursor, when the bar has it. */
    fun beat(at: TabCursor): TabBeat? = if (hasBeat(at)) bars[at.bar - 1][at.beat - 1] else null

    /** The note on a string at the cursor's beat, for the undo label of a tap that takes it off. */
    fun note(on: Int, at: TabCursor): TabNote? =
        if (hasBeat(at)) bars[at.bar - 1][at.beat - 1].notes.firstOrNull { it.string == on } else null

    /** Where a step took the cursor, and whether it added a beat or a bar. */
    data class Moved(val cursor: TabCursor, val changed: Boolean)

    /**
     * The next or previous beat. Forward past the last beat fills the bar with a rest beat, or goes
     * to the next bar, adding one at the end.
     */
    fun move(cursor: TabCursor, by: Int, duration: NoteValue): Moved {
        var c = clamp(cursor)
        if (by < 0) {
            if (c.beat > 1) {
                c = c.copy(beat = c.beat - 1)
            } else if (c.bar > 1) {
                val bar = c.bar - 1
                c = c.copy(bar = bar, beat = max(1, bars[bar - 1].size))
            }
            return Moved(c, false)
        }
        if (c.beat < bars[c.bar - 1].size) return Moved(c.copy(beat = c.beat + 1), false)
        if (filled(c.bar) + duration.quarters <= capacity + 0.0001) {
            setBar(c.bar, bars[c.bar - 1] + TabBeat(duration, rest = true, notes = emptyList()))
            return Moved(c.copy(beat = bars[c.bar - 1].size), true)
        }
        if (c.bar == bars.size) {
            bars = bars + listOf(listOf(TabBeat(duration, rest = true, notes = emptyList())))
            return Moved(c.copy(bar = c.bar + 1, beat = 1), true)
        }
        return Moved(c.copy(bar = c.bar + 1, beat = 1), false)
    }

    /** The cursor's bar and its neighbours, as the phone shows them. */
    fun window(around: TabCursor): List<TabBar> {
        val first = max(1, around.bar - 1)
        val last = min(bars.size, around.bar + 3)
        if (first > last) return emptyList()
        return (first..last).map { TabBar(it, timeSignature, bars[it - 1]) }
    }

    override fun equals(other: Any?): Boolean =
        other is DemoTab && other.tuning == tuning && other.bars == bars && other.timeSignature == timeSignature

    override fun hashCode(): Int = listOf(tuning, bars, timeSignature).hashCode()

    companion object {
        const val MAX_FRET = 24

        // The demo song.

        val STANDARD = listOf(64, 59, 55, 50, 45, 40)
        val BASS = listOf(43, 38, 33, 28)

        /** Eight bars of Em, C, G, D arpeggios in eighths, then eight empty bars. */
        fun demoGuitar(): DemoTab {
            val eighth = NoteValue(8)
            fun bar(vararg notes: Pair<Int, Int>): List<TabBeat> =
                notes.map { (string, fret) -> TabBeat(eighth, rest = false, notes = listOf(TabNote(string, fret))) }
            val em = bar(6 to 0, 4 to 2, 3 to 0, 2 to 0, 1 to 0, 2 to 0, 3 to 0, 4 to 2)
            val c = bar(5 to 3, 4 to 2, 3 to 0, 2 to 1, 1 to 0, 2 to 1, 3 to 0, 4 to 2)
            val g = bar(6 to 3, 5 to 2, 4 to 0, 3 to 0, 2 to 0, 1 to 3, 2 to 0, 3 to 0)
            val d = bar(4 to 0, 3 to 2, 2 to 3, 1 to 2, 2 to 3, 3 to 2, 4 to 0, 3 to 2)
            val empty = listOf(TabBeat(NoteValue(4), rest = true, notes = emptyList()))
            return DemoTab(STANDARD, listOf(em, c, g, d, em, c, g, d) + List(8) { empty })
        }

        /** Roots in quarters under the guitar. */
        fun demoBass(): DemoTab {
            val quarter = NoteValue(4)
            fun bar(string: Int, fret: Int): List<TabBeat> =
                List(4) { TabBeat(quarter, rest = false, notes = listOf(TabNote(string, fret))) }
            val bars = listOf(bar(4, 0), bar(3, 3), bar(4, 3), bar(3, 5))
            val empty = listOf(TabBeat(quarter, rest = true, notes = emptyList()))
            return DemoTab(BASS, bars + bars + List(8) { empty })
        }
    }
}
