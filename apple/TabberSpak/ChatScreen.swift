import LocalAuthentication
import RemoteKit
import SwiftUI

/// Tabber Studio's chat on the phone (plan: TR30, decision 21): ask in
/// words, see the plan, and Execute it, as the chat bubble on the computer
/// does. The AI and its key stay on the computer. Chat can change the song,
/// so it opens only after Face ID, Touch ID or the passcode, and locks again
/// when the tab or the app is left.
struct ChatScreen: View {
    @Bindable var model: AppModel
    @State private var unlocked = false
    @State private var lockNote: String?
    @State private var draft = ""
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Connected(model: model) {
                if !model.chatAvailable {
                    Unavailable(text: "Update Tabber Studio on \(model.computerName) to use its chat from this phone.")
                } else if !unlocked {
                    ChatLock(note: lockNote) { unlock() }
                } else if let chat = model.state.chat {
                    if chat.available {
                        Conversation(model: model, chat: chat)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                ChatInput(draft: $draft, working: chat.isWorking) { send() }
                            }
                    } else {
                        Unavailable(text: "Set up the AI in Tabber Studio first, in Preferences › AI.")
                    }
                }
            }
            .background(Studio.bg1)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(model.state.undo.undo == nil || !unlocked)
                        .accessibilityLabel(model.state.undo.undo.map { "Undo \($0.label)" } ?? "Undo")
                        .accessibilityIdentifier("undo")
                }
                ToolbarItem(placement: .topBarTrailing) { ComputerChip(model: model) }
            }
            .takeSlot(model: model)
        }
        .onChange(of: phase) { _, now in if now != .active { unlocked = false } }
        .onDisappear { unlocked = false }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.chatSend(text)
        draft = ""
    }

    /// The device owner opens Chat: Face ID or Touch ID, else the passcode.
    /// The demo has no computer behind it, so it opens at once.
    private func unlock() {
        lockNote = nil
        if model.isDemo {
            unlocked = true
            return
        }
        Task {
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                lockNote = "Set a passcode on this iPhone to use Chat."
                return
            }
            do {
                unlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open Chat")
            } catch {
                unlocked = false
            }
        }
    }
}

/// Before Chat opens: why it asks, and the one way in.
private struct ChatLock: View {
    let note: String?
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock")
                .font(.largeTitle)
                .foregroundStyle(Studio.text2)
                .accessibilityHidden(true)
            Text("Chat can change your song on the computer, so it opens only for you.")
                .font(.body)
                .foregroundStyle(Studio.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Studio.text1)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("chat-lock-note")
            }
            Button("Unlock Chat", action: unlock)
                .buttonStyle(.studioPrimary)
                .accessibilityIdentifier("unlock-chat")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The conversation, newest at the bottom, with a waiting plan and "Thinking…".
private struct Conversation: View {
    @Bindable var model: AppModel
    let chat: ChatState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if chat.messages.isEmpty && chat.plan == nil {
                        Text("Ask Tabber Studio for a change to your song, like “mute the drums”. You see the plan, and nothing changes until you tap Execute.")
                            .font(.subheadline)
                            .foregroundStyle(Studio.text2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("chat-hint")
                    }
                    ForEach(chat.messages) { message in
                        MessageRow(message: message)
                    }
                    if let plan = chat.plan {
                        PlanCard(model: model, plan: plan)
                    }
                    if chat.isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(chat.state == "running" ? "Working…" : "Thinking…")
                                .font(.subheadline)
                                .foregroundStyle(Studio.text2)
                            Spacer()
                            Button("Stop") { model.chatStop() }
                                .buttonStyle(.studio)
                                .accessibilityIdentifier("chat-stop")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("chat-thinking")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat) { proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isYou { Spacer(minLength: 48) }
            if !message.isYou, let symbol {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(message.kind == "error" ? Studio.record : Studio.text2)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(message.isYou ? Studio.bg3 : Studio.bg2,
                            in: RoundedRectangle(cornerRadius: Studio.radiusCard, style: .continuous))
            if !message.isYou { Spacer(minLength: 32) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isYou ? "You" : "Tabber Studio"): \(message.text)")
        .accessibilityIdentifier("chat-\(message.from)-\(message.id)")
    }

    private var symbol: String? {
        switch message.kind {
        case "refusal": "hand.raised"
        case "error": "exclamationmark.triangle"
        default: nil
        }
    }
}

/// A plan as the chat bubble shows it: what the AI means to do, its steps,
/// then Execute or Cancel. Nothing changes before Execute.
private struct PlanCard: View {
    @Bindable var model: AppModel
    let plan: ChatPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.text)
                .font(.body)
                .foregroundStyle(Studio.text1)
                .fixedSize(horizontal: false, vertical: true)
            Text("Planned steps")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Studio.text2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step.text)")
                    .font(.subheadline)
                    .foregroundStyle(Studio.text1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Execute") { model.chatConfirm(plan) }
                    .buttonStyle(.studioPrimary)
                    .accessibilityIdentifier("chat-execute")
                Button("Cancel") { model.chatCancel(plan) }
                    .buttonStyle(.studio)
                    .accessibilityIdentifier("chat-cancel")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .studioCard(selected: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-plan")
    }
}

/// The request field: type, or the keyboard's microphone to speak it.
private struct ChatInput: View {
    @Binding var draft: String
    let working: Bool
    let send: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: $draft, prompt: Text("Ask Tabber Studio").foregroundStyle(Studio.text2), axis: .vertical)
                .focused($focused)
                .lineLimit(1...4)
                .font(.body)
                .foregroundStyle(Studio.text1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .studioWell(radius: Studio.radiusCard)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityLabel("Ask Tabber Studio")
                .accessibilityIdentifier("chat-field")
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Studio.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Studio.accent, in: Circle())
            }
            .disabled(working || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(working ? 0.5 : 1)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chat-send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Studio.bg1)
    }

    /// Send, and put the keyboard away so the answer and its plan show.
    private func submit() {
        send()
        focused = false
    }
}
