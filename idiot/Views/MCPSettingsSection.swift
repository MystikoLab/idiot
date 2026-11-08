#if os(macOS)
    import AppKit
    import SwiftUI

    struct MCPSettingsSection: View {
        @Bindable private var controller = MCPServerController.shared
        @State private var showRegenerateConfirmation = false

        var body: some View {
            Section {
                Toggle("Allow agent access", isOn: $controller.isEnabled)

                if controller.isEnabled {
                    LabeledContent("Status") {
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }

                    Toggle("Allow agents to change transactions", isOn: $controller.writesEnabled)

                    LabeledContent("Last request") {
                        Text(lastRequestText)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if let command = controller.claudeCodeCommand {
                            copy(command)
                        }
                    } label: {
                        Label("Copy Claude Code Setup Command", systemImage: "terminal")
                    }

                    Text(controller.hermesConfig)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)

                    Button {
                        copy(controller.hermesConfig)
                    } label: {
                        Label("Copy Hermes Config", systemImage: "doc.on.doc")
                    }

                    Button {
                        if let token = controller.currentToken() {
                            copy("IDIOT_MCP_TOKEN=\(token)")
                        }
                    } label: {
                        Label("Copy Access Token", systemImage: "key")
                    }

                    Button(role: .destructive) {
                        showRegenerateConfirmation = true
                    } label: {
                        Label("Regenerate Access Token", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } header: {
                Text("Agent Access (MCP)")
            } footer: {
                Text(footerText)
            }
            .alert("Regenerate Access Token?", isPresented: $showRegenerateConfirmation) {
                Button("Regenerate", role: .destructive) {
                    controller.regenerateToken()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Connected agents lose access until you give them the new token.")
            }
        }

        private var footerText: String {
            if controller.isEnabled {
                return "Claude Code: paste the setup command in Terminal once, then ask Claude about your finances in any session. The command contains your access token, which Claude Code saves in ~/.claude.json. Hermes: add the config to ~/.hermes/config.yaml and the token to ~/.hermes/.env, then run /reload-mcp. Agents can reach your finances only while Idiot is open on this Mac, and anything they read is sent to the AI model they use."
            }
            return "Lets a local AI agent such as Claude Code or Hermes read your finances over MCP. Anything an agent reads is sent to the AI model it uses."
        }

        private var statusText: String {
            switch controller.status {
            case .off: "Off"
            case .starting: "Starting…"
            case .running: "Listening on \(controller.endpoint)"
            case let .failed(message): message
            }
        }

        private var statusColor: Color {
            if case .failed = controller.status {
                return .red
            }
            return .secondary
        }

        private var lastRequestText: String {
            guard let call = controller.lastToolCall else { return "None" }
            return "\(call.name), \(call.date.formatted(date: .omitted, time: .shortened))"
        }

        private func copy(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
#endif
