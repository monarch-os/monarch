# Agent usage integration

User instructions live in the
[Agents panel guide](https://docs.monarchlinux.com/basics/noctalia/agents-panel).
This document covers the implementation and upgrade contract.

Monarch uses CodexBar CLI and its own `monarch-agents` Noctalia v5 plugin.
The `monarch agent` launcher remains independent of quota monitoring.

The bar shows one agent icon; its tooltip and panel retain every provider.
The panel retains Monarch's provider selector and spent-quota gauges. Quota
labels come directly from CodexBar, rather than assuming weekly/monthly windows.
CodexBar owns collection and authentication; the plugin keeps no local history.
One singleton plugin service collects for every bar/output. Its streaming bridge
allows 120 seconds for a CLI result, including Antigravity's 90-second fallback,
without Noctalia's shorter asynchronous-call deadline. Partial results are retained.
The panel and tooltip use Noctalia's language, with English and French catalogs.
Provider names, authentication errors and quota labels from CodexBar are preserved.

The provider list comes directly from CodexBar; enabling a provider is
independent of picking a default agent.

`setup` uses the existing CLI authentication for Claude/Codex. Other providers
offer an API-key or existing-authentication choice. Keys are passed to CodexBar
through stdin, never command arguments, and stored only by CodexBar. Unsupported
key types are rejected by CodexBar. Providers requiring an endpoint, workspace
or cookies still need those additional settings in CodexBar; the configurator
does not invent them or start an interactive login itself.

No Qt application or HTTP server is required.

Codex uses the CLI's read-only app-server RPC, retaining support for credentials
stored in its keyring. Claude reads its existing OAuth credentials without
launching an interactive authentication fallback.

When the old Monarch collector is present, reconciliation prepares its transition
before the common plugin update. It preserves existing CodexBar configuration;
otherwise it enables Claude/Codex when their local directories exist, honours
disabled-provider markers, and imports the existing Synthetic key. Credentials,
history and Noctalia configuration stay untouched. The old plugin is archived
only after CodexBar validates the configuration. Archival copies the legacy tree;
the common managed-tree publisher leaves it live until the replacement is staged
and restores it if publication fails. Matching archives permit safe retries.

After this transition, the plugin follows the same managed-tree reconciliation
as every other Monarch plugin. Backend authentication/configuration errors do not
block ordinary updates. Fresh installs leave provider configuration to CodexBar
and `monarch agent usage setup`; first-run only activates the plugin inventory.

Monarch Agents shows quotas, resets and credits, not Monarch's former local charts.
CodexBar's local-history coverage is source-specific, not complete account billing.
