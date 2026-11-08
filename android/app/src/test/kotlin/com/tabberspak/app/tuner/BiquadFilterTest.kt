package com.tabberspak.app.tuner

import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

/**
 * The detector's filters: a 20 Hz high-pass and two 5 kHz low-passes, second-order Butterworth
 * biquads. Each one's steady gain, measured with a sine, against the analogue Butterworth's
 * through the bilinear transform: 1 / (1 + (tan(w/2) / tan(w0/2))^4).
 */
class BiquadFilterTest {
    private val rate = 48000.0

    /** The gain at [hz] in dB: a sine through the filter, its power over the second second. */
    private fun gain(filter: BiquadFilter, hz: Double): Double {
        var input = 0.0
        var output = 0.0
        for (i in 0 until (2 * rate).toInt()) {
            val x = sin(2 * PI * hz * i / rate).toFloat()
            val y = filter.process(x)
            if (i >= rate) {
                input += x * x
                output += y * y
            }
        }
        return 10 * log10(output / input)
    }

    private fun butterworth(hz: Double, cutoff: Double, highPass: Boolean): Double {
        val ratio = tan(PI * hz / rate) / tan(PI * cutoff / rate)
        return -10 * log10(1 + (if (highPass) 1 / ratio else ratio).pow(4))
    }

    private fun filter(type: BiquadFilter.FilterType, cutoff: Double) =
        BiquadFilter().apply { setCoefficients(type, rate, cutoff, 0.7071068) }

    @Test fun theLowPassKeepsTheStringsAndCutsAboveFiveKilohertz() {
        for (hz in listOf(82.0, 440.0, 1000.0, 5000.0, 10000.0, 15000.0)) {
            val expected = butterworth(hz, 5000.0, highPass = false)
            assertEquals("low-pass at $hz Hz", expected, gain(filter(BiquadFilter.FilterType.LOW_PASS, 5000.0), hz), 0.05)
        }
        assertEquals(-3.01, gain(filter(BiquadFilter.FilterType.LOW_PASS, 5000.0), 5000.0), 0.02) // the cutoff
        assertEquals(0.0, gain(filter(BiquadFilter.FilterType.LOW_PASS, 5000.0), 82.0), 0.01) // the low E untouched
    }

    @Test fun theHighPassKeepsTheStringsAndCutsBelowTwentyHertz() {
        for (hz in listOf(5.0, 10.0, 20.0, 41.0, 82.0, 1000.0)) {
            val expected = butterworth(hz, 20.0, highPass = true)
            assertEquals("high-pass at $hz Hz", expected, gain(filter(BiquadFilter.FilterType.HIGH_PASS, 20.0), hz), 0.05)
        }
        assertEquals(-3.01, gain(filter(BiquadFilter.FilterType.HIGH_PASS, 20.0), 20.0), 0.02)
        assertEquals(-24.1, gain(filter(BiquadFilter.FilterType.HIGH_PASS, 20.0), 5.0), 0.1) // rumble, two octaves down
        assertEquals(0.0, gain(filter(BiquadFilter.FilterType.HIGH_PASS, 20.0), 82.0), 0.05)
    }

    @Test fun resetForgetsTheLastSignal() {
        val low = filter(BiquadFilter.FilterType.LOW_PASS, 5000.0)
        repeat(100) { low.process(1f) }
        low.reset()
        assertEquals(0f, low.process(0f), 0f)
        repeat(100) { low.process(1f) }
        low.setCoefficients(BiquadFilter.FilterType.LOW_PASS, rate, 5000.0, 0.7071068) // new coefficients start clean too
        assertEquals(0f, low.process(0f), 0f)
    }

    @Test fun aNewFilterPassesEverythingThrough() {
        val plain = BiquadFilter()
        for (x in listOf(0.5f, -0.25f, 1f)) assertEquals(x, plain.process(x), 0f)
    }
}
