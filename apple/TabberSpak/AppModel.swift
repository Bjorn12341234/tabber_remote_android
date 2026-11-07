import Foundation
import Observation
import RemoteKit

/// The app's one session, on the main actor for SwiftUI.
@MainActor
@Observable
final class AppModel {
    private(set) var state = SessionState()
    private(set) var problem: String?
    private(set) var isDemo = false
    private(set) var known: KnownHost?
    private var session: RemoteSession?
    private var listener: Task<Void, Never>?

    static let app = AppInfo(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                             build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")

    init() {
        known = HostStore.load()
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            startDemo()
        } else if let known, let signer = try? DeviceKeyStore.loadOrCreate() {
            start(.paired(known, signer), routes: known.routes)
        }
    }

    func startDemo() {
        isDemo = true
        let host = DemoHost()
        attach(RemoteSession(credentials: .demo, app: Self.app) { _ in await host.connect() })
    }

    /// Pair from the QR code's link (scanned, pasted, or `simctl openurl`).
    func pair(with link: PairingLink) async {
        problem = nil
        do {
            let signer = try DeviceKeyStore.loadOrCreate()
            var lastError: Error?
            for route in link.routes {
                let client = RemoteClient(transport: NetworkTransport(route: route, pin: link.pin))
                await client.start()
                do {
                    _ = try await client.sayHello(app: Self.app)
                    _ = try await client.pair(token: link.token, pin: link.pin, device: signer,
                                              name: DeviceName.current, model: DeviceName.model)
                    await client.close()
                    let host = KnownHost(id: link.hostID, name: link.name, pin: link.pin, routes: [route] + link.routes.filter { $0 != route })
                    HostStore.save(host)
                    known = host
                    isDemo = false
                    start(.paired(host, signer), routes: host.routes)
                    return
                } catch {
                    lastError = error
                    await client.close()
                }
            }
            problem = Self.explain(lastError)
        } catch {
            problem = Self.explain(error)
        }
    }

    private func start(_ credentials: RemoteSession.Credentials, routes: [Route]) {
        attach(RemoteSession(credentials: credentials, app: Self.app) { attempt in
            NetworkTransport(route: routes[attempt % max(1, routes.count)], pin: {
                if case .paired(let host, _) = credentials { return host.pin }
                return nil
            }())
        })
    }

    private func attach(_ next: RemoteSession) {
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = next
        listener = Task { [weak self] in
            await next.start()
            for await update in next.updates {
                self?.state = update
            }
        }
    }

    func forget() {
        HostStore.clear()
        known = nil
        listener?.cancel()
        if let old = session { Task { await old.stop() } }
        session = nil
        state = SessionState()
    }

    /// Run a verb; a refusal is shown in words (spec 10).
    func perform(_ method: String, _ params: JSONValue = [:]) {
        guard let session else { return }
        Task {
            do {
                _ = try await session.perform(method, params)
                problem = nil
            } catch {
                problem = Self.explain(error)
            }
        }
    }

    static func explain(_ error: Error?) -> String {
        switch error {
        case let failure as RemoteError: return failure.message
        case TransportFailure.wrongKey?: return "This is not the computer you paired with."
        case TransportFailure.closed?: return "Tabber Studio closed the connection."
        case .some(let other): return "Could not reach Tabber Studio (\(other.localizedDescription))."
        case nil: return "Could not reach Tabber Studio."
        }
    }
}

/// The paired computer, kept on this phone (no secrets: the key stays in the Keychain).
enum HostStore {
    static let key = "studio.tabber.spak.known-host"
    static func load() -> KnownHost? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(KnownHost.self, from: $0) }
    }
    static func save(_ host: KnownHost) {
        UserDefaults.standard.set(try? JSONEncoder().encode(host), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

@MainActor
enum DeviceName {
    static var current: String {
        #if canImport(UIKit)
        return UIDeviceName.name
        #else
        return Host.current().localizedName ?? "Tabber Spak"
        #endif
    }
    static var model: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        return "iPhone"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
enum UIDeviceName {
    @MainActor static var name: String { UIDevice.current.name }
}
#endif
