import Foundation
import Testing
@testable import RemoteKit

/// RemoteKit's Network framework client against Tabber Studio's real host,
/// over TLS 1.3 with the pin. Runs when `REMOTE_INTEROP` holds the JSON line
/// `tools/interop_host.py` prints (apple/scripts/interop.sh does both).
@Suite("Interop with Tabber Studio's host",
       .enabled(if: ProcessInfo.processInfo.environment["REMOTE_INTEROP"] != nil))
struct InteropTests {
    let port: UInt16
    let pin: String
    let token: String
    let hostID: String

    init() throws {
        let line = ProcessInfo.processInfo.environment["REMOTE_INTEROP"] ?? "{}"
        let json = try JSONCoding.parse(line)
        port = UInt16(json["port"]?.intValue ?? 0)
        pin = json["pin"]?.stringValue ?? ""
        token = json["token"]?.stringValue ?? ""
        hostID = json["host_id"]?.stringValue ?? ""
    }

    var route: Route { Route(host: "127.0.0.1", port: port) }

    @Test func pairThenAuthenticateOverPinnedTLS() async throws {
        let signer = SoftwareSigner()
        let first = RemoteClient(transport: NetworkTransport(route: route, pin: pin))
        await first.start()
        let hello = try await first.sayHello(app: AppInfo(version: "1.0", build: "1"))
        #expect(hello.host.id == hostID && hello.protocolVersion == RemoteClient.protocolVersions[0],
                "the interop host is the Tabber Studio checkout, which speaks the phone's newest version")
        #expect(hello.capabilities.contains("takes.discard/1"))
        let paired = try await first.pair(token: token, pin: pin, device: signer, name: "Interop iPhone", model: "test")
        #expect(paired.deviceID == signer.deviceID)
        do {
            _ = try await first.call("transport.play", ["key": .string(UUID().uuidString.lowercased())])
        } catch let failure as RemoteError {
            #expect(failure.reason == "host_error")   // the interop host has no song window
        }
        do {
            _ = try await first.call("system.quit", [:])
            Issue.record("a raw Control API method got through")
        } catch let failure as RemoteError {
            #expect(failure.reason == "method_not_found")
        }
        await first.close()

        let second = RemoteClient(transport: NetworkTransport(route: route, pin: pin))
        await second.start()
        _ = try await second.sayHello(app: AppInfo(version: "1.0", build: "1"))
        let auth = try await second.authenticate(pin: pin, device: signer)
        #expect(auth.device.id == signer.deviceID && auth.device.name == "Interop iPhone")
        await second.close()
    }

    @Test func aWrongPinNeverTalksToTheHost() async throws {
        let wrong = Base64URL.encode(Data(repeating: 7, count: 32))
        let client = RemoteClient(transport: NetworkTransport(route: route, pin: wrong))
        await client.start()
        await #expect(throws: (any Error).self) {
            _ = try await client.call("hello", ["app": ["name": "x", "version": "1", "build": "1", "platform": "ios"],
                                                "protocol_versions": ["1.0"]], timeout: .seconds(5))
        }
        await client.close()
    }

    @Test func noPinYetSeesTheHostsKey() async throws {
        let transport = NetworkTransport(route: route, pin: nil)
        let client = RemoteClient(transport: transport)
        await client.start()
        _ = try await client.sayHello(app: AppInfo(version: "1.0", build: "1"))
        #expect(transport.observedPin == pin)
        await client.close()
    }
}
