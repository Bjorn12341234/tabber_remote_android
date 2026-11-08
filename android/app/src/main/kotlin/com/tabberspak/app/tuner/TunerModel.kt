package com.tabberspak.app.tuner

import com.tabberspak.app.ui.Format

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tabberspak.remotekit.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The microphone's pitch, measured on the microphone's own thread by the Viga Tuner's detector, as
 * the iPhone's PitchTap. Only that thread feeds it; the lock guards the result the main thread reads.
 */
class PitchTap {
    private val detector = YinPitchDetector()
    private val lock = Any()
    private var latest = PitchResult()

    fun prepare(sampleRate: Double, blockSize: Int) = synchronized(lock) {
        detector.prepare(sampleRate, blockSize)
        latest = PitchResult()
    }

    fun feed(samples: FloatArray, count: Int) = synchronized(lock) {
        if (detector.process(samples, count)) latest = detector.getLatestResult()
    }

    fun read(): PitchResult = synchronized(lock) { latest }
}

/**
 * Tabber Tuner (plan: TR32), ported from the iPhone's TunerModel.swift: what the instrument plays
 * against the chosen track's strings, from the phone's microphone. The sound never leaves the phone
 * and nothing is recorded. Its properties are Compose state, written on the main thread.
 *
 * [microphone] opens the microphone for [start] (Microphone.start on the phone); the demo never
 * calls it.
 */
class TunerModel(
    private val scope: CoroutineScope,
    tuning: List<Int> = STANDARD,
    access: Access = Access.UNKNOWN,
    private val microphone: (PitchTap) -> Microphone? = { null },
) {
    enum class Access { UNKNOWN, GRANTED, DENIED }

    data class Reading(
        /** The note heard, or the string it is closest to. */
        val note: String,
        val octave: Int,
        /** Off by this much: negative is flat. */
        val cents: Double,
        val frequency: Double,
        /** Which string of the tuning (1 is the highest), when one is close. */
        val string: Int?,
    ) {
        val inTune: Boolean get() = abs(cents) <= IN_TUNE

        /** The dial's words under the note: "24 cents flat", or "In tune" (the iPhone's "%.0f"). */
        val words: String
            get() = if (inTune) "In tune" else "${Math.rint(abs(cents)).toLong()} cents ${if (cents < 0) "flat" else "sharp"}"

        /** What the dial tells TalkBack: "A2, 24 cents flat", or "A2, in tune". */
        val spoken: String
            get() = if (inTune) "$note$octave, in tune"
            else "$note$octave, ${Math.round(abs(cents))} cents ${if (cents < 0) "flat" else "sharp"}"

        /** "110.00 Hz", rounded as the iPhone's "%.2f Hz" rounds. */
        val hertz: String get() = BigDecimal(frequency).setScale(2, RoundingMode.HALF_EVEN).toPlainString() + " Hz"
    }

    /** Where the strings come from: the name under the dial and the open strings, highest first. */
    data class Source(val name: String, val tuning: List<Int>)

    var access by mutableStateOf(access)
    var listening by mutableStateOf(false)
        private set
    var reading by mutableStateOf<Reading?>(null)
        private set

    /** The open strings, highest first: the chosen track's, or standard guitar. */
    var tuning by mutableStateOf(tuning)
    var reference = 440.0

    private var poll: Job? = null
    private var input: Microphone? = null
    private var smoothed: Smoothed? = null
    private var demoStart = System.nanoTime()

    private data class Smoothed(val string: Int?, val midi: Int, val cents: Double)

    /** Start listening: the microphone, or in the demo a guitar being tuned. */
    fun start(demo: Boolean) {
        if (listening) return
        if (demo) {
            access = Access.GRANTED
            demoStart = System.nanoTime()
            listening = true
            poll = scope.launch {
                while (isActive) {
                    update(simulated((System.nanoTime() - demoStart) / 1e9))
                    delay(50)
                }
            }
            return
        }
        if (access != Access.GRANTED) return
        // The microphone runs on its own thread. If it cannot open (another app holds it, or there
        // is no input), nothing reaches the tap and the tuner just waits, as on the iPhone.
        val tap = PitchTap()
        input = microphone(tap)
        listening = true
        poll = scope.launch {
            while (isActive) {
                update(tap.read())
                delay(50)
            }
        }
    }

    fun stop() {
        poll?.cancel()
        poll = null
        input?.stop()
        input = null
        listening = false
        reading = null
        smoothed = null
    }

    /**
     * A detected pitch as the tuner shows it: the nearest string when one is within a semitone,
     * else the nearest note; the cents smoothed while the target holds.
     */
    fun update(result: PitchResult) {
        if (result.isSilent || !(result.frequency > 20f) || !(result.clarity > 0.5f)) {
            reading = null
            smoothed = null
            return
        }
        val heard = 69 + 12 * log2(result.frequency.toDouble() / reference)
        val nearest = tuning.withIndex().minByOrNull { abs(it.value - heard) }
        val string: Int?
        val midi: Int
        if (nearest != null && abs(nearest.value - heard) <= 1.0) {
            string = nearest.index + 1
            midi = nearest.value
        } else {
            string = null
            midi = heard.roundToInt()
        }
        val raw = (heard - midi) * 100
        var cents = raw
        val last = smoothed
        if (last != null && last.string == string && last.midi == midi) cents = last.cents + (raw - last.cents) * 0.35
        smoothed = Smoothed(string, midi, cents)
        reading = Reading(
            note = Format.noteNames[((midi % 12) + 12) % 12], octave = midi / 12 - 1,
            cents = cents, frequency = result.frequency.toDouble(), string = string,
        )
    }

    /** The demo, [elapsed] seconds in: each string in turn, starting flat and settling in tune. */
    fun simulated(elapsed: Double): PitchResult {
        val strings = tuning.reversed()
        if (strings.isEmpty()) return PitchResult() // no strings to tune (the iPhone would stop here)
        val index = (elapsed / 4).toInt() % max(1, strings.size)
        val phase = elapsed % 4.0
        val cents = -28 * exp(-phase * 1.6) + 1.2 * sin(elapsed * 5)
        val midi = strings[index] + cents / 100
        return PitchResult(frequency = (reference * 2.0.pow((midi - 69) / 12)).toFloat(), clarity = 0.95f, isSilent = false)
    }

    companion object {
        /** Within this many cents the note is in tune. */
        const val IN_TUNE = 3.0

        /** A standard guitar, highest string first. */
        val STANDARD = listOf(64, 59, 55, 50, 45, 40)

        /** The lowest note the detector's window reaches: A0, below a five-string bass's low B (30.87 Hz). */
        const val LOWEST_HZ = 27.5

        /**
         * The detector's window, in samples at the microphone's rate. YIN finds a period only up to
         * its longest lag, an eighth of the window less two, counted at a quarter of the rate. With
         * the iPhone's fixed 1024 (TunerModel.swift) that lag is 126 samples at 12 kHz, so at 48 kHz
         * nothing below 95 Hz reads: not the guitar's low E (82.4 Hz), nor three of a bass's four
         * strings (YinPitchDetectorTest shows it). This window starts at the iPhone's 1024 and
         * doubles until the longest lag holds [LOWEST_HZ]'s period: 4096 at 44.1 and 48 kHz.
         */
        fun blockSize(sampleRate: Double): Int {
            var block = 1024
            while (block / 8 - 2 < sampleRate / 4 / LOWEST_HZ) block *= 2
            return block
        }

        /** The chosen track's strings when it has tab, else a standard guitar. */
        fun source(tracks: List<Track>): Source {
            val track = tracks.firstOrNull { it.selected }
            val tuning = track?.tuning
            return if (track != null && tuning != null) Source("Strings of ${track.name}", tuning) else Source("Standard tuning", STANDARD)
        }
    }
}
