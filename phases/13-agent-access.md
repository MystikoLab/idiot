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

## Menu bar and Claude Code

- **Menu bar** (`Views/MenuBarView.swift`): `MenuBarExtra` with `.window` style, inserted while `showMenuBarExtra` is on (Settings > "Show in menu bar", default on). Shows the current month's income, expenses, net and balance, over-budget categories, the four most recent transactions, and actions for Add Transaction (`idiot://add`), Open Idiot and Analytics.
- **Main window**: the `WindowGroup` has id `main` and prefers external events, so `idiot://` URLs reuse the open window instead of spawning a new one.
- **Claude Code**: `MCPServerController.claudeCodeCommand` builds `claude mcp add --transport http --scope user idiot http://127.0.0.1:47821/mcp --header "Authorization: Bearer <token>"`. Copy it from the menu bar or Settings and run it once. Regenerating the token means running the command again after `claude mcp remove idiot -s user`.
