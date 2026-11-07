import CryptoKit
import Foundation
import Testing
@testable import RemoteKit

/// The protocol's vectors, run in Swift (spec 13).
enum Vectors {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appending(path: "protocol/vectors")
    }()

    static func json(_ path: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: root.appending(path: path)))
    }

    static func exchanges() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "exchanges").path())
            .filter { $0.hasSuffix(".json") }.sorted()
    }
}

@Suite("Crypto vectors")
struct CryptoVectorTests {
    let identity: JSONValue

    init() throws { identity = try Vectors.json("crypto/identity.json") }

    func key(_ name: String) throws -> P256.Signing.PrivateKey {
        let pem = try String(contentsOf: Vectors.root.appending(path: "keys/\(name)_test_key.pem"), encoding: .utf8)
        return try P256.Signing.PrivateKey(pemRepresentation: pem)
    }

    @Test func pinsAndDeviceIDs() throws {
        let host = try key("host").publicKey.derRepresentation
        #expect(RemoteCrypto.pin(spkiDER: host) == identity["host"]?["pin"]?.stringValue)
        let device = try key("device").publicKey.derRepresentation
        #expect(Base64URL.encode(device) == identity["device"]?["key"]?.stringValue)
        #expect(RemoteCrypto.deviceID(publicKeyDER: device) == identity["device"]?["device_id"]?.stringValue)
        #expect(SoftwareSigner(key: try key("device")).deviceID == identity["device"]?["device_id"]?.stringValue)
    }

    @Test func theSPKIPrefixMatchesCryptoKit() throws {
        let key = try key("host").publicKey
        #expect(RemoteCrypto.spkiDER(x963: key.x963Representation) == key.derRepresentation)
    }

    @Test func signedBytesAndSignatures() throws {
        let vectors = try Vectors.json("crypto/signatures.json")
        let pinHash = try #require(Base64URL.decode(vectors["host_pin"]!.stringValue!))
        for case let item in vectors["cases"]!.arrayValue! {
            let message = Data(hex: item["signed_bytes_hex"]!.stringValue!)
            let keyDER = try #require(Base64URL.decode(item["device_key"]!.stringValue!))
            let signature = try #require(Base64URL.decode(item["signature"]!.stringValue!))
            let verifies = item["verifies"]!.boolValue!
            #expect(RemoteCrypto.verify(publicKeyDER: keyDER, signatureDER: signature, message: message) == verifies,
                    "\(item["name"]!.stringValue!)")
            if verifies {
                let context = Data(item["context"]!.stringValue!.utf8) + Data([0])
                let token = item["token"]?.stringValue.flatMap(Base64URL.decode) ?? Data()
                #expect(RemoteCrypto.signedBytes(context: context, pinHash: pinHash,
                                                 challenge: Base64URL.decode(item["challenge"]!.stringValue!)!,
                                                 token: token) == message)
            }
        }
    }

    @Test func aSignatureMadeHereVerifiesThere() throws {
        let signer = SoftwareSigner(key: try key("device"))
        let message = Data("tabber".utf8)
        #expect(RemoteCrypto.verify(publicKeyDER: signer.publicKeyDER, signatureDER: try signer.sign(message), message: message))
    }

    @Test func pairingCodes() throws {
        for case let item in try Vectors.json("crypto/pairing_code.json")["cases"]!.arrayValue! {
            let code = RemoteCrypto.pairingCode(pinHash: Base64URL.decode(item["host_pin"]!.stringValue!)!,
                                                deviceIDHash: Base64URL.decode(item["device_id"]!.stringValue!)!,
                                                challenge: Base64URL.decode(item["challenge"]!.stringValue!)!)
            #expect(code == item["code"]!.stringValue!)
        }
    }

    @Test func theQRLink() throws {
        let vector = try Vectors.json("crypto/qr_link.json")
        let link = try #require(PairingLink(string: vector["link"]!.stringValue!))
        #expect(link.hostID == identity["host"]?["id"]?.stringValue)
        #expect(link.pin == identity["host"]?["pin"]?.stringValue)
        #expect(link.token == identity["token"]?.stringValue)
        #expect(link.name == "Studio Mac")
        #expect(link.routes.map(\.description) == vector["routes"]!.arrayValue!.map { $0.stringValue! })
        #expect(link.routes.last == Route(host: "fd12:3456:789a::20", port: 9474))
    }
}

@Suite("Exchange vectors")
struct ExchangeVectorTests {
    static let results: [String: any Decodable.Type] = [
        "hello": HelloResult.self, "pair": PairResult.self, "auth": AuthResult.self,
        "session.subscribe": Snapshot.self, "session.snapshot": Snapshot.self,
    ]

    /// Every message the app reads decodes into its model and encodes back to the same JSON.
    @Test(arguments: try Vectors.exchanges())
    func everyHostMessageDecodes(_ file: String) throws {
        let vector = try Vectors.json("exchanges/\(file)")
        var methods: [Int: String] = [:]
        for step in vector["steps"]!.arrayValue! {
            guard let message = step["message"] else { continue }
            if step["from"]?.stringValue == "remote" {
                if let id = message["id"]?.intValue { methods[id] = message["method"]?.stringValue }
                continue
            }
            if let result = message["result"], let method = message["id"]?.intValue.flatMap({ methods[$0] }) {
                try check(method: method, result: result)
            } else if let error = message["error"] {
                let failure = try #require(RemoteError(json: error))
                #expect(!failure.reason.isEmpty)
            } else if message["method"]?.stringValue == "event", let params = message["params"] {
                try check(topic: params["topic"]!.stringValue!, data: params["data"]!)
            } else if message["method"]?.stringValue == "heartbeat" {
                _ = try JSONCoding.decode(Heartbeat.self, from: message["params"]!)
            }
        }
    }

    func roundTrip<T: Codable>(_ type: T.Type, _ value: JSONValue) throws {
        let model = try JSONCoding.decode(T.self, from: value)
        #expect(try JSONCoding.value(model) == value, "\(T.self) does not round-trip")
    }

    func check(method: String, result: JSONValue) throws {
        switch method {
        case "hello": try roundTrip(HelloResult.self, result)
        case "pair": try roundTrip(PairResult.self, result)
        case "auth": try roundTrip(AuthResult.self, result)
        case "session.subscribe", "session.snapshot": try roundTrip(Snapshot.self, result)
        default:
            for (key, value) in result.objectValue ?? [:] {
                switch key {
                case "transport": try roundTrip(TransportState.self, value)
                case "record": try roundTrip(RecordState.self, value)
                case "tracks": try roundTrip([Track].self, value)
                case "markers": try roundTrip([Marker].self, value)
                case "marker": try roundTrip(Marker.self, value)
                case "takes": try roundTrip([Take].self, value)
                case "take": if value != .null { try roundTrip(Take.self, value) }
                case "undo": try roundTrip(UndoState.self, value)
                case "project": try roundTrip(ProjectState.self, value)
                case "topics": try roundTrip([String].self, value)
                default: Issue.record("unknown result field \(key) of \(method)")
                }
            }
        }
    }

    func check(topic: String, data: JSONValue) throws {
        switch topic {
        case "transport": try roundTrip(TransportState.self, data)
        case "record": try roundTrip(RecordState.self, data)
        case "tracks": try roundTrip([Track].self, data["tracks"]!)
        case "markers": try roundTrip([Marker].self, data["markers"]!)
        case "takes": try roundTrip([Take].self, data["takes"]!)
        case "undo": try roundTrip(UndoState.self, data)
        case "project": try roundTrip(ProjectState.self, data)
        case "position": try roundTrip(Position.self, data["position"]!)
        case "meters": try roundTrip([MeterLevel].self, data["levels"]!)
        default: Issue.record("unknown topic \(topic)")
        }
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
