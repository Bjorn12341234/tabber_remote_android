package com.tabberspak.app.tuner

import com.tabberspak.remotekit.MonitorMode
import com.tabberspak.remotekit.Track
import com.tabberspak.remotekit.TrackKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.sin

/**
 * The tuner's arithmetic, as the iPhone's TunerModel: the note, the cents, the nearest string within
 * a semitone, the smoothing; the dial's words; the demo's guitar; where the strings come from; and
 * that the microphone opens only when it may.
 */
class TunerModelTest {
    private val bass = listOf(43, 38, 33, 28)

    private fun model(tuning: List<Int> = TunerModel.STANDARD, microphone: (PitchTap) -> Microphone? = { null }) =
        TunerModel(CoroutineScope(Dispatchers.Unconfined), tuning, microphone = microphone)

    private fun heard(hz: Double, clarity: Float = 0.95f) = PitchResult(hz.toFloat(), clarity, isSilent = false)

    /** The cents from [hz] to the note [midi], with A4 at 440. */
    private fun cents(hz: Double, midi: Int) = 1200 * log2(hz / (440.0 * Math.pow(2.0, (midi - 69) / 12.0)))

    private fun TunerModel.hear(hz: Double): TunerModel.Reading {
        update(heard(hz))
        return reading ?: throw AssertionError("no reading for $hz Hz")
    }

    /**
     * The app's main thread, for the tests that start the tuner: its poll runs there, as on the
     * phone, and the test reads and stops it there too.
     */
    private fun <T> onMain(test: (ExecutorCoroutineDispatcher) -> T): T =
        Executors.newSingleThreadExecutor().asCoroutineDispatcher().use(test)

    private fun <T> ExecutorCoroutineDispatcher.run(block: () -> T): T = runBlocking(this) { block() }

    private fun ExecutorCoroutineDispatcher.waitFor(what: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 3000
        while (!run(condition)) {
            if (System.currentTimeMillis() > deadline) throw AssertionError("never $what")
            Thread.sleep(20)
        }
    }

    @Test fun aStringInTune() {
        val reading = model().hear(110.0)
        assertEquals("A", reading.note)
        assertEquals(2, reading.octave)
        assertEquals(0.0, reading.cents, 1e-9)
        assertEquals(5, reading.string)
        assertTrue(reading.inTune)
        assertEquals("In tune", reading.words)
        assertEquals("A2, in tune", reading.spoken)
        assertEquals("110.00 Hz", reading.hertz)
    }

    @Test fun aFlatString() {
        val reading = model().hear(108.0)
        assertEquals("A", reading.note)
        assertEquals(2, reading.octave)
        assertEquals(cents(108.0, 45), reading.cents, 1e-4) // -31.77
        assertEquals(5, reading.string)
        assertFalse(reading.inTune)
        assertEquals("32 cents flat", reading.words)
        assertEquals("A2, 32 cents flat", reading.spoken)
    }

    @Test fun aSharpHighE() {
        val reading = model().hear(332.0)
        assertEquals("E", reading.note)
        assertEquals(4, reading.octave)
        assertEquals(1, reading.string)
        assertEquals(cents(332.0, 64), reading.cents, 1e-4) // +12.4
        assertEquals("E4, 12 cents sharp", reading.spoken)
    }

    @Test fun theLowE() {
        val reading = model().hear(82.41)
        assertEquals("E2", reading.note + reading.octave)
        assertEquals(6, reading.string)
        assertTrue(reading.inTune)
    }

    @Test fun inTuneIsWithinThreeCents() {
        val e2 = 440.0 * Math.pow(2.0, (40 - 69) / 12.0)
        assertTrue(model().hear(e2 * Math.pow(2.0, 2.99 / 1200)).inTune)
        assertTrue(model().hear(e2 * Math.pow(2.0, -2.99 / 1200)).inTune)
        assertFalse(model().hear(e2 * Math.pow(2.0, 3.01 / 1200)).inTune)
        assertEquals("E2, 3 cents sharp", model().hear(e2 * Math.pow(2.0, 3.2 / 1200)).spoken)
    }

    @Test fun theNearestStringWithinASemitone() {
        // 104 Hz is 97 cents under A2: still the A string, far flat.
        val reading = model().hear(104.0)
        assertEquals(5, reading.string)
        assertEquals("A", reading.note)
        assertEquals(cents(104.0, 45), reading.cents, 1e-4)
        assertEquals("A2, 97 cents flat", reading.spoken)
    }

    @Test fun anyOtherNoteIsNamedAsItIs() {
        // More than a semitone from every string: the nearest note, in Tabber Studio's names.
        val names = mapOf(130.81 to "C3", 554.37 to "C♯5", 622.25 to "E♭5", 739.99 to "F♯5", 830.61 to "G♯5", 932.33 to "B♭5")
        for ((hz, name) in names) {
            val reading = model().hear(hz)
            assertNull("$hz Hz is no string", reading.string)
            assertEquals(name, reading.note + reading.octave)
            assertTrue(abs(reading.cents) < 1)
        }
    }

    @Test fun theCentsAreSmoothedWhileTheTargetHolds() {
        val tuner = model()
        val first = tuner.hear(108.0).cents
        assertEquals(first + (0.0 - first) * 0.35, tuner.hear(110.0).cents, 1e-9) // -20.65: a third of the way
        val third = tuner.hear(110.0).cents
        assertEquals(first * 0.65 * 0.65, third, 1e-9)
    }

    @Test fun aNewTargetStartsAfresh() {
        val tuner = model()
        tuner.hear(108.0)
        val d3 = tuner.hear(145.0)
        assertEquals(4, d3.string)
        assertEquals(cents(145.0, 50), d3.cents, 1e-4) // not smoothed from the A
    }

    @Test fun silenceClearsTheReading() {
        val tuner = model()
        tuner.hear(108.0)
        tuner.update(PitchResult())
        assertNull(tuner.reading)
        assertEquals(cents(110.5, 45), tuner.hear(110.5).cents, 1e-4) // and the smoothing with it
    }

    @Test fun anUnclearOrTooLowPitchIsNoReading() {
        val tuner = model()
        tuner.update(heard(110.0, clarity = 0.5f))
        assertNull(tuner.reading)
        tuner.update(heard(20.0))
        assertNull(tuner.reading)
        tuner.update(heard(Double.NaN))
        assertNull(tuner.reading)
        tuner.update(PitchResult(110f, 0.95f, isSilent = true))
        assertNull(tuner.reading)
    }

    @Test fun aBassesStrings() {
        val tuner = model(bass)
        assertEquals(4, tuner.hear(41.20).string) // E1, the lowest
        assertEquals("E1", tuner.reading!!.note + tuner.reading!!.octave)
        assertEquals(3, tuner.hear(55.0).string)
        assertEquals(1, tuner.hear(98.0).string)
    }

    @Test fun theFrequencyReadsAsTheIPhoneWritesIt() {
        // "%.2f" rounds a tie to even: 82.125 is exact in binary, and reads 82.12.
        val reading = TunerModel.Reading("E", 2, 0.0, 82.125, 6)
        assertEquals("82.12 Hz", reading.hertz)
        assertEquals("329.63 Hz", reading.copy(frequency = 329.6276).hertz)
    }

    @Test fun theDialsWordsRoundAsTheIPhonesDo() {
        // The words under the note use "%.0f" (a tie to even); the spoken value rounds a tie up.
        val reading = TunerModel.Reading("A", 2, -24.5, 108.5, 5)
        assertEquals("24 cents flat", reading.words)
        assertEquals("A2, 25 cents flat", reading.spoken)
        assertEquals("26 cents sharp", reading.copy(cents = 25.5).words)
    }

    @Test fun theDemoTunesAGuitarStringByString() {
        // The tuner polls 20 times a second; each string has four seconds, from 28 cents flat to in tune.
        val tuner = model()
        val order = listOf("E2", "A2", "D3", "G3", "B3", "E4", "E2")
        for ((window, name) in order.withIndex()) {
            val readings = (0 until 80).map { tick ->
                tuner.update(tuner.simulated(window * 4 + tick / 20.0))
                assertNotNull(tuner.reading)
                tuner.reading!!
            }
            assertTrue("each reading is $name", readings.all { it.note + it.octave == name })
            assertEquals(6 - window % 6, readings.first().string)
            assertTrue("$name starts flat", readings.first().cents in -30.0..-26.0)
            assertTrue("$name says how far off", readings.first().spoken.endsWith("cents flat"))
            assertTrue("$name settles in tune", readings.drop(40).any { it.inTune })
            assertTrue("$name ends in tune", readings.last().spoken == "$name, in tune")
        }
    }

    @Test fun theDemoTunesTheChosenTracksStrings() {
        val tuner = model(bass)
        val names = (0 until 4).map { string ->
            tuner.update(tuner.simulated(string * 4 + 3.5))
            tuner.reading!!.note + tuner.reading!!.octave
        }
        assertEquals(listOf("E1", "A1", "D2", "G2"), names)
    }

    @Test fun theDemoWithNoStringsIsSilent() = assertTrue(model(emptyList()).simulated(1.0).isSilent)

    @Test fun theStringsComeFromTheChosenTrack() {
        fun track(name: String, selected: Boolean, kind: TrackKind = TrackKind.MIDI, tuning: List<Int>? = null) =
            Track("id-$name", name, kind, armed = false, monitor = MonitorMode.AUTO, selected = selected, color = null, tuning = tuning)
        val guitar = track("Guitar", true, tuning = TunerModel.STANDARD)
        val bassTrack = track("Bass", false, tuning = bass)
        val drums = track("Drums", false)
        val vocals = track("Vocals", false, kind = TrackKind.AUDIO)
        assertEquals(TunerModel.Source("Strings of Guitar", TunerModel.STANDARD), TunerModel.source(listOf(guitar, bassTrack, vocals)))
        assertEquals(
            TunerModel.Source("Strings of Bass", bass),
            TunerModel.source(listOf(guitar.copy(selected = false), bassTrack.copy(selected = true), vocals)),
        )
        val standard = TunerModel.Source("Standard tuning", TunerModel.STANDARD)
        assertEquals(standard, TunerModel.source(listOf(guitar.copy(selected = false), vocals.copy(selected = true)))) // audio
        assertEquals(standard, TunerModel.source(listOf(drums.copy(selected = true), bassTrack))) // MIDI without tab
        assertEquals(standard, TunerModel.source(emptyList()))
    }

    @Test fun theWindowReachesA0() {
        assertEquals(4096, TunerModel.blockSize(48000.0))
        assertEquals(4096, TunerModel.blockSize(44100.0))
        assertEquals(8192, TunerModel.blockSize(96000.0))
        for (rate in listOf(8000.0, 16000.0, 22050.0, 32000.0, 44100.0, 48000.0, 88200.0, 96000.0, 192000.0)) {
            val block = TunerModel.blockSize(rate)
            val longest = block / 8 - 2 // YIN's longest lag, at a quarter of the rate
            assertTrue("$rate Hz: $block reaches A0", longest >= rate / 4 / TunerModel.LOWEST_HZ)
            assertTrue("$rate Hz: $block is no longer than it needs to be", block == 1024 || block / 16 - 2 < rate / 4 / TunerModel.LOWEST_HZ)
        }
    }

    @Test fun theDemoNeverOpensTheMicrophone() = onMain { main ->
        val tuner = TunerModel(CoroutineScope(main)) { fail("the demo opened the microphone"); null }
        main.run { tuner.start(demo = true) }
        assertTrue(main.run { tuner.listening })
        assertEquals(TunerModel.Access.GRANTED, main.run { tuner.access })
        main.waitFor("a reading") { tuner.reading?.spoken?.startsWith("E2, ") == true } // the low E first
        main.run { tuner.stop() }
        assertFalse(main.run { tuner.listening })
        Thread.sleep(150) // three polls' time: none comes
        assertNull(main.run { tuner.reading })
    }

    @Test fun withoutPermissionTheMicrophoneStaysShut() {
        for (access in listOf(TunerModel.Access.UNKNOWN, TunerModel.Access.DENIED)) {
            val tuner = TunerModel(CoroutineScope(Dispatchers.Unconfined), access = access) { fail("opened without permission"); null }
            tuner.start(demo = false)
            assertFalse(tuner.listening)
        }
    }

    @Test fun theMicrophonesPitchReachesTheDial() = onMain { main ->
        // With permission, start hands the microphone a tap; what the tap hears shows on the dial.
        var tap: PitchTap? = null
        val tuner = TunerModel(CoroutineScope(main), access = TunerModel.Access.GRANTED) { tap = it; null }
        main.run { tuner.start(demo = false) }
        assertTrue(main.run { tuner.listening })
        val microphone = tap ?: throw AssertionError("start never opened the microphone")
        // The microphone's thread is this one: a second of A2 at 48 kHz, 1024 frames at a time.
        microphone.prepare(48000.0, TunerModel.blockSize(48000.0))
        val frames = FloatArray(1024)
        for (block in 0 until 47) {
            for (i in frames.indices) frames[i] = (0.2 * sin(2 * PI * 110.0 * (block * frames.size + i) / 48000.0)).toFloat()
            microphone.feed(frames, frames.size)
        }
        main.waitFor("A2 in tune") { tuner.reading?.spoken == "A2, in tune" }
        main.run { tuner.stop() }
        assertNull(main.run { tuner.reading })
    }
}
