#if os(macOS)
    import Foundation
    import Observation
    import Security
    import SwiftData

    @MainActor
    @Observable
    final class MCPServerController {
        enum Status: Equatable {
            case off
            case starting
            case running
            case failed(String)
        }

        static let shared = MCPServerController()
        static let port: UInt16 = 47821

        private static let enabledKey = "mcpServerEnabled"
        private static let writesEnabledKey = "mcpWritesEnabled"
        private static let keychainService = "com.umangsurana.idiot.mcp"
        private static let keychainAccount = "bearer-token"

        private(set) var status: Status = .off
        private(set) var lastToolCall: (name: String, date: Date)?

        var isEnabled: Bool {
            didSet {
                UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
                applyEnabled()
            }
        }

        var writesEnabled: Bool {
            didSet {
                UserDefaults.standard.set(writesEnabled, forKey: Self.writesEnabledKey)
            }
        }

        var endpoint: String {
            "http://127.0.0.1:\(Self.port)/mcp"
        }

        var hermesConfig: String {
            """
            mcp_servers:
              idiot:
                url: "\(endpoint)"
                headers:
                  Authorization: "Bearer ${IDIOT_MCP_TOKEN}"
                trust: untrusted
            """
        }

        private var container: ModelContainer?
        private var server: MCPHTTPServer?
        private var token = ""
        private var activity: NSObjectProtocol?

        private init() {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
            writesEnabled = UserDefaults.standard.bool(forKey: Self.writesEnabledKey)
        }

        func configure(container: ModelContainer) {
            self.container = container
            applyEnabled()
        }

        func currentToken() -> String? {
            if token.isEmpty {
                loadOrCreateToken()
            }
            return token.isEmpty ? nil : token
        }

        func regenerateToken() {
            guard let fresh = Self.generateToken(), Self.storeToken(fresh) else {
                status = .failed("Could not save the access token to the keychain.")
                return
            }
            token = fresh
        }

        private func applyEnabled() {
            stopServer()
            guard isEnabled, let container else {
                status = .off
                return
            }
            loadOrCreateToken()
            guard !token.isEmpty else {
                status = .failed("Could not save the access token to the keychain.")
                return
            }

            let rpc = MCPProtocol(
                context: container.mainContext,
                writesEnabled: { [weak self] in self?.writesEnabled ?? false },
                onToolCall: { [weak self] name in self?.lastToolCall = (name, .now) }
            )
            let server = MCPHTTPServer(
                port: Self.port,
                token: { [weak self] in self?.token ?? "" },
                handler: { rpc.respond(to: $0) },
                onStateChange: { [weak self] state in
                    switch state {
                    case .ready:
                        self?.status = .running
                    case let .failed(message):
                        self?.stopServer()
                        self?.status = .failed(message)
                    }
                }
            )

            do {
                status = .starting
                try server.start()
                self.server = server
                activity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: "Serving agent access"
                )
            } catch {
                status = .failed(error.localizedDescription)
            }
        }

        private func stopServer() {
            server?.stop()
            server = nil
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
            }
            activity = nil
        }

        private func loadOrCreateToken() {
            if let stored = Self.loadToken() {
                token = stored
            } else if let fresh = Self.generateToken(), Self.storeToken(fresh) {
                token = fresh
            }
        }

        private static func generateToken() -> String? {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }

        private static var keychainQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
        }

        private static func loadToken() -> String? {
            var query = keychainQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func storeToken(_ token: String) -> Bool {
            let data = Data(token.utf8)
            let updated = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updated == errSecSuccess {
                return true
            }
            var attributes = keychainQuery
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
    }
#endif
