// From the Viga Tuner iPhone app (viga_guitar_tuner/ios/VigaTuner/DSP/YinPitchDetector.swift at a3527b5),
// unchanged: the same pitch detection in Tabber Spak's Tuner (plan: TR32).

import Foundation

/// Result of a pitch detection cycle
struct PitchResult {
    var frequency: Float = 0.0
    var clarity: Float = 0.0  // 0.0 to 1.0
    var isSilent: Bool = true
}

/// YIN pitch detection algorithm with 4x decimation and median filtering.
/// Port of the C++ implementation from the VST plugin.
final class YinPitchDetector {

    // MARK: - Configuration

    private var sampleRate: Double = 48000.0  // Effective (post-decimation)
    private var bufferSize: Int = 512         // Post-decimation window
    private let decimationFactor = 4
    private let threshold: Float = 0.15
    private let medianWindowSize = 5

    // MARK: - Filters

    private var highPass = BiquadFilter()
    private var lowPass = BiquadFilter()
    private var lowPass2 = BiquadFilter()

    // MARK: - State

    private var inputBuffer: [Float] = []
    private var differenceBuffer: [Float] = []
    private var bufferWritePos = 0
    private var sampleCounter = 0
    private var pitchHistory: [Float] = []
    private var lastResult = PitchResult()

    // MARK: - Constants

    private static let lowPassCutoffHz: Double = 5000.0
    private static let highPassCutoffHz: Double = 20.0
    private static let butterworthQ: Double = 0.7071068
    private var silenceThresholdRms: Float = 0.00001

    // MARK: - Init

    init() {
        prepare(sampleRate: 48000.0, blockSize: 2048)
    }

    // MARK: - Public API

    func prepare(sampleRate inputSampleRate: Double, blockSize: Int) {
        sampleRate = inputSampleRate / Double(decimationFactor)
        bufferSize = blockSize / decimationFactor

        // Ensure divisible by 4 for 75% overlap
        if bufferSize % 4 != 0 {
            bufferSize += 4 - (bufferSize % 4)
        }

        inputBuffer = [Float](repeating: 0.0, count: bufferSize)
        differenceBuffer = [Float](repeating: 0.0, count: bufferSize / 2)
        bufferWritePos = 0
        sampleCounter = 0
        pitchHistory.removeAll()
        lastResult = PitchResult()

        // Filters run at full sample rate (before decimation)
        highPass.setCoefficients(type: .highPass, sampleRate: inputSampleRate,
                                 frequency: Self.highPassCutoffHz, q: Self.butterworthQ)
        lowPass.setCoefficients(type: .lowPass, sampleRate: inputSampleRate,
                                frequency: Self.lowPassCutoffHz, q: Self.butterworthQ)
        lowPass2.setCoefficients(type: .lowPass, sampleRate: inputSampleRate,
                                 frequency: Self.lowPassCutoffHz, q: Self.butterworthQ)
    }

    /// Push samples into the detector. Returns true when a new pitch estimate is ready.
    @discardableResult
    func process(_ input: UnsafeBufferPointer<Float>) -> Bool {
        var resultReady = false

        for i in 0..<input.count {
            var s = input[i]

            // Sanitize NaN/Inf
            if !s.isFinite { s = 0.0 }

            s = highPass.process(s)
            s = lowPass.process(s)
            s = lowPass2.process(s)

            // Decimate: keep every Nth sample
            if sampleCounter % decimationFactor == 0 {
                inputBuffer[bufferWritePos] = s
                bufferWritePos += 1

                if bufferWritePos >= bufferSize {
                    executeYin()
                    resultReady = true

                    // Shift buffer by hop size (75% overlap -> hop = 25%)
                    let hop = bufferSize / 4
                    let keep = bufferSize - hop
                    inputBuffer.withUnsafeMutableBufferPointer { ptr in
                        ptr.baseAddress!.update(from: ptr.baseAddress! + hop, count: keep)
                    }
                    bufferWritePos = keep
                }
            }
            sampleCounter += 1
        }

        return resultReady
    }

    /// Convenience overload for Array input
    @discardableResult
    func process(_ input: [Float]) -> Bool {
        input.withUnsafeBufferPointer { process($0) }
    }

    func getLatestResult() -> PitchResult {
        lastResult
    }

    func setSilenceThreshold(_ threshold: Float) {
        silenceThresholdRms = threshold
    }

    // MARK: - YIN Core

    private func executeYin() {
        // Silence gate (RMS)
        var sumSq: Float = 0.0
        for s in inputBuffer { sumSq += s * s }
        if (sumSq / Float(bufferSize)) < silenceThresholdRms {
            lastResult = PitchResult(frequency: 0.0, clarity: 0.0, isSilent: true)
            pitchHistory.removeAll()
            return
        }

        // 1. Difference function
        calculateDifference()

        // 2. Cumulative mean normalized difference
        cumulativeMeanNormalizedDifference()

        // 3. Absolute threshold
        let tau = absoluteThreshold()

        // 4. Parabolic interpolation & output
        if tau != -1 {
            let refinedTau = parabolicInterpolation(tau: tau)
            let freq = Float(sampleRate / Double(refinedTau))

            if freq >= 20.0 && freq <= 5000.0 {
                pitchHistory.append(freq)
                if pitchHistory.count > medianWindowSize {
                    pitchHistory.removeFirst()
                }

                let sorted = pitchHistory.sorted()
                let medianFreq = sorted[sorted.count / 2]

                lastResult = PitchResult(
                    frequency: medianFreq,
                    clarity: 1.0 - differenceBuffer[tau],
                    isSilent: false
                )
            } else {
                lastResult = PitchResult(frequency: 0.0, clarity: 0.0, isSilent: true)
                pitchHistory.removeAll()
            }
        } else {
            lastResult = PitchResult(frequency: 0.0, clarity: 0.0, isSilent: true)
            pitchHistory.removeAll()
        }
    }

    private func calculateDifference() {
        let halfSize = bufferSize / 2
        for tau in 0..<halfSize {
            var sum: Float = 0.0
            for j in 0..<halfSize {
                let delta = inputBuffer[j] - inputBuffer[j + tau]
                sum += delta * delta
            }
            differenceBuffer[tau] = sum
        }
    }

    private func cumulativeMeanNormalizedDifference() {
        let halfSize = bufferSize / 2
        differenceBuffer[0] = 1.0
        var runningSum: Float = 0.0

        for tau in 1..<halfSize {
            runningSum += differenceBuffer[tau]
            if runningSum == 0 {
                differenceBuffer[tau] = 1.0
            } else {
                differenceBuffer[tau] *= Float(tau) / runningSum
            }
        }
    }

    private func absoluteThreshold() -> Int {
        let halfSize = bufferSize / 2
        var tau = 2

        while tau < halfSize {
            if differenceBuffer[tau] < threshold {
                while tau + 1 < halfSize && differenceBuffer[tau + 1] < differenceBuffer[tau] {
                    tau += 1
                }
                return tau
            }
            tau += 1
        }
        return -1
    }

    private func parabolicInterpolation(tau: Int) -> Float {
        if tau <= 0 || tau >= differenceBuffer.count - 1 {
            return Float(tau)
        }

        let s0 = differenceBuffer[tau - 1]
        let s1 = differenceBuffer[tau]
        let s2 = differenceBuffer[tau + 1]

        let denom = 2.0 * s1 - s2 - s0
        if abs(denom) < 1e-6 { return Float(tau) }

        let adjustment = (s2 - s0) / (2.0 * denom)
        return Float(tau) + adjustment
    }
}
