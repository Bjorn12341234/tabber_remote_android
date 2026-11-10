import Foundation
import Testing
@testable import RemoteKit

/// What the phone says when Tabber Studio refuses (spec 10). A `host_error`
/// with a `detail` is Studio's own reason, shown in place of the general
/// "Tabber Studio could not do that.", which the phone showed for every one
/// of them until the Android port found it.
@Suite("Refusals in words")
struct RefusalTests {
    static let general = "Tabber Studio could not do that."

    func hostError(_ data: JSONValue) -> RemoteError {
        RemoteError(code: 1099, message: Self.general, reason: "host_error", data: data)
    }

    @Test func aHostErrorSaysStudiosReason() {
        #expect(hostError(["reason": "host_error", "detail": "The bus was not added."]).sentence == "The bus was not added.")
        #expect(hostError(["reason": "host_error", "detail": "That pitch already sounds in this beat, on another string."])
            .sentence == "That pitch already sounds in this beat, on another string.")
    }

    @Test func withoutAReasonItIsTheGeneralSentence() {
        #expect(hostError(["reason": "host_error"]).sentence == Self.general)
        #expect(hostError(["reason": "host_error", "detail": " \n "]).sentence == Self.general, "spaces are no reason")
        #expect(hostError(["reason": "host_error", "detail": ""]).sentence == Self.general)
        #expect(hostError(["reason": "host_error", "detail": nil]).sentence == Self.general)
        #expect(hostError(["reason": "host_error", "detail": 7]).sentence == Self.general, "nor is a number")
    }

    @Test func aReasonEndsAsASentence() {
        #expect(hostError(["detail": "Insert this instrument on a MIDI/score track"]).sentence
            == "Insert this instrument on a MIDI/score track.", "Studio's words, with the full stop they leave off")
        #expect(hostError(["detail": "  Old Delay failed to load. "]).sentence == "Old Delay failed to load.")
        #expect(hostError(["detail": "Is Old Delay installed?"]).sentence == "Is Old Delay installed?")
        #expect(hostError(["detail": "Old Delay says \u{201C}No licence.\u{201D}"]).sentence
            == "Old Delay says \u{201C}No licence.\u{201D}")
        #expect(hostError(["detail": "Old Delay did not open (it is for an Intel Mac)"]).sentence
            == "Old Delay did not open (it is for an Intel Mac).")
    }

    @Test func aRoutingLoopStillNamesTheLoop() {
        let message = "That route would make a feedback loop."
        let loop = RemoteError(code: 1034, message: message, reason: "routing_loop",
                               data: ["reason": "routing_loop", "path": ["Reverb", "Delay", "Reverb"]])
        #expect(loop.sentence == "That route would make a feedback loop. Reverb → Delay → Reverb.")
        #expect(RemoteError(code: 1034, message: message, reason: "routing_loop").sentence == message)
    }

    @Test func otherRefusalsSayTheirMessage() {
        let stale = RemoteError(code: 1026, message: "This changed on the computer. The phone now shows the new state.",
                                reason: "stale_target", data: ["reason": "stale_target", "detail": "Not a host error."])
        #expect(stale.sentence == stale.message, "only a host_error carries a reason in words")
        let busy = RemoteError(code: 1012, message: "Tabber Studio is busy. Try again in a moment.", reason: "busy")
        #expect(busy.sentence == busy.message)
    }

    /// Every host_error in the protocol's vectors, read off the wire as the app reads it.
    @Test func everyHostErrorInTheVectorsSaysItsDetail() throws {
        var seen = 0
        for file in try Vectors.exchanges() {
            for step in try Vectors.json("exchanges/\(file)")["steps"]?.arrayValue ?? [] {
                guard let error = step["message"]?["error"], let failure = RemoteError(json: error),
                      failure.reason == "host_error" else { continue }
                #expect(failure.message == Self.general)
                #expect(failure.sentence == (error["data"]?["detail"]?.stringValue ?? Self.general), "\(file)")
                seen += 1
            }
        }
        #expect(seen >= 3, "the plug-in, MIDI tab and take refusals")
    }

    /// DemoHost's own host_error refusals, through RemoteSession, as the app gets them.
    @Test func theDemosRefusalsSayWhy() async throws {
        let demo = DemoHostTests()
        let session = demo.session(DemoHost())
        _ = try await demo.connected(session)
        do {
            _ = try await session.perform("plugins.insert", ["strip_id": "demo-vocals", "plugin_id": "pl-gone"])
            Issue.record("a plug-in the computer does not have went in")
        } catch let failure as RemoteError {
            #expect(failure.reason == "host_error" && failure.message == Self.general)
            #expect(failure.sentence == "That plug-in is not on the computer any more. Open the list again.")
        }
        do {
            _ = try await session.perform("plugins.insert", ["strip_id": "demo-vocals", "plugin_id": "pl-tabber-synth"])
            Issue.record("an instrument went in on an audio track")
        } catch let failure as RemoteError {
            #expect(failure.reason == "host_error" && failure.message == Self.general)
            #expect(failure.sentence == "Insert this instrument on a MIDI/score track.")
        }
        await session.stop()
    }
}
