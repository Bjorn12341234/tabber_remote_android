import Foundation

/// What Tabber Studio shows on the computer (view/1): the editor, Arrange,
/// Tab or Piano Roll, and whether Split is on beside it.
public struct ViewState: Codable, Sendable, Hashable {
    public static let editors = ["arrange", "tab", "piano_roll"]

    /// "arrange", "tab" or "piano_roll"; in Split, the one beside Arrange.
    public var editor: String
    public var split: Bool

    public init(editor: String, split: Bool) { self.editor = editor; self.split = split }
}
