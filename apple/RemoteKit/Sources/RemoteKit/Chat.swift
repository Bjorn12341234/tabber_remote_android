import Foundation

/// One line of the conversation with Tabber Studio's chat (chat/1).
public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var from: String          // "you" or "studio"
    public var kind: String          // "text", "result", "refusal" or "error"
    public var text: String

    public var isYou: Bool { from == "you" }

    public init(id: String, from: String, kind: String, text: String) {
        self.id = id; self.from = from; self.kind = kind; self.text = text
    }
}

/// What the AI means to do, waiting for Execute.
public struct ChatPlan: Codable, Sendable, Hashable, Identifiable {
    public struct Step: Codable, Sendable, Hashable {
        public var text: String
        public init(text: String) { self.text = text }
    }

    public var id: String
    public var text: String
    public var steps: [Step]

    public init(id: String, text: String, steps: [Step]) { self.id = id; self.text = text; self.steps = steps }
}

/// Tabber Studio's chat as the phone sees it: words only. The AI and its key
/// stay on the computer.
public struct ChatState: Codable, Sendable, Hashable {
    /// False when Tabber Studio has no AI set up.
    public var available: Bool
    /// "idle", "thinking", "waiting" (a plan waits for Execute) or "running".
    public var state: String
    public var messages: [ChatMessage]
    public var plan: ChatPlan?

    public var isWorking: Bool { state == "thinking" || state == "running" }

    public init(available: Bool, state: String, messages: [ChatMessage], plan: ChatPlan?) {
        self.available = available; self.state = state; self.messages = messages; self.plan = plan
    }

    /// No plan is an explicit null, as the computer sends it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(available, forKey: .available); try c.encode(state, forKey: .state)
        try c.encode(messages, forKey: .messages); try c.encode(plan, forKey: .plan)
    }
}
