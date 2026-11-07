import CryptoKit
import Foundation

/// The protocol's cryptography (spec 4), exact to the byte.
public enum RemoteCrypto {
    public static let pairContext = Data("tabber-remote pair v1".utf8) + Data([0])
    public static let authContext = Data("tabber-remote auth v1".utf8) + Data([0])
    public static let codeContext = Data("tabber-remote code v1".utf8) + Data([0])

    /// DER SubjectPublicKeyInfo prefix for an uncompressed P-256 key.
    static let p256SPKIPrefix = Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02,
                                      0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
                                      0x42, 0x00])

    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    /// The pin: b64url(SHA-256(DER SubjectPublicKeyInfo)).
    public static func pin(spkiDER: Data) -> String { Base64URL.encode(sha256(spkiDER)) }

    /// SubjectPublicKeyInfo from a raw X9.63 P-256 point (what SecKey exports).
    public static func spkiDER(x963 point: Data) -> Data? {
        guard point.count == 65, point.first == 0x04 else { return nil }
        return p256SPKIPrefix + point
    }

    public static func deviceID(publicKeyDER: Data) -> String { Base64URL.encode(sha256(publicKeyDER)) }

    public static func signedBytes(context: Data, pinHash: Data, challenge: Data, token: Data = Data()) -> Data {
        context + pinHash + challenge + token
    }

    public static func verify(publicKeyDER: Data, signatureDER: Data, message: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: publicKeyDER),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    /// The six digits both screens show (spec 4.4).
    public static func pairingCode(pinHash: Data, deviceIDHash: Data, challenge: Data) -> String {
        let digest = sha256(codeContext + pinHash + deviceIDHash + challenge)
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
}

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), text.allSatisfy(\.isASCII) else {
            return nil
        }
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base)
    }
}

/// Where a computer can be reached: `name:port`, `ipv4:port` or `[ipv6]:port`.
public struct Route: Sendable, Hashable, Codable, CustomStringConvertible {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16) { self.host = host; self.port = port }

    public init?(_ text: String) {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"), text[text.index(after: close)...].hasPrefix(":"),
                  let port = UInt16(text[text.index(close, offsetBy: 2)...]) else { return nil }
            self.init(host: String(text[text.index(after: text.startIndex)..<close]), port: port)
        } else {
            guard let colon = text.lastIndex(of: ":"), let port = UInt16(text[text.index(after: colon)...]),
                  colon > text.startIndex else { return nil }
            self.init(host: String(text[..<colon]), port: port)
        }
    }

    public var description: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
}

/// The QR code's link (spec 4.2).
public struct PairingLink: Sendable, Hashable {
    public var versions: [String]
    public var hostID: String
    public var name: String
    public var pin: String
    public var token: String
    public var routes: [Route]

    public init?(url: URL) {
        guard url.scheme == "tabber-remote", url.host() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var fields: [String: String] = [:]
        for item in items { fields[item.name] = item.value ?? "" }
        guard let id = fields["id"], let pin = fields["spki"], let token = fields["tok"],
              let hosts = fields["hosts"], Base64URL.decode(pin)?.count == 32,
              Base64URL.decode(token)?.count == 16 else { return nil }
        let routes = hosts.split(separator: ",").compactMap { Route(String($0)) }
        guard !routes.isEmpty else { return nil }
        self.versions = (fields["v"] ?? "1").split(separator: ",").map(String.init)
        self.hostID = id
        self.name = fields["name"] ?? "Tabber Studio"
        self.pin = pin
        self.token = token
        self.routes = routes
    }

    public init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }
}
