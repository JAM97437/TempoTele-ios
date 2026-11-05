import Foundation
import Combine
import Security
import CryptoKit

// LG webOS 23: local, encrypted SSAP WebSocket on port 3001.
// This is a best-effort remote, NOT an always-on parental-control lock.

private enum LGSecrets {
    private static let service = "TempoTele.LGTV"

    static func read(_ account: String) -> String? {
        let request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let data = value.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func erase(_ account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

// A local LG TV typically has a privately issued TLS certificate. Trust its
// certificate upon FIRST pairing on a trusted home network, then pin its SHA-256
// fingerprint. A changed certificate is rejected until the user resets pairing.
private final class LGTVCertificateDelegate: NSObject, URLSessionDelegate {
    private let host: String
    private let fingerprintAccount: String

    init(host: String) {
        self.host = host
        self.fingerprintAccount = "certificate-\(host)"
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let bytes = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if let pinned = LGSecrets.read(fingerprintAccount) {
            guard pinned == fingerprint else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        } else {
            LGSecrets.save(fingerprint, account: fingerprintAccount)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

@MainActor
final class LGTVRemote: ObservableObject {
    @Published var ipAddress: String = UserDefaults.standard.string(forKey: "lgIPV5") ?? "" {
        didSet { UserDefaults.standard.set(ipAddress, forKey: "lgIPV5") }
    }
    @Published var automaticPowerOff: Bool = UserDefaults.standard.object(forKey: "lgAutoOffV5") as? Bool ?? false {
        didSet { UserDefaults.standard.set(automaticPowerOff, forKey: "lgAutoOffV5") }
    }
    @Published private(set) var status = "TV LG non associée"
    @Published private(set) var isBusy = false

    var paired: Bool {
        guard let host = validatedHost() else { return false }
        return LGSecrets.read("key-\(host)") != nil
    }

    // Private LAN IPv4 addresses only. No cloud service, public IP or external host.
    private func validatedHost() -> String? {
        let address = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = address.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4 else { return nil }
        let numbers = fields.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return nil }
        let a = numbers[0], b = numbers[1]
        guard a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) else { return nil }
        return numbers.map(String.init).joined(separator: ".")
    }

    func forgetPairing() {
        guard let host = validatedHost() else { return }
        LGSecrets.erase("key-\(host)")
        LGSecrets.erase("certificate-\(host)")
        automaticPowerOff = false
        status = "Association effacée. Vous pouvez recommencer."
    }

    func pair() async { await run(turnOff: false) }
    func turnOff() async { await run(turnOff: true) }

    private func run(turnOff: Bool) async {
        guard !isBusy else { return }
        guard let host = validatedHost() else {
            status = "Saisissez une adresse IP locale valide (ex. 192.168.1.50)."
            return
        }
        if turnOff && !paired {
            status = "Associez d’abord la télévision dans les réglages."
            return
        }

        isBusy = true
        defer { isBusy = false }
        status = turnOff ? "Connexion pour éteindre la TV…" : "Connexion… Acceptez la demande affichée sur la TV."
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config, delegate: LGTVCertificateDelegate(host: host), delegateQueue: nil)
        let socket = session.webSocketTask(with: URL(string: "wss://\(host):3001/")!)
        socket.maximumMessageSize = 128 * 1024
        socket.resume()
        // Also bounds the TV's on-screen pairing prompt when it is never accepted.
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer {
            timeout.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        do {
            let key = LGSecrets.read("key-\(host)")
            let manifest: [String: Any] = [
                "manifestVersion": 1,
                "appVersion": "1.0",
                "permissions": ["CONTROL_POWER", "READ_RUNNING_APPS"],
                "signed": [
                    "created": "20261105",
                    "appId": "com.tempotele.ios",
                    "vendorId": "com.tempotele",
                    "localizedAppNames": ["": "Tempo Télé"],
                    "localizedVendorNames": ["": "Tempo Télé"],
                    "permissions": ["CONTROL_POWER", "READ_RUNNING_APPS"]
                ]
            ]
            var payload: [String: Any] = [
                "pairingType": "PROMPT",
                "forcePairing": false,
                "manifest": manifest
            ]
            if let key = key { payload["client-key"] = key }
            try await send(socket, ["id": "registration", "type": "register", "payload": payload])

            var didRegister = false
            while !didRegister {
                let response = try await receive(socket)
                if (response["type"] as? String) == "registered" {
                    guard let responsePayload = response["payload"] as? [String: Any],
                          let newKey = responsePayload["client-key"] as? String else {
                        throw LGError.protocolError("La télévision n’a pas renvoyé de clé d’association.")
                    }
                    LGSecrets.save(newKey, account: "key-\(host)")
                    didRegister = true
                } else if (response["type"] as? String) == "error" {
                    throw LGError.protocolError(response["error"] as? String ?? "Association refusée par la TV.")
                }
            }

            if !turnOff {
                status = "LG UR73006LA associée. Vous pouvez tester l’extinction."
                return
            }
            try await send(socket, [
                "id": "powerOff", "type": "request", "uri": "ssap://system/turnOff", "payload": [:] as [String: String]
            ])
            // The TV may drop the socket before answering when it powers off.
            // Sending is not proof that the TV actually switched off.
            status = "Commande d’extinction envoyée. Vérifiez que la TV s’est arrêtée."
        } catch {
            status = "TV inaccessible ou commande refusée : \(error.localizedDescription)"
        }
    }

    private func send(_ socket: URLSessionWebSocketTask, _ value: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        guard let json = String(data: data, encoding: .utf8) else { throw LGError.protocolError("JSON invalide") }
        try await socket.send(.string(json))
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let string): data = Data(string.utf8)
        case .data(let payload): data = payload
        @unknown default: throw LGError.protocolError("Réponse inconnue")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LGError.protocolError("Réponse invalide")
        }
        return object
    }

    private enum LGError: LocalizedError {
        case protocolError(String)
        var errorDescription: String? {
            switch self { case .protocolError(let message): return message }
        }
    }
}
