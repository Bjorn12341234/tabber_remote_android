import AVFoundation
import Observation
import RemoteKit

/// The microphone's pitch, measured on the audio thread by the Viga Tuner's
/// detector. Only the tap's thread feeds it; the lock guards the result the
/// main actor reads.
final class PitchTap: @unchecked Sendable {
    private let detector = YinPitchDetector()
    private let lock = NSLock()
    private var latest = PitchResult()

    func prepare(sampleRate: Double, blockSize: Int) {
        lock.lock(); defer { lock.unlock() }
        detector.prepare(sampleRate: sampleRate, blockSize: blockSize)
        latest = PitchResult()
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        lock.lock(); defer { lock.unlock() }
        if detector.process(samples) { latest = detector.getLatestResult() }
    }

    func read() -> PitchResult {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Listen to the microphone. The tap's block is made here, outside the
    /// main actor: AVAudioEngine calls it on its audio thread, and under
    /// Swift 6 a block made in main-actor code carries a main-actor check
    /// that stopped the app on the first buffer (TestFlight build 3, the
    /// owner's iPhone, 7 Nov 2026).
    func install(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [self] buffer, _ in feed(buffer) }
    }
}

/// Tabber Tuner (plan: TR32): what the instrument plays against the chosen
/// track's strings, from the phone's microphone. The sound never leaves the
/// phone and nothing is recorded.
@MainActor
@Observable
final class TunerModel {
    enum Access: Equatable { case unknown, granted, denied }

    struct Reading: Equatable {
        /// The note heard, or the string it is closest to.
        var note: String
        var octave: Int
        /// Off by this much: negative is flat.
        var cents: Double
        var frequency: Double
        /// Which string of the tuning (1 is the highest), when one is close.
        var string: Int?
    }

    private(set) var access: Access = .unknown
    private(set) var listening = false
    private(set) var reading: Reading?
    /// The open strings, highest first: the chosen track's, or standard guitar.
    var tuning: [Int] = [64, 59, 55, 50, 45, 40]
    var reference = 440.0
    /// Within this many cents the note is in tune.
    static let inTune = 3.0

    private var engine: AVAudioEngine?
    private let tap = PitchTap()
    private var poll: Task<Void, Never>?
    private var smoothed: (string: Int?, midi: Int, cents: Double)?
    private var demoStart = Date.now

    init() {
        access = Self.currentAccess()
    }

    private static func currentAccess() -> Access {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    /// Start listening: the microphone, or in the demo a guitar being tuned.
    func start(demo: Bool) async {
        guard !listening else { return }
        if demo {
            access = .granted
            demoStart = .now
            listening = true
            poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.update(self?.simulated() ?? PitchResult())
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            return
        }
        if access == .unknown {
            access = await AVAudioApplication.requestRecordPermission() ? .granted : .denied
        }
        guard access == .granted else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // No microphone to listen to (another app holds it, or no input
            // route): a tap on it would stop the app, so the tuner just waits.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            // The detector decimates by 4 and looks for periods up to half its
            // window, so 1024 samples at 48 kHz heard nothing below about 94 Hz:
            // no low E (82.4 Hz), no bass. 4096 hears down to about 23 Hz, a
            // five-string bass's low B (30.9 Hz) included (found porting the
            // app to Android, 2026-11-09).
            tap.prepare(sampleRate: format.sampleRate, blockSize: 4096)
            tap.install(on: input, format: format)
            try engine.start()
            self.engine = engine
            listening = true
            poll = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.update(self.tap.read())
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        engine = nil
        listening = false
        reading = nil
        smoothed = nil
    }

    /// A detected pitch as the tuner shows it: the nearest string when one is
    /// within a semitone, else the nearest note; the cents smoothed while the
    /// target holds.
    func update(_ result: PitchResult) {
        guard !result.isSilent, result.frequency > 20, result.clarity > 0.5 else {
            reading = nil
            smoothed = nil
            return
        }
        let heard = 69 + 12 * log2(Double(result.frequency) / reference)
        let nearest = tuning.enumerated().min { abs(Double($0.element) - heard) < abs(Double($1.element) - heard) }
        let string: Int?, midi: Int
        if let nearest, abs(Double(nearest.element) - heard) <= 1.0 {
            (string, midi) = (nearest.offset + 1, nearest.element)
        } else {
            (string, midi) = (nil, Int(heard.rounded()))
        }
        let raw = (heard - Double(midi)) * 100
        var cents = raw
        if let last = smoothed, last.string == string, last.midi == midi { cents = last.cents + (raw - last.cents) * 0.35 }
        smoothed = (string, midi, cents)
        reading = Reading(note: Format.noteNames[((midi % 12) + 12) % 12], octave: midi / 12 - 1,
                          cents: cents, frequency: Double(result.frequency), string: string)
    }

    /// The demo: each string in turn, starting flat and settling in tune.
    private func simulated() -> PitchResult {
        let elapsed = Date.now.timeIntervalSince(demoStart)
        let strings = tuning.reversed().map { $0 }
        let index = Int(elapsed / 4) % max(1, strings.count)
        let phase = elapsed.truncatingRemainder(dividingBy: 4)
        let cents = -28 * exp(-phase * 1.6) + 1.2 * sin(elapsed * 5)
        let midi = Double(strings[index]) + cents / 100
        return PitchResult(frequency: Float(reference * pow(2, (midi - 69) / 12)), clarity: 0.95, isSilent: false)
    }
}
