package com.tabberspak.app.ui

import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.tabberspak.app.AppModel
import com.tabberspak.remotekit.ChatMessage
import com.tabberspak.remotekit.ChatPlan
import com.tabberspak.remotekit.ChatState

/**
 * Tabber Studio's chat on the phone (plan: TR30, decision 21), as the iPhone's ChatScreen.swift:
 * ask in words, see the plan, and Execute it, as the chat bubble on the computer does. The AI and
 * its key stay on the computer. Chat can change the song, so it opens only after the phone's own
 * lock (a fingerprint, the face, or the PIN, pattern or password), and locks again when the tab or
 * the app is left.
 */
@Composable
fun ChatScreen(model: AppModel) {
    val context = LocalContext.current
    var unlocked by remember { mutableStateOf(false) }
    var lockNote by remember { mutableStateOf<String?>(null) }
    var draft by rememberSaveable { mutableStateOf("") }
    // Leaving the app locks it again; leaving the tab ends this screen, and with it the unlock.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) unlocked = false }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    fun send() {
        val text = draft.trim()
        if (text.isEmpty()) return
        model.chatSend(text)
        draft = ""
    }

    ScreenScaffold(model, "Chat", leading = { UndoButton(model, available = unlocked) }) {
        Connected(model) {
            val chat = model.state.chat
            when {
                !model.chatAvailable -> Unavailable("Update Tabber Studio on ${model.computerName} to use its chat from this phone.")
                !unlocked -> ChatLock(lockNote) {
                    lockNote = null
                    // The demo has no computer behind it, so it opens at once.
                    if (model.isDemo) unlocked = true else unlock(context, onOpen = { unlocked = true }, onNote = { lockNote = it })
                }
                chat == null -> Unit
                !chat.available -> Unavailable("Set up the AI in Tabber Studio first, in Preferences › AI.")
                else -> Column(Modifier.fillMaxSize()) {
                    Conversation(model, chat, Modifier.weight(1f))
                    ChatInput(draft, { draft = it }, working = chat.isWorking, send = ::send)
                }
            }
        }
    }
}

/**
 * The phone's owner opens Chat: a fingerprint or the face, else the screen lock's PIN, pattern or
 * password, as the iPhone asks for Face ID, Touch ID or the passcode.
 */
private fun unlock(context: Context, onOpen: () -> Unit, onNote: (String) -> Unit) {
    val keyguard = context.getSystemService(KeyguardManager::class.java)
    if (keyguard?.isDeviceSecure != true) {
        onNote("Set a screen lock on this phone to use Chat.")
        return
    }
    val builder = BiometricPrompt.Builder(context).setTitle("Open Chat")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
    } else {
        @Suppress("DEPRECATION")
        builder.setDeviceCredentialAllowed(true)
    }
    builder.build().authenticate(
        CancellationSignal(), context.mainExecutor,
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onOpen()
        },
    )
}

/** Before Chat opens: why it asks, and the one way in. */
@Composable
private fun ChatLock(note: String?, unlock: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = Studio.text2, modifier = Modifier.size(36.dp))
        Text(
            "Chat can change your song on the computer, so it opens only for you.",
            color = Studio.text2, fontSize = 17.sp, textAlign = TextAlign.Center,
        )
        if (note != null) {
            Text(note, color = Studio.text1, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.testTag("chat-lock-note"))
        }
        StudioButton("Unlock Chat", onClick = unlock, kind = ButtonKind.PRIMARY, modifier = Modifier.testTag("unlock-chat"))
    }
}

/** The conversation, newest at the bottom, with a waiting plan and "Thinking…". */
@Composable
private fun Conversation(model: AppModel, chat: ChatState, modifier: Modifier) {
    val list = rememberLazyListState()
    LaunchedEffect(chat) {
        val last = list.layoutInfo.totalItemsCount - 1
        if (last >= 0) list.animateScrollToItem(last)
    }
    LazyColumn(
        state = list, modifier = modifier.fillMaxWidth().testTag("chat-conversation"),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (chat.messages.isEmpty() && chat.plan == null) {
            item {
                Text(
                    "Ask Tabber Studio for a change to your song, like “mute the drums”. You see the plan, and nothing changes until you tap Execute.",
                    color = Studio.text2, fontSize = 15.sp, modifier = Modifier.padding(vertical = 8.dp).testTag("chat-hint"),
                )
            }
        }
        items(chat.messages, key = { "message-${it.id}" }) { message -> MessageRow(message) }
        chat.plan?.let { plan -> item(key = "plan-${plan.id}") { PlanCard(model, plan) } }
        if (chat.isWorking) {
            item(key = "working") {
                Row(
                    Modifier.fillMaxWidth().testTag("chat-thinking"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircularProgressIndicator(color = Studio.text2, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                    Text(if (chat.state == "running") "Working…" else "Thinking…", color = Studio.text2, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    StudioButton("Stop", onClick = model::chatStop, modifier = Modifier.testTag("chat-stop"))
                }
            }
        }
    }
}

@Composable
private fun MessageRow(message: ChatMessage) {
    val symbol = when (message.kind) {
        "refusal" -> Icons.Outlined.PanTool
        "error" -> Icons.Outlined.WarningAmber
        else -> null
    }
    Row(
        Modifier.fillMaxWidth()
            .clearAndSetSemantics {
                contentDescription = "${if (message.isYou) "You" else "Tabber Studio"}: ${message.text}"
                testTag = "chat-${message.from}-${message.id}"
            },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        if (message.isYou) Spacer(Modifier.width(48.dp).weight(1f, fill = false))
        if (!message.isYou && symbol != null) {
            Icon(
                symbol, contentDescription = null, tint = if (message.kind == "error") Studio.record else Studio.text2,
                modifier = Modifier.padding(top = 2.dp).size(18.dp),
            )
        }
        Text(
            message.text, color = Studio.text1, fontSize = 17.sp,
            modifier = Modifier.weight(1f, fill = false).clip(RoundedCornerShape(Studio.radiusCard))
                .background(if (message.isYou) Studio.bg3 else Studio.bg2).padding(horizontal = 12.dp, vertical = 8.dp),
        )
        if (!message.isYou) Spacer(Modifier.width(32.dp))
    }
}

/** A plan as the chat bubble shows it: what the AI means to do, its steps, then Execute or Cancel. Nothing changes before Execute. */
@Composable
private fun PlanCard(model: AppModel, plan: ChatPlan) {
    Column(
        Modifier.fillMaxWidth().studioCard(selected = true).padding(14.dp).testTag("chat-plan"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(plan.text, color = Studio.text1, fontSize = 17.sp)
        Text("Planned steps", color = Studio.text2, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        plan.steps.forEachIndexed { index, step -> Text("${index + 1}. ${step.text}", color = Studio.text1, fontSize = 15.sp) }
        Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StudioButton("Execute", onClick = { model.chatConfirm(plan) }, kind = ButtonKind.PRIMARY, modifier = Modifier.testTag("chat-execute"))
            StudioButton("Cancel", onClick = { model.chatCancel(plan) }, modifier = Modifier.testTag("chat-cancel"))
        }
    }
}

/** The request field: type, or the keyboard's microphone to speak it. */
@Composable
private fun ChatInput(draft: String, onDraft: (String) -> Unit, working: Boolean, send: () -> Unit) {
    val focus = LocalFocusManager.current
    // Send, and put the keyboard away so the answer and its plan show.
    fun submit() {
        send()
        focus.clearFocus()
    }
    val canSend = !working && draft.isNotBlank()
    Row(
        Modifier.fillMaxWidth().background(Studio.bg1).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TextField(
            value = draft, onValueChange = onDraft, maxLines = 4,
            placeholder = { Text("Ask Tabber Studio", color = Studio.text2) },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { submit() }),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Studio.bg0, unfocusedContainerColor = Studio.bg0,
                focusedTextColor = Studio.text1, unfocusedTextColor = Studio.text1, cursorColor = Studio.text1,
                focusedIndicatorColor = Studio.bg0, unfocusedIndicatorColor = Studio.bg0,
            ),
            shape = RoundedCornerShape(Studio.radiusCard),
            modifier = Modifier.weight(1f).semantics { contentDescription = "Ask Tabber Studio" }.testTag("chat-field"),
        )
        Box(
            Modifier.size(44.dp).clip(CircleShape).background(Studio.accent).alpha(if (working) 0.5f else 1f)
                .clickable(enabled = canSend, role = Role.Button) { submit() }
                .semantics { contentDescription = "Send" }.testTag("chat-send"),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.ArrowUpward, contentDescription = null, tint = Studio.onAccent)
        }
    }
}
