#if os(macOS)
    import Foundation
    import Network

    @MainActor
    final class MCPHTTPServer {
        enum State: Equatable {
            case ready
            case failed(String)
        }

        fileprivate static let maxHeaderBytes = 16 * 1024
        fileprivate static let maxBodyBytes = 1024 * 1024
        private static let maxConnections = 16

        let port: UInt16
        fileprivate let token: () -> String
        fileprivate let handler: (Data) -> Data?
        private let onStateChange: (State) -> Void
        private var listener: NWListener?
        private var connections: [ObjectIdentifier: MCPHTTPConnection] = [:]

        init(port: UInt16, token: @escaping () -> String, handler: @escaping (Data) -> Data?, onStateChange: @escaping (State) -> Void) {
            self.port = port
            self.token = token
            self.handler = handler
            self.onStateChange = onStateChange
        }

        func start() throws {
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                throw MCPToolError("Invalid port \(port)")
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        self?.onStateChange(.ready)
                    case let .failed(error):
                        self?.onStateChange(.failed(error.localizedDescription))
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        }

        func stop() {
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.close() }
            connections.removeAll()
        }

        private func accept(_ connection: NWConnection) {
            guard connections.count < Self.maxConnections else {
                connection.cancel()
                return
            }
            let wrapper = MCPHTTPConnection(connection: connection, server: self)
            connections[ObjectIdentifier(wrapper)] = wrapper
            wrapper.start()
        }

        fileprivate func remove(_ connection: MCPHTTPConnection) {
            connections[ObjectIdentifier(connection)] = nil
        }
    }

    @MainActor
    private final class MCPHTTPConnection {
        private struct Response {
            let status: String
            var headers: [String] = []
            var body = Data()
            var closes = false
        }

        private static let idleTimeout: TimeInterval = 120
        private static let separator = Data("\r\n\r\n".utf8)

        private let connection: NWConnection
        private weak var server: MCPHTTPServer?
        private var buffer = Data()
        private var idleTimer: DispatchWorkItem?
        private var closed = false

        init(connection: NWConnection, server: MCPHTTPServer) {
            self.connection = connection
            self.server = server
        }

        func start() {
            connection.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .failed, .cancelled:
                        self?.close()
                    default:
                        break
                    }
                }
            }
            connection.start(queue: .main)
            resetIdleTimer()
            receive()
        }

        func close() {
            guard !closed else { return }
            closed = true
            idleTimer?.cancel()
            connection.stateUpdateHandler = nil
            connection.cancel()
            server?.remove(self)
        }

        private func resetIdleTimer() {
            idleTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.close()
                }
            }
            idleTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTimeout, execute: timer)
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    if let data {
                        self.buffer.append(data)
                        self.resetIdleTimer()
                    }
                    if self.processBuffer() {
                        return
                    }
                    if isComplete || error != nil {
                        self.close()
                    } else {
                        self.receive()
                    }
                }
            }
        }

        private func processBuffer() -> Bool {
            while true {
                guard let headerEnd = buffer.range(of: Self.separator) else {
                    if buffer.count > MCPHTTPServer.maxHeaderBytes {
                        send(Response(status: "431 Request Header Fields Too Large", closes: true))
                        return true
                    }
                    return false
                }
                guard headerEnd.lowerBound - buffer.startIndex <= MCPHTTPServer.maxHeaderBytes,
                      let head = String(data: buffer[buffer.startIndex ..< headerEnd.lowerBound], encoding: .utf8),
                      let request = RequestHead(head)
                else {
                    send(Response(status: "400 Bad Request", closes: true))
                    return true
                }
                if request.headers["transfer-encoding"] != nil {
                    send(Response(status: "501 Not Implemented", closes: true))
                    return true
                }
                guard let length = request.contentLength else {
                    send(Response(status: "400 Bad Request", closes: true))
                    return true
                }
                guard length <= MCPHTTPServer.maxBodyBytes else {
                    send(Response(status: "413 Content Too Large", closes: true))
                    return true
                }
                guard buffer.count - (headerEnd.upperBound - buffer.startIndex) >= length else {
                    return false
                }

                let bodyStart = headerEnd.upperBound
                let body = Data(buffer[bodyStart ..< bodyStart + length])
                buffer = Data(buffer[(bodyStart + length)...])
                let response = respond(to: request, body: body)
                send(response)
                if response.closes {
                    return true
                }
            }
        }

        private func respond(to request: RequestHead, body: Data) -> Response {
            guard let server else {
                return Response(status: "503 Service Unavailable", closes: true)
            }
            let loopbackHosts = ["127.0.0.1:\(server.port)", "localhost:\(server.port)"]
            guard let host = request.headers["host"]?.lowercased(), loopbackHosts.contains(host) else {
                return Response(status: "403 Forbidden", closes: true)
            }
            if let origin = request.headers["origin"]?.lowercased(), !loopbackHosts.contains(where: { origin == "http://\($0)" }) {
                return Response(status: "403 Forbidden", closes: true)
            }
            guard isAuthorized(request.headers["authorization"], token: server.token()) else {
                return Response(status: "401 Unauthorized", headers: ["WWW-Authenticate: Bearer"])
            }
            guard request.path == "/mcp" else {
                return Response(status: "404 Not Found")
            }
            guard request.method == "POST" else {
                return Response(status: "405 Method Not Allowed", headers: ["Allow: POST"])
            }
            guard let payload = server.handler(body) else {
                return Response(status: "202 Accepted")
            }
            return Response(status: "200 OK", headers: ["Content-Type: application/json"], body: payload)
        }

        private func isAuthorized(_ header: String?, token: String) -> Bool {
            guard !token.isEmpty else { return false }
            let supplied = Array((header ?? "").utf8)
            let expected = Array("Bearer \(token)".utf8)
            var difference = supplied.count ^ expected.count
            for index in expected.indices {
                difference |= Int(expected[index] ^ (index < supplied.count ? supplied[index] : 0))
            }
            return difference == 0
        }

        private func send(_ response: Response) {
            var head = "HTTP/1.1 \(response.status)\r\n"
            for header in response.headers {
                head += "\(header)\r\n"
            }
            head += "Content-Length: \(response.body.count)\r\n"
            if response.closes {
                head += "Connection: close\r\n"
            }
            head += "\r\n"

            let closes = response.closes
            connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { [weak self] _ in
                MainActor.assumeIsolated {
                    if closes {
                        self?.close()
                    }
                }
            })
        }
    }

    private struct RequestHead {
        let method: String
        let path: String
        let headers: [String: String]
        let contentLength: Int?

        init?(_ head: String) {
            let lines = head.components(separatedBy: "\r\n")
            let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
            guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }
            method = String(requestLine[0])
            path = String(requestLine[1])

            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let name = line[..<colon].lowercased()
                guard headers[name] == nil else { return nil }
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            self.headers = headers

            if let value = headers["content-length"] {
                contentLength = Int(value).flatMap { $0 >= 0 ? $0 : nil }
            } else {
                contentLength = 0
            }
        }
    }
#endif
