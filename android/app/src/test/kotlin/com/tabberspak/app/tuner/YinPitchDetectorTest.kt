package com.tabberspak.app.tuner

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Random
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.sin

/**
 * The Viga Tuner's detector on synthetic strings: a fundamental with five overtones in random
 * phases, white noise under it, fed 1024 frames at a time as the microphone feeds it, through the
 * window the tuner uses ([TunerModel.blockSize]).
 */
class YinPitchDetectorTest {
    /** A string: [hz] and its overtones, about 0.18 RMS, with white noise of [noise] RMS. */
    private fun string(
        hz: Double, rate: Double, seconds: Double = 1.5, noise: Double = 0.003,
        overtones: DoubleArray = GUITAR, seed: Long = 7,
    ): FloatArray {
        val random = Random(seed)
        val phases = DoubleArray(overtones.size) { random.nextDouble() * 2 * PI }
        return FloatArray((rate * seconds).toInt()) { i ->
            var s = 0.0
            for (k in overtones.indices) s += overtones[k] * sin(2 * PI * hz * (k + 1) * i / rate + phases[k])
            (0.2 * s + noise * random.nextGaussian()).toFloat()
        }
    }

    /** Every estimate the detector makes, in order. */
    private fun listen(samples: FloatArray, rate: Double, block: Int = TunerModel.blockSize(rate)): List<PitchResult> {
        val detector = YinPitchDetector()
        detector.prepare(rate, block)
        val chunk = FloatArray(1024)
        val results = ArrayList<PitchResult>()
        var at = 0
        while (at < samples.size) {
            val count = minOf(chunk.size, samples.size - at)
            samples.copyInto(chunk, 0, at, at + count)
            if (detector.process(chunk, count)) results.add(detector.getLatestResult())
            at += count
        }
        return results
    }

    /** After the first third of a second, every estimate is the string, within [cents]. */
    private fun assertReads(hz: Double, rate: Double, cents: Double, samples: FloatArray = string(hz, rate)) {
        val results = listen(samples, rate)
        val settled = results.drop((results.size * 0.3 / 1.5).toInt() + 1)
        assertTrue("estimates for $hz Hz", settled.size > 20)
        for (result in settled) {
            assertFalse("$hz Hz at $rate Hz read as silence", result.isSilent)
            assertTrue("$hz Hz clarity ${result.clarity}", result.clarity > 0.5f)
            val off = 1200 * log2(result.frequency / hz)
            assertTrue("$hz Hz read as ${result.frequency} Hz, %.2f cents off".format(off), abs(off) <= cents)
        }
    }

    @Test fun readsEachStringOfAGuitar() {
        // E2 A2 D3 G3 B3 E4: measured within 0.7 cents
        for (hz in listOf(82.41, 110.0, 146.83, 196.0, 246.94, 329.63)) assertReads(hz, 48000.0, cents = 1.5)
    }

    @Test fun readsA440() = assertReads(440.0, 48000.0, cents = 2.5) // measured +1.5 cents: inside the 3-cent band

    @Test fun readsEachStringOfABass() {
        for (hz in listOf(41.20, 55.0, 73.42, 98.0)) assertReads(hz, 48000.0, cents = 1.5) // E1 A1 D2 G2
    }

    @Test fun readsAtCdRate() {
        for (hz in listOf(41.20, 82.41, 329.63)) assertReads(hz, 44100.0, cents = 1.5)
        assertReads(440.0, 44100.0, cents = 2.5)
    }

    @Test fun readsThroughNoise() {
        // Noise 0.03 RMS under 0.18: about 15 dB, a guitar at arm's length in a busy room.
        for (hz in listOf(41.20, 82.41, 329.63, 440.0)) assertReads(hz, 48000.0, cents = 3.0, samples = string(hz, 48000.0, noise = 0.03))
    }

    @Test fun readsAWeakFundamental() {
        // A phone's microphone hears little of a low E's fundamental: the string is still the E, not its octave.
        val weak = doubleArrayOf(0.3, 1.0, 0.7, 0.4, 0.2)
        for (hz in listOf(41.20, 82.41, 110.0)) assertReads(hz, 48000.0, cents = 1.5, samples = string(hz, 48000.0, overtones = weak))
    }

    @Test fun silenceIsNoPitch() {
        val results = listen(FloatArray(48000), 48000.0)
        assertTrue(results.isNotEmpty())
        for (result in results) {
            assertTrue(result.isSilent)
            assertEquals(0f, result.frequency, 0f)
        }
    }

    @Test fun aQuietRoomIsSilence() {
        // Below the gate (a mean square of 0.00001): nothing to tune.
        val faint = string(110.0, 48000.0, noise = 0.0).map { it * 0.01f }.toFloatArray()
        assertTrue(listen(faint, 48000.0).all { it.isSilent })
    }

    @Test fun noiseAloneIsNoPitch() {
        val random = Random(3)
        val hiss = FloatArray(72000) { (0.05 * random.nextGaussian()).toFloat() }
        assertTrue(listen(hiss, 48000.0).drop(5).all { it.isSilent })
    }

    @Test fun brokenSamplesAreSkipped() {
        val samples = string(110.0, 48000.0)
        for (i in 5000 until samples.size step 997) samples[i] = if (i % 2 == 0) Float.NaN else Float.POSITIVE_INFINITY
        assertReads(110.0, 48000.0, cents = 3.0, samples = samples)
    }

    @Test fun theIPhonesWindowCannotHearTheLowE() {
        // With the iPhone's 1024-sample window, YIN's longest lag is 126 samples at 12 kHz: 95 Hz.
        // The guitar's low E reads as silence at 48 kHz, and as 86.8 Hz (+90 cents) at 44.1 kHz.
        assertTrue(listen(string(82.41, 48000.0), 48000.0, block = 1024).all { it.isSilent })
        val cd = listen(string(82.41, 44100.0), 44100.0, block = 1024).filter { !it.isSilent }
        assertTrue(cd.all { abs(1200 * log2(it.frequency / 82.41)) > 50 })
        // A2 is inside its reach.
        assertTrue(listen(string(110.0, 48000.0), 48000.0, block = 1024).drop(10).none { it.isSilent })
    }

    @Test fun theFirstReadingComesWithinAWindow() {
        // 4096 samples at 48 kHz: 85 ms after the string sounds.
        val detector = YinPitchDetector()
        detector.prepare(48000.0, TunerModel.blockSize(48000.0))
        val samples = string(110.0, 48000.0, seconds = 0.2)
        var first = -1
        for (i in samples.indices) {
            if (detector.process(floatArrayOf(samples[i])) && !detector.getLatestResult().isSilent) {
                first = i
                break
            }
        }
        assertEquals(4092, first) // the 1024th sample kept by the 4x decimation
    }

    private companion object {
        /** A guitar-like spectrum: the fundamental strongest, each overtone weaker. */
        val GUITAR = doubleArrayOf(1.0, 0.6, 0.4, 0.25, 0.15, 0.1)
    }
}
