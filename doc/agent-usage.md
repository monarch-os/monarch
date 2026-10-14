# Agent usage

Monarch uses CodexBar CLI and its own `monarch-agents` Noctalia v5 plugin.
The `monarch agent` launcher remains independent of quota monitoring.

The bar shows one agent icon; its tooltip and panel retain every provider.
The panel retains Monarch's provider selector and spent-quota gauges. Quota
labels come directly from CodexBar, rather than assuming weekly/monthly windows.
CodexBar owns collection and authentication; the plugin keeps no local history.
The panel and tooltip use Noctalia's language, with English and French catalogs.
Provider names, authentication errors and quota labels from CodexBar are preserved.

Manage providers from the panel's **Manage providers** button, or run
`monarch agent usage manage` in a terminal. The searchable list comes directly
from CodexBar; enabling a provider is independent of picking a default agent.

The commands documented in the wiki remain supported:

```bash
monarch agent usage providers
monarch agent usage status
monarch agent usage status claude
monarch agent usage enable claude
monarch agent usage disable claude
monarch agent usage setup codex
codexbar usage --format json
```

For Synthetic, enter the key in the masked terminal prompt:

```bash
monarch agent usage setup synthetic
```

`setup` uses the existing CLI authentication for Claude/Codex. Other providers
offer an API-key or existing-authentication choice. Keys are passed to CodexBar
through stdin, never command arguments, and stored only by CodexBar. Unsupported
key types are rejected by CodexBar. Providers requiring an endpoint, workspace
or cookies still need those additional settings in CodexBar; the configurator
does not invent them or start an interactive login itself.

Right-click the bar widget to refresh. No Qt application or HTTP server is required.

Codex uses the CLI's read-only app-server RPC, retaining support for credentials
stored in its keyring. Claude reads its existing OAuth credentials without
launching an interactive authentication fallback.

When the old Monarch collector is present, reconciliation prepares its transition
before the common plugin update. It preserves existing CodexBar configuration;
otherwise it enables Claude/Codex when their local directories exist, honours
disabled-provider markers, and imports the existing Synthetic key. Credentials,
history and Noctalia configuration stay untouched. The old plugin is archived
only after CodexBar validates the configuration.

After this transition, the plugin follows the same managed-tree reconciliation
as every other Monarch plugin. Backend authentication/configuration errors do not
block ordinary updates. Fresh installs leave provider configuration to CodexBar
and `monarch agent usage setup`; first-run only activates the plugin inventory.

Monarch Agents shows quotas, resets and credits, not Monarch's former local charts.
Use `codexbar cost --provider claude --format json` or the Codex equivalent for
local history; coverage is source-specific, not complete account billing.
