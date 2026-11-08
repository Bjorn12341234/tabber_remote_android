package com.tabberspak.app.tuner

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

// Ported line for line from the iPhone app's apple/TabberSpak/Tuner/BiquadFilter.swift, which is the
// Viga Tuner's unchanged: the same pitch detection in Tabber Spak's Tuner on both phones (plan: TR32).
// Plain Kotlin, no Android API, so it is tested on the JVM.

/**
 * Simple biquad filter (low-pass / high-pass) using Direct Form II Transposed.
 * Replaces the JUCE-dependent Biquad from the VST plugin.
 */
class BiquadFilter {
    enum class FilterType { LOW_PASS, HIGH_PASS }

    // Coefficients
    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0

    // State (Direct Form II Transposed)
    private var z1 = 0.0
    private var z2 = 0.0

    fun setCoefficients(type: FilterType, sampleRate: Double, frequency: Double, q: Double) {
        val omega = 2.0 * PI * frequency / sampleRate
        val sinOmega = sin(omega)
        val cosOmega = cos(omega)
        val alpha = sinOmega / (2.0 * q)

        val a0: Double

        when (type) {
            FilterType.LOW_PASS -> {
                b1 = 1.0 - cosOmega
                b0 = b1 / 2.0
                b2 = b0
                a0 = 1.0 + alpha
                a1 = -2.0 * cosOmega
                a2 = 1.0 - alpha
            }
            FilterType.HIGH_PASS -> {
                b1 = -(1.0 + cosOmega)
                b0 = (1.0 + cosOmega) / 2.0
                b2 = b0
                a0 = 1.0 + alpha
                a1 = -2.0 * cosOmega
                a2 = 1.0 - alpha
            }
        }

        // Normalize
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0

        z1 = 0.0
        z2 = 0.0
    }

    fun process(input: Float): Float {
        val x = input.toDouble()
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y.toFloat()
    }

    fun reset() {
        z1 = 0.0
        z2 = 0.0
    }
}
