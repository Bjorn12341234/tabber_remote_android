package com.tabberspak.app.tuner

import kotlin.math.abs

// Ported line for line from the iPhone app's apple/TabberSpak/Tuner/YinPitchDetector.swift, which is
// the Viga Tuner's unchanged: the same pitch detection in Tabber Spak's Tuner on both phones (plan:
// TR32). The arithmetic keeps Swift's types (Float samples and sums, Double rates), so both phones
// compute the same numbers. Plain Kotlin, no Android API, so it is tested on the JVM.

/** Result of a pitch detection cycle */
data class PitchResult(
    val frequency: Float = 0.0f,
    val clarity: Float = 0.0f, // 0.0 to 1.0
    val isSilent: Boolean = true,
)

/**
 * YIN pitch detection algorithm with 4x decimation and median filtering.
 * Port of the C++ implementation from the VST plugin.
 */
class YinPitchDetector {

    // Configuration

    private var sampleRate = 48000.0 // Effective (post-decimation)
    private var bufferSize = 512 // Post-decimation window
    private val decimationFactor = 4
    private val threshold = 0.15f
    private val medianWindowSize = 5

    // Filters

    private val highPass = BiquadFilter()
    private val lowPass = BiquadFilter()
    private val lowPass2 = BiquadFilter()

    // State

    private var inputBuffer = FloatArray(0)
    private var differenceBuffer = FloatArray(0)
    private var bufferWritePos = 0
    private var sampleCounter = 0L
    private val pitchHistory = ArrayList<Float>()
    private var lastResult = PitchResult()

    private var silenceThresholdRms = 0.00001f

    init {
        prepare(48000.0, 2048)
    }

    // Public API

    fun prepare(inputSampleRate: Double, blockSize: Int) {
        sampleRate = inputSampleRate / decimationFactor.toDouble()
        bufferSize = blockSize / decimationFactor

        // Ensure divisible by 4 for 75% overlap
        if (bufferSize % 4 != 0) {
            bufferSize += 4 - (bufferSize % 4)
        }

        inputBuffer = FloatArray(bufferSize)
        differenceBuffer = FloatArray(bufferSize / 2)
        bufferWritePos = 0
        sampleCounter = 0
        pitchHistory.clear()
        lastResult = PitchResult()

        // Filters run at full sample rate (before decimation)
        highPass.setCoefficients(BiquadFilter.FilterType.HIGH_PASS, inputSampleRate, HIGH_PASS_CUTOFF_HZ, BUTTERWORTH_Q)
        lowPass.setCoefficients(BiquadFilter.FilterType.LOW_PASS, inputSampleRate, LOW_PASS_CUTOFF_HZ, BUTTERWORTH_Q)
        lowPass2.setCoefficients(BiquadFilter.FilterType.LOW_PASS, inputSampleRate, LOW_PASS_CUTOFF_HZ, BUTTERWORTH_Q)
    }

    /** Push the first [count] samples into the detector. Returns true when a new pitch estimate is ready. */
    fun process(input: FloatArray, count: Int = input.size): Boolean {
        var resultReady = false

        for (i in 0 until count) {
            var s = input[i]

            // Sanitize NaN/Inf
            if (!s.isFinite()) s = 0.0f

            s = highPass.process(s)
            s = lowPass.process(s)
            s = lowPass2.process(s)

            // Decimate: keep every Nth sample
            if (sampleCounter % decimationFactor == 0L) {
                inputBuffer[bufferWritePos] = s
                bufferWritePos += 1

                if (bufferWritePos >= bufferSize) {
                    executeYin()
                    resultReady = true

                    // Shift buffer by hop size (75% overlap -> hop = 25%)
                    val hop = bufferSize / 4
                    val keep = bufferSize - hop
                    inputBuffer.copyInto(inputBuffer, destinationOffset = 0, startIndex = hop, endIndex = hop + keep)
                    bufferWritePos = keep
                }
            }
            sampleCounter += 1
        }

        return resultReady
    }

    fun getLatestResult(): PitchResult = lastResult

    fun setSilenceThreshold(threshold: Float) {
        silenceThresholdRms = threshold
    }

    // YIN Core

    private fun executeYin() {
        // Silence gate (RMS)
        var sumSq = 0.0f
        for (s in inputBuffer) sumSq += s * s
        if ((sumSq / bufferSize.toFloat()) < silenceThresholdRms) {
            lastResult = PitchResult(frequency = 0.0f, clarity = 0.0f, isSilent = true)
            pitchHistory.clear()
            return
        }

        // 1. Difference function
        calculateDifference()

        // 2. Cumulative mean normalized difference
        cumulativeMeanNormalizedDifference()

        // 3. Absolute threshold
        val tau = absoluteThreshold()

        // 4. Parabolic interpolation & output
        if (tau != -1) {
            val refinedTau = parabolicInterpolation(tau)
            val freq = (sampleRate / refinedTau.toDouble()).toFloat()

            if (freq >= 20.0f && freq <= 5000.0f) {
                pitchHistory.add(freq)
                if (pitchHistory.size > medianWindowSize) {
                    pitchHistory.removeAt(0)
                }

                val sorted = pitchHistory.sorted()
                val medianFreq = sorted[sorted.size / 2]

                lastResult = PitchResult(
                    frequency = medianFreq,
                    clarity = 1.0f - differenceBuffer[tau],
                    isSilent = false,
                )
            } else {
                lastResult = PitchResult(frequency = 0.0f, clarity = 0.0f, isSilent = true)
                pitchHistory.clear()
            }
        } else {
            lastResult = PitchResult(frequency = 0.0f, clarity = 0.0f, isSilent = true)
            pitchHistory.clear()
        }
    }

    private fun calculateDifference() {
        val halfSize = bufferSize / 2
        for (tau in 0 until halfSize) {
            var sum = 0.0f
            for (j in 0 until halfSize) {
                val delta = inputBuffer[j] - inputBuffer[j + tau]
                sum += delta * delta
            }
            differenceBuffer[tau] = sum
        }
    }

    private fun cumulativeMeanNormalizedDifference() {
        val halfSize = bufferSize / 2
        differenceBuffer[0] = 1.0f
        var runningSum = 0.0f

        for (tau in 1 until halfSize) {
            runningSum += differenceBuffer[tau]
            if (runningSum == 0.0f) {
                differenceBuffer[tau] = 1.0f
            } else {
                differenceBuffer[tau] *= tau.toFloat() / runningSum
            }
        }
    }

    private fun absoluteThreshold(): Int {
        val halfSize = bufferSize / 2
        var tau = 2

        while (tau < halfSize) {
            if (differenceBuffer[tau] < threshold) {
                while (tau + 1 < halfSize && differenceBuffer[tau + 1] < differenceBuffer[tau]) {
                    tau += 1
                }
                return tau
            }
            tau += 1
        }
        return -1
    }

    private fun parabolicInterpolation(tau: Int): Float {
        if (tau <= 0 || tau >= differenceBuffer.size - 1) {
            return tau.toFloat()
        }

        val s0 = differenceBuffer[tau - 1]
        val s1 = differenceBuffer[tau]
        val s2 = differenceBuffer[tau + 1]

        val denom = 2.0f * s1 - s2 - s0
        if (abs(denom) < 1e-6f) return tau.toFloat()

        val adjustment = (s2 - s0) / (2.0f * denom)
        return tau.toFloat() + adjustment
    }

    // Constants

    private companion object {
        const val LOW_PASS_CUTOFF_HZ = 5000.0
        const val HIGH_PASS_CUTOFF_HZ = 20.0
        const val BUTTERWORTH_Q = 0.7071068
    }
}
