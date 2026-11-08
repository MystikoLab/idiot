# Phase 13 — Agent Access (MCP)

Let local AI agents such as Hermes read, and optionally change, finances through MCP.

## Implementation guide

- **Transport** (`Helpers/MCPHTTPServer.swift`): `NWListener` bound to `127.0.0.1:47821`, running on the main queue. `POST /mcp` only, JSON responses, no sessions or SSE. Checks `Host` and `Origin` against DNS rebinding, compares the bearer token in constant time, caps headers at 16 KB, bodies at 1 MB and connections at 16.
- **Protocol** (`Helpers/MCPProtocol.swift`): JSON-RPC handling for `initialize`, `ping`, `tools/list` and `tools/call`.
- **Tools** (`Helpers/MCPTools.swift`): six read tools and three write tools, reusing `AnalyticsEngine` and `RecurringEngine`. Write tools are hidden and refused unless enabled, and always refuse dates in past months regardless of the `lockPastMonths` setting.
- **Lifecycle** (`ViewModels/MCPServerController.swift`): persists the two toggles, stores the token in the keychain, and holds a process activity to avoid App Nap while serving. Started from `idiotApp.init`.
- **UI** (`Views/MCPSettingsSection.swift`): Settings section with toggles, status, last request, and copy buttons for the Hermes config and token.
- **Entitlement**: `com.apple.security.network.server` in `Idiot-macOS.entitlements`.
- iOS is not supported because the app cannot serve requests in the background.
