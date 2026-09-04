# Agents

One bar pill and one panel for the AI coding subscriptions on this machine.

The panel is strictly a display. It draws the JSON records that
`monarch-agent-usage-update` writes to `~/.local/state/monarch/agents/usage/`,
one per agent, and knows nothing about how the numbers were made. Adding an
agent therefore never touches this plugin: ship a `monarch-agent-usage-<id>`
collector that prints the record contract and the panel gains a button. An
`assets/<id>.svg` mark is optional — with an `assets/<id>-light.svg` twin for
light surfaces — and the generic glyph stands in when there is none.

An agent appears only once its record declares itself `ready`, which the
collectors earn rather than assume: no usage and no limits means no record
drawn, so a machine that has never run an agent shows nothing at all. The bar
pill hides itself on the same rule.

## Collectors

| Collector | Limits | Local stats |
|---|---|---|
| `claude` | Anthropic's OAuth usage endpoint (5-hour session, 7-day weekly) | `~/.claude/projects` transcripts, pi/omp sessions, and opencode sessions on an Anthropic provider |
| `codex` | The Codex app-server RPC | native Codex CLI session files, plus pi and opencode sessions |
| `synthetic` | `GET /v2/quotas` — weekly token credits, subscription requests, web search | none: Synthetic publishes no usage history (see below) |

A non-default Claude directory is honoured via `CLAUDE_CONFIG_DIR`, Codex via
`CODEX_HOME`. Both find their credentials on their own; only Synthetic needs
configuring.

## Configuring Synthetic

Synthetic authenticates with an API key from
[synthetic.new](https://synthetic.new). Either of these works:

**A config file** — the reliable one. Create
`~/.config/monarch/agents/synthetic.json`:

```json
{ "apiKey": "syn_your_key_here" }
```

```bash
mkdir -p ~/.config/monarch/agents
printf '{"apiKey":"%s"}\n' "$SYNTHETIC_API_KEY" > ~/.config/monarch/agents/synthetic.json
chmod 600 ~/.config/monarch/agents/synthetic.json
```

**`SYNTHETIC_API_KEY` in the environment** — convenient in a terminal, but it
only reaches the collector if the *graphical session* exports it. The collector
runs from the Noctalia service, which never sees a shell profile, so an
`export` in `~/.zshrc` will work when you run the command by hand and do
nothing for the panel. Put it in `~/.config/uwsm/env` if you want this route —
that file is read once at login, so the session has to be restarted.

The panel picks the key up on its next refresh — within 15 minutes by default,
or immediately on a right-click of the bar pill.

### Checking it worked

Without a key there is no card to read an error from, by design. Run the
collector by hand instead:

```bash
monarch-agent-usage-synthetic | jq '{ready, usageStatusText, authHelpText, limits}'
```

`ready: true` with a populated `limits` array means the panel will draw it.
`ready: false` says why: `"Waiting for auth"` for a missing key,
`"Synthetic quotas unavailable"` with the error in `authHelpText` for a
rejected one.

### What Synthetic cannot show

The panel's "Last 7 days" and "By model" charts stay absent for Synthetic, and
that is not an oversight: `/v2/quotas` is a point-in-time counter and the API
publishes no history endpoint — every plausible route (`/v2/usage`,
`/v2/activity`, `/v2/billing`, …) answers 404, while routes that do exist
answer 405, which makes the absence conclusive. The record says so with
`hasLocalStats: false`, and the panel then leaves out the counters it cannot
fill rather than printing them as zeroes.

The data exists behind the web dashboard, which serves it from a
session-authenticated Next.js server action whose id is minted at build time.
Neither the API key nor a stable call survives that, so nothing here depends on
it. The fix is upstream: their docs invite requests for more data, and a
`GET /v2/usage` returning the dashboard's `{tokens, requests, models}` shape
would fill both charts with no change to this plugin.

## Refresh

Records regenerate on the service's interval, `refresh_interval_sec` in the
plugin's settings (900 by default, 60 minimum). Right-clicking the bar pill
forces a collection immediately.
