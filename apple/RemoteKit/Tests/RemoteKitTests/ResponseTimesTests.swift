import Foundation
import Testing
@testable import RemoteKit

/// TR7's gate measured on the phone: how long the computer takes to answer a tap.
@Suite("Response times")
struct ResponseTimesTests {
    @Test func nearestRankPercentiles() {
        var times = ResponseTimes()
        #expect(times.median == nil && times.p95 == nil)
        for ms in 1...20 { times.add(.milliseconds(ms)) }
        #expect(times.median == .milliseconds(10))
        #expect(times.p95 == .milliseconds(19))
        times.add(.milliseconds(400))
        #expect(times.p95 == .milliseconds(20), "one slow answer in 21 is not the 95th percentile")
        var one = ResponseTimes()
        one.add(.milliseconds(7))
        #expect(one.median == .milliseconds(7) && one.p95 == .milliseconds(7))
    }

    @Test func onlyTheNewestAreKept() {
        var times = ResponseTimes()
        for ms in 1...(ResponseTimes.kept + 10) { times.add(.milliseconds(ms)) }
        #expect(times.count == ResponseTimes.kept)
        #expect(times.samples.first == .milliseconds(11))
    }

    @Test func wholeMilliseconds() {
        #expect(Duration.microseconds(18_400).milliseconds == 18)
        #expect(Duration.microseconds(18_600).milliseconds == 19)
        #expect(Duration.seconds(2).milliseconds == 2000)
    }

    @Test func changesAreTimedButNotReadsOrTheChat() async throws {
        let host = DemoHost()
        let session = RemoteSession(credentials: .demo, app: AppInfo(version: "1.0", build: "1")) { _ in await host.connect() }
        await session.start()
        for _ in 0..<200 {
            if case .connected = await session.state.link, await session.state.transport != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await session.responseTimes.count == 0, "connecting is not a tap")
        _ = try await session.perform("transport.set_click", ["enabled": true])
        _ = try await session.perform("transport.play")
        _ = try await session.perform("mixer.state")
        _ = try await session.perform("chat.send", ["text": "mute the drums"])
        let times = await session.responseTimes
        #expect(times.count == 2, "the click and play; not the read or the chat")
        #expect(times.samples.allSatisfy { $0 > .zero && $0 < .seconds(2) })
        await session.resetResponseTimes()
        #expect(await session.responseTimes.count == 0)
        await session.stop()
    }
}
