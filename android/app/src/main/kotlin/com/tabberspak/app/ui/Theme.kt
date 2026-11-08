package com.tabberspak.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Tabber Studio's design language on the phone, as the iPhone's Theme.swift: every colour is
 * Tabber Studio's own (ui/design_tokens.py, ui/theme.py, core/models.py). Surfaces get lighter as
 * they come closer; no shadows or glows. Teal marks the one selected thing, red means recording,
 * amber marks the playhead. Words are sentence case; only Studio's readout labels are capitals.
 */
object Studio {
    // Surfaces, lighter = closer
    val bg0 = Color(0xFF121219) // wells, the readout
    val bg1 = Color(0xFF1D1D2B) // the screen
    val bg2 = Color(0xFF262638) // track cards, strips, the take card
    val bg3 = Color(0xFF30304A) // buttons
    val bgOn = Color(0xFF3D3D5C) // a toggle that is on
    val edge = Color.White.copy(alpha = 0.06f)
    val dashes = Color(0xFF363643)
    val editor = Color(0xFF22223B) // the tab editor's paper
    val staffLine = Color(0xFF5C5C7C)
    val barLine = Color(0xFF6E6E90)

    // Ink
    val text1 = Color(0xFFECECF3)
    val text2 = Color(0xFFB0B0C4)
    val text3 = Color(0xFF8585A0)

    // Signals
    val accent = Color(0xFF00D4AA) // the one selected thing
    val onAccent = Color(0xFF0D1F1A)
    val record = Color(0xFFFF4D6A) // record arm, recording
    val playhead = Color(0xFFFFB020)
    val solo = Color(0xFFD4A24C)
    val mute = Color(0xFF5D6D90)
    val meterLow = Color(0xFF4CAF7D)
    val meterMid = Color(0xFFFFC107)

    // The fretboard (dark theme): rosewood, nickel frets, a bone nut
    val woodEdge = Color(44, 31, 21)
    val wood = Color(72, 48, 28)
    val woodCentre = Color(85, 61, 40)
    val fret = Color(154, 147, 135)
    val nut = Color(240, 238, 228)
    val string = Color(210, 210, 205)
    val inlay = Color(216, 207, 189).copy(alpha = 0.6f)
    val openNote = Color(0, 180, 130)

    // The piano
    val keyTop = Color(235, 232, 222)
    val keyBottom = Color(215, 212, 200)
    val blackTop = Color(30, 30, 35)
    val blackBottom = Color(50, 50, 55)
    val keyBorder = Color(60, 60, 80)

    // Shape: Studio's small corners, grown a little for fingers.
    val radiusCard = 8.dp
    val radiusControl = 6.dp

    /** Tabber Studio's twelve track colours, for a track that sends none. */
    val tracks = listOf(
        Color(80, 160, 220), Color(100, 190, 100), Color(220, 170, 60), Color(170, 100, 210),
        Color(154, 134, 214), Color(220, 80, 80), Color(220, 130, 70), Color(150, 190, 60),
        Color(200, 100, 160), Color(100, 140, 200), Color(190, 160, 100), Color(210, 200, 80),
    )

    fun track(hex: String?, index: Int): Color = hexColor(hex) ?: tracks[index.mod(tracks.size)]

    fun hexColor(hex: String?): Color? {
        if (hex == null || hex.length != 7 || !hex.startsWith("#")) return null
        val value = hex.substring(1).toLongOrNull(16) ?: return null
        return Color(0xFF000000 or value)
    }

    /** Counters (position, time, levels, frets) are monospaced, as in Studio's transport. */
    fun counter(size: Int = 17, weight: FontWeight = FontWeight.Medium) =
        TextStyle(fontFamily = FontFamily.Monospace, fontWeight = weight, fontSize = size.sp)

    val colors = darkColorScheme(
        primary = accent, onPrimary = onAccent, background = bg1, surface = bg1, onSurface = text1,
        onBackground = text1, surfaceVariant = bg2, onSurfaceVariant = text2, secondary = bg3, onSecondary = text1,
        error = record, outline = text3, surfaceContainer = bg2, surfaceContainerHigh = bg2, surfaceContainerLow = bg1,
    )
}

@Composable
fun StudioTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = Studio.colors, content = content)

/** Tabber Studio's readout labels, POS, TIME and BPM: the only capitals in the app. */
@Composable
fun ReadoutLabel(text: String, color: Color = Studio.text2) {
    Text(text, color = color, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { contentDescription = "" })
}

enum class ButtonKind { NORMAL, PRIMARY, QUIET, DESTRUCTIVE }

/** The app's buttons, as Studio's: flat fills, small corners, plain words. */
@Composable
fun StudioButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.NORMAL,
    enabled: Boolean = true,
    pending: Boolean = false,
    minHeight: Dp = 44.dp,
    content: (@Composable () -> Unit)? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val foreground = when (kind) {
        ButtonKind.NORMAL -> Studio.text1
        ButtonKind.PRIMARY -> Studio.onAccent
        ButtonKind.QUIET -> Studio.text2
        ButtonKind.DESTRUCTIVE -> Studio.record
    }
    val background = when (kind) {
        ButtonKind.NORMAL, ButtonKind.DESTRUCTIVE -> Studio.bg3
        ButtonKind.PRIMARY -> Studio.accent
        ButtonKind.QUIET -> Color.Transparent
    }
    Box(
        modifier
            .sizeIn(minHeight = minHeight, minWidth = 44.dp)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(background)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (pressed || pending) 0.6f else if (enabled) 1f else 0.4f)
            .padding(horizontal = if (kind == ButtonKind.QUIET) 6.dp else 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (content != null) {
            content()
        } else {
            Text(text, color = foreground, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, textAlign = TextAlign.Center)
        }
    }
}

/** A transport toggle as Studio has them (Loop, Count-in, Metro): lit when on. */
@Composable
fun ToggleChip(title: String, isOn: Boolean, modifier: Modifier = Modifier, spoken: String = title, onClick: () -> Unit) {
    Box(
        modifier
            .sizeIn(minHeight = 40.dp)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .background(if (isOn) Studio.bgOn else Color.Transparent)
            .clickable(role = Role.Switch, onClick = onClick)
            .semantics { contentDescription = spoken; selected = isOn }
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, color = if (isOn) Studio.text1 else Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

/** Studio's S and M buttons (and a send's PRE): a word on a small square, lit in its colour when on. */
@Composable
fun LetterButton(
    letter: String,
    isOn: Boolean,
    onColor: Color,
    spoken: String,
    modifier: Modifier = Modifier,
    pending: Boolean = false,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .sizeIn(minWidth = 44.dp, minHeight = 44.dp)
            .clickable(role = Role.Switch, onClick = onClick)
            .semantics { contentDescription = spoken; selected = isOn }
            .alpha(if (pending) 0.5f else 1f),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.sizeIn(minWidth = 34.dp, minHeight = 30.dp).clip(RoundedCornerShape(5.dp)).background(if (isOn) onColor else Studio.bg3)
                .padding(horizontal = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(letter, color = if (isOn) Studio.bg0 else Studio.text2, fontWeight = FontWeight.Bold, fontSize = 15.sp, maxLines = 1)
        }
    }
}

/** Record arm: an open ring, red and filled when armed. */
@Composable
fun ArmButton(armed: Boolean, spoken: String, pending: Boolean = false, onClick: () -> Unit) {
    Box(
        Modifier.size(48.dp).clickable(role = Role.Switch, onClick = onClick)
            .semantics { contentDescription = spoken; selected = armed }.alpha(if (pending) 0.5f else 1f),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(24.dp).clip(CircleShape)
                .background(if (armed) Studio.record else Color.Transparent)
                .border(BorderStroke(2.dp, if (armed) Studio.record else Studio.text2), CircleShape),
        )
    }
}

/** A level meter, as Studio draws one: green, amber near the top, red at the top. */
@Composable
fun LevelMeter(level: Double, modifier: Modifier = Modifier) {
    val fraction = level.coerceIn(0.0, 1.0).toFloat()
    BoxWithConstraints(modifier.clip(RoundedCornerShape(2.dp)).background(Studio.bg0)) {
        Box(
            Modifier.fillMaxHeight().width(maxWidth * fraction).background(
                Brush.horizontalGradient(
                    0f to Studio.meterLow, 0.7f to Studio.meterLow, 0.88f to Studio.meterMid, 1f to Studio.record,
                    endX = constraints.maxWidth.toFloat(),
                ),
            ),
        )
    }
}

/** A card: a surface one step closer, with the accent's edge when it is the selected one. */
fun Modifier.studioCard(selected: Boolean = false): Modifier = this
    .clip(RoundedCornerShape(Studio.radiusCard))
    .background(Studio.bg2)
    .border(BorderStroke(if (selected) 2.dp else 1.dp, if (selected) Studio.accent else Studio.edge), RoundedCornerShape(Studio.radiusCard))

/** A well: a surface one step further, for grouped toggles. */
fun Modifier.studioWell(radius: Dp = Studio.radiusControl + 3.dp): Modifier = this
    .clip(RoundedCornerShape(radius))
    .background(Studio.bg0)

/** Studio's "+ Add Track": a dashed outline in the muted text, never the accent. */
@Composable
fun GhostButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier
            .sizeIn(minHeight = 48.dp)
            .clip(RoundedCornerShape(Studio.radiusControl))
            .border(BorderStroke(1.5.dp, Studio.dashes), RoundedCornerShape(Studio.radiusControl))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else 0.4f)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = Studio.text2, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
    }
}

/** A row of chips in a well, as Studio groups its transport toggles. */
@Composable
fun ChipWell(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.fillMaxWidth().studioWell().padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

object Format {
    /** Tabber Studio's position: "25 : 1". */
    fun position(bar: Int, beat: Int): String = "$bar : $beat"

    /** m:ss, for a take or a recording. */
    fun clock(seconds: Double): String {
        val whole = seconds.toInt().coerceAtLeast(0)
        return "${whole / 60}:" + String.format(java.util.Locale.ROOT, "%02d", whole % 60)
    }

    /** "42 seconds", "1 minute 5 seconds", as the iPhone says it. */
    fun length(seconds: Double): String {
        val whole = maxOf(1, Math.round(seconds).toInt())
        val minutes = whole / 60
        val rest = whole % 60
        val s = if (rest == 1) "1 second" else "$rest seconds"
        if (minutes == 0) return s
        val m = if (minutes == 1) "1 minute" else "$minutes minutes"
        return if (rest == 0) m else "$m $s"
    }

    /** A fader's level: "+0.0", "-12.0", "-∞". */
    fun db(value: Double?): String {
        value ?: return "-∞"
        return (if (value >= 0) "+" else "") + String.format(java.util.Locale.ROOT, "%.1f", value)
    }

    val noteNames = listOf("C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B")

    /** A MIDI note's name: "E2", "C♯4". */
    fun note(pitch: Int): String = "${noteNames[pitch.mod(12)]}${Math.floorDiv(pitch, 12) - 1}"

    /** A note value in words, for TalkBack. */
    fun value(value: Int): String = when (value) {
        1 -> "Whole note"
        2 -> "Half note"
        4 -> "Quarter note"
        8 -> "Eighth note"
        16 -> "Sixteenth note"
        else -> "Thirty-second note"
    }
}
