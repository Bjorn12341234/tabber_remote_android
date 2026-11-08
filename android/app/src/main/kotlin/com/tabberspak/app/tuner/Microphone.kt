package com.tabberspak.app.tuner

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Process
import com.tabberspak.app.Prefs

/**
 * The phone's microphone for the tuner, as the iPhone's AVAudioEngine input tap: AudioRecord on a
 * thread of its own, mono, at the microphone's own rate, with the phone's voice processing off (as
 * iOS's measurement mode). Each buffer goes to the pitch detector and is overwritten by the next:
 * nothing is recorded, kept or sent anywhere. [stop] ends it, and the thread closes the microphone
 * itself within one buffer, so the main thread never waits for it.
 */
class Microphone private constructor(
    private val context: Context,
    private val tap: PitchTap,
    /** The microphone before this one, still closing: this one opens after it. */
    private val previous: Thread?,
) {
    @Volatile private var running = true
    private val thread = Thread(::listen, "Tabber Tuner")

    fun stop() {
        running = false
    }

    private class Input(val record: AudioRecord, val float: Boolean)

    private fun listen() {
        // An exception left on any thread ends an Android app: whatever stops the microphone (the
        // permission taken back, the input gone), the tuner just waits, as on the iPhone.
        try {
            previous?.join(1000)
            if (!running) return
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val input = open() ?: return
            try {
                hear(input)
            } finally {
                runCatching { input.record.stop() }
                input.record.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun hear(input: Input) {
        val record = input.record
        val rate = record.sampleRate.toDouble()
        tap.prepare(rate, TunerModel.blockSize(rate))
        record.startRecording()
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) return
        val samples = FloatArray(READ_FRAMES)
        val shorts = if (input.float) null else ShortArray(READ_FRAMES)
        while (running) {
            val count = if (shorts == null) {
                record.read(samples, 0, READ_FRAMES, AudioRecord.READ_BLOCKING)
            } else {
                record.read(shorts, 0, READ_FRAMES, AudioRecord.READ_BLOCKING).also { n ->
                    for (i in 0 until n) samples[i] = shorts[i] / 32768f
                }
            }
            if (count < 0) return // the microphone went away (the audio server restarted)
            if (count > 0) tap.feed(samples, count)
        }
    }

    /** Float at the microphone's own rate; else 16-bit; else 16-bit at 44.1 kHz, which every phone records. */
    private fun open(): Input? {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return null
        val audio = context.getSystemService(AudioManager::class.java)
        // No automatic gain or noise suppression: they bend a held note. UNPROCESSED where the phone
        // has it, else VOICE_RECOGNITION, which Android's compatibility rules keep free of both.
        val source = if (audio?.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true") {
            MediaRecorder.AudioSource.UNPROCESSED
        } else {
            MediaRecorder.AudioSource.VOICE_RECOGNITION
        }
        val guess = audio?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48000
        return attempt(source, AudioFormat.ENCODING_PCM_FLOAT, null, guess)
            ?: attempt(source, AudioFormat.ENCODING_PCM_16BIT, null, guess)
            ?: attempt(MediaRecorder.AudioSource.MIC, AudioFormat.ENCODING_PCM_16BIT, 44100, 44100)
    }

    @SuppressLint("MissingPermission") // open() checks RECORD_AUDIO first
    private fun attempt(source: Int, encoding: Int, rate: Int?, guess: Int): Input? {
        val record = try {
            val format = AudioFormat.Builder().setEncoding(encoding).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .apply { if (rate != null) setSampleRate(rate) }
                .build()
            val bytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
            val least = AudioRecord.getMinBufferSize(rate ?: guess, AudioFormat.CHANNEL_IN_MONO, encoding)
            AudioRecord.Builder().setAudioSource(source).setAudioFormat(format)
                .setBufferSizeInBytes(maxOf(BUFFER_FRAMES * bytes, 2 * least))
                .build()
        } catch (_: Exception) {
            return null // this format is not offered here
        }
        if (record.state != AudioRecord.STATE_INITIALIZED || record.sampleRate <= 0) {
            record.release()
            return null
        }
        return Input(record, encoding == AudioFormat.ENCODING_PCM_FLOAT)
    }

    companion object {
        /** Frames per read, as the iPhone's tap buffer. */
        private const val READ_FRAMES = 1024

        /** AudioRecord's own buffer: room for the thread to be late now and then. */
        private const val BUFFER_FRAMES = 8192

        private var last: Thread? = null

        /** Listen on a new thread, feeding [tap]. Called on the main thread. */
        fun start(context: Context, tap: PitchTap): Microphone {
            val microphone = Microphone(context.applicationContext, tap, last)
            last = microphone.thread
            microphone.thread.start()
            return microphone
        }
    }
}

/**
 * Whether the tuner may listen, as the iPhone's record permission: granted, refused, or not asked
 * yet. Android lets an app ask again after a refusal, iOS does not; this phone remembers the answer,
 * so a refusal shows the way to Settings, as on the iPhone, until the microphone is allowed there.
 */
object MicrophoneAccess {
    private const val REFUSED = "tunerDenied"

    fun current(context: Context): TunerModel.Access {
        val prefs = Prefs(context)
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            if (prefs.bool(REFUSED)) prefs.remove(REFUSED)
            return TunerModel.Access.GRANTED
        }
        return if (prefs.bool(REFUSED)) TunerModel.Access.DENIED else TunerModel.Access.UNKNOWN
    }

    /** The answer to the system's question, kept for next time. */
    fun answered(context: Context, granted: Boolean): TunerModel.Access {
        val prefs = Prefs(context)
        if (granted) prefs.remove(REFUSED) else prefs.set(REFUSED, true)
        return if (granted) TunerModel.Access.GRANTED else TunerModel.Access.DENIED
    }
}
