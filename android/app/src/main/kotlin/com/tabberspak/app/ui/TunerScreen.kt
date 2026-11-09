package com.tabberspak.app.ui

import kotlinx.coroutines.delay
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.mutableStateOf
import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.tabberspak.app.AppModel
import com.tabberspak.app.tuner.Microphone
import com.tabberspak.app.tuner.MicrophoneAccess
import com.tabberspak.app.tuner.TunerModel
import kotlin.math.abs

/**
 * Tabber Tuner, as the iPhone's TunerScreen.swift: the note the instrument plays, how far off it
 * is, and which of the chosen track's strings it is. It works with or without a computer. It
 * listens only while it is on screen with the app in front, and never in the demo, where a guitar
 * is tuned string by string instead.
 */
@Composable
fun TunerScreen(model: AppModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val source = TunerModel.source(model.state.tracks)
    val tuner = remember {
        TunerModel(scope, source.tuning, MicrophoneAccess.current(context)) { tap -> Microphone.start(context, tap) }
    }
    LaunchedEffect(source.tuning) { tuner.tuning = source.tuning }

    // On screen means the tab shown and the app resumed: leaving either closes the microphone.
    // Back from Settings, the answer there may have changed.
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val onScreen = lifecycle.isAtLeast(Lifecycle.State.RESUMED)
    LaunchedEffect(onScreen) {
        if (onScreen && !model.isDemo) tuner.access = MicrophoneAccess.current(context)
    }
    val listen = onScreen && (model.isDemo || tuner.access == TunerModel.Access.GRANTED)
    DisposableEffect(listen, model.isDemo) {
        if (listen) tuner.start(demo = model.isDemo)
        onDispose { tuner.stop() }
    }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        tuner.access = MicrophoneAccess.answered(context, granted)
    }

    // The iPhone's Tuner has no take slot: it is the one screen about the phone, not the computer.
    ScreenScaffold(model, "Tuner", takeSlot = false) {
        when {
            model.isDemo || tuner.access == TunerModel.Access.GRANTED -> Tuning(tuner, source.name)
            tuner.access == TunerModel.Access.DENIED -> Ask(
                "Tabber Spak can't hear your instrument. Turn on the microphone for Tabber Spak in Settings.",
                "Open Settings",
            ) { openSettings(context) }
            else -> Ask(
                "The tuner listens to your instrument through this phone's microphone. Nothing is recorded, and the sound never leaves the phone.",
                "Start tuning",
            ) { ask.launch(Manifest.permission.RECORD_AUDIO) }
        }
    }
}

@Composable
private fun Tuning(tuner: TunerModel, source: String) {
    val reading = tuner.reading
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TunerDial(reading, Modifier.fillMaxWidth().height(300.dp))
        StringsRow(tuner.tuning, lit = reading?.string, inTune = abs(reading?.cents ?: 99.0) <= TunerModel.IN_TUNE)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(reading?.hertz ?: " ", style = Studio.counter(13), color = Studio.text2, modifier = Modifier.clearAndSetSemantics {})
            Text(
                "$source, A4 = ${tuner.reference.toInt()} Hz", color = Studio.text2, fontSize = 13.sp,
                modifier = Modifier.testTag("tuner-strings"),
            )
        }
    }
}

/** Before the system asks, or after a refusal: one plain sentence and the one thing to do. */
@Composable
private fun Ask(text: String, button: String, action: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(text, color = Studio.text2, fontSize = 17.sp)
        StudioButton(button, onClick = action, kind = ButtonKind.PRIMARY, modifier = Modifier.testTag("tuner-start"))
    }
}

/** The app's page in the phone's Settings, where the microphone is allowed. */
private fun openSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}

/**
 * The note, and a needle on a cents scale from -50 to +50: teal once it is within three cents.
 * Drawn, at the iPhone's sizes in dp; it tells TalkBack the note and how far off it is.
 */
@Composable
private fun TunerDial(reading: TunerModel.Reading?, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    // TalkBack hears the reading at most once a second, as VoiceOver reads a value that updates
    // frequently: it speaks each change of the focused dial, and the needle changes 20 times a
    // second. The needle itself moves at full speed.
    val latest by rememberUpdatedState(reading?.spoken ?: "Play a string")
    var spoken by remember { mutableStateOf(latest) }
    LaunchedEffect(Unit) {
        while (true) {
            spoken = latest
            delay(1000)
        }
    }
    Canvas(modifier.semantics { contentDescription = "Tuner"; stateDescription = spoken }.testTag("tuner-dial")) {
        val inTune = reading?.inTune ?: false
        val ink = if (inTune) Studio.accent else Studio.text1
        val middle = size.width / 2
        // The note, the one large thing on the screen
        if (reading != null) {
            val note = label(measurer, reading.note, 120, FontWeight.SemiBold, ink)
            drawCentred(note, middle, 92.dp.toPx())
            val octave = label(measurer, "${reading.octave}", 30, FontWeight.SemiBold, Studio.text2)
            drawText(octave, topLeft = Offset(middle + note.size.width / 2f + 6.dp.toPx(), 128.dp.toPx() - octave.size.height / 2f))
            drawCentred(label(measurer, reading.words, 17, FontWeight.SemiBold, if (inTune) Studio.accent else Studio.text2), middle, 178.dp.toPx())
        } else {
            drawCentred(label(measurer, "Play a string", 22, FontWeight.SemiBold, Studio.text2), middle, 100.dp.toPx())
        }
        // The scale
        val left = 12.dp.toPx()
        val right = size.width - 12.dp.toPx()
        val base = 250.dp.toPx()
        fun x(cents: Double): Float = left + (right - left) * ((cents + 50) / 100).toFloat()
        drawRoundRect(
            Studio.accent.copy(alpha = 0.16f), topLeft = Offset(x(-TunerModel.IN_TUNE), base - 34.dp.toPx()),
            size = Size(x(TunerModel.IN_TUNE) - x(-TunerModel.IN_TUNE), 40.dp.toPx()), cornerRadius = CornerRadius(3.dp.toPx()),
        )
        for (cents in -50..50 step 5) {
            val major = cents % 25 == 0
            val height = (if (cents == 0) 40 else if (major) 24 else 12).dp.toPx()
            drawRect(
                if (cents == 0) Studio.accent else Studio.staffLine,
                topLeft = Offset(x(cents.toDouble()) - 0.75.dp.toPx(), base - height + 6.dp.toPx()), size = Size(1.5.dp.toPx(), height),
            )
            if (major) {
                val text = if (cents > 0) "+$cents" else "$cents"
                drawCentred(label(measurer, text, 11, FontWeight.Medium, Studio.text2, digits = true), x(cents.toDouble()), base + 20.dp.toPx())
            }
        }
        if (reading != null) {
            val needle = x(reading.cents.coerceIn(-50.0, 50.0))
            drawRoundRect(
                ink, topLeft = Offset(needle - 2.5.dp.toPx(), base - 44.dp.toPx()), size = Size(5.dp.toPx(), 54.dp.toPx()),
                cornerRadius = CornerRadius(2.5.dp.toPx()),
            )
        }
    }
}

/** The dial's words at a fixed size, as the iPhone draws them: the drawing does not grow with the text size. */
private fun DrawScope.label(
    measurer: TextMeasurer, text: String, size: Int, weight: FontWeight, color: Color, digits: Boolean = false,
): TextLayoutResult = measurer.measure(
    text, TextStyle(color = color, fontSize = size.dp.toSp(), fontWeight = weight, fontFeatureSettings = if (digits) "tnum" else null),
)

private fun DrawScope.drawCentred(text: TextLayoutResult, x: Float, y: Float) =
    drawText(text, topLeft = Offset(x - text.size.width / 2f, y - text.size.height / 2f))

/** The strings, low to high as they face the player; the one being tuned is lit. */
@Composable
private fun StringsRow(tuning: List<Int>, lit: Int?, inTune: Boolean) {
    Row(Modifier.fillMaxWidth().clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for ((index, pitch) in tuning.withIndex().reversed()) {
            val on = lit == index + 1
            Box(
                Modifier.weight(1f).heightIn(min = 48.dp).clip(RoundedCornerShape(Studio.radiusControl))
                    .background(if (on) (if (inTune) Studio.accent else Studio.text2) else Studio.bg2),
                contentAlignment = Alignment.Center,
            ) {
                Text(Format.noteNames[pitch.mod(12)], style = Studio.counter(17, FontWeight.SemiBold), color = if (on) Studio.onAccent else Studio.text1)
            }
        }
    }
}
