// From the Viga Tuner iPhone app (viga_guitar_tuner/ios/VigaTuner/DSP/BiquadFilter.swift at a3527b5),
// unchanged: the same pitch detection in Tabber Spak's Tuner (plan: TR32).

import Foundation

/// Simple biquad filter (low-pass / high-pass) using Direct Form II Transposed.
/// Replaces the JUCE-dependent Biquad from the VST plugin.
struct BiquadFilter {
    enum FilterType {
        case lowPass
        case highPass
    }

    // Coefficients
    private var b0: Double = 1.0
    private var b1: Double = 0.0
    private var b2: Double = 0.0
    private var a1: Double = 0.0
    private var a2: Double = 0.0

    // State (Direct Form II Transposed)
    private var z1: Double = 0.0
    private var z2: Double = 0.0

    mutating func setCoefficients(type: FilterType, sampleRate: Double, frequency: Double, q: Double) {
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        let a0: Double

        switch type {
        case .lowPass:
            b1 = 1.0 - cosOmega
            b0 = b1 / 2.0
            b2 = b0
            a0 = 1.0 + alpha
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha

        case .highPass:
            b1 = -(1.0 + cosOmega)
            b0 = (1.0 + cosOmega) / 2.0
            b2 = b0
            a0 = 1.0 + alpha
            a1 = -2.0 * cosOmega
            a2 = 1.0 - alpha
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

    mutating func process(_ input: Float) -> Float {
        let x = Double(input)
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return Float(y)
    }

    mutating func reset() {
        z1 = 0.0
        z2 = 0.0
    }
}
