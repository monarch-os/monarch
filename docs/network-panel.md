# Network panel contracts

The Luau panel presents connection actions; `monarch-wifi-panel` owns NetworkManager identity and credential transport. Its Python implementation uses PyGObject/Gio on the system bus. Listing never requests secrets. NetworkManager continues to enforce the caller's session permissions; the helper does not elevate privileges.

## Identity and state

The snapshot is JSON with `enabled`, `present` and `networks`. Each row carries a stable key (interface, SSID bytes in hex, security class), display SSID, UUID, BSSID and interface. Saved profiles are matched by wireless SSID and compatible security, not by connection name; interface, BSSID and band restrictions must also match. The active compatible UUID takes precedence; otherwise the most recently used profile wins deterministically. Active BSS measurements take precedence over a stronger inactive BSS. For disconnected networks, an AP compatible with a saved profile takes precedence over a stronger incompatible AP; signal breaks ties. Incompatible security classes remain separate rows.

Join revalidates the requested row, BSSID and UUID. Disconnect targets the active connection object matching the requested interface and UUID, so a stale row cannot disconnect its replacement. Forget deletes precisely the selected Wi-Fi UUID. Renamed and duplicate profiles remain intact unless explicitly selected for deletion.

Noctalia's plugin API has no network subscription surface. The panel and bar therefore use an `nmcli monitor` stream; the panel coalesces notifications on its existing statistics tick. Periodic reads also recover state if an event is missed. Each resource has one outstanding read and stale generations are ignored. Closing a panel does not release an outstanding action lock. Lists retain their order while a credential form is open; action helpers still revalidate frozen targets.

## Credentials

Noctalia's subprocess API has no stdin parameter. Before submission, the helper creates a random mode-0700 temporary directory under the runtime directory (or the system temporary directory when unavailable). Luau writes one JSON request there, then launches the helper with only its path. The helper validates ownership and directory permissions, rejects symlink/nonregular request files, bounds request size, reads and deletes the request and directory before activation. Completion and launch/write failure paths also discard the owned request. A shell crash can leave a private request in the runtime directory until session cleanup.

Passwords travel to NetworkManager through D-Bus settings, never shell arguments. A password repair updates the same UUID and preserves unrelated settings and EAP secrets. A failed activation retains the profile so the user can correct it without forgetting it. Newly configured Enterprise profiles require an identity, CA certificate and server-domain constraint; existing profiles must also have explicit server validation. Certificate-based EAP profiles can be reused without recreating their authentication method.

`monarch wifi join <ssid> --password-stdin` replaces the former password argument. Ambiguous CLI targets are refused rather than guessed. The Enterprise CLI accepts SSID, identity, CA path and server domain, with its password on stdin. Do not place a literal password in shell history when using either command.

## Diagnostics and limits

Scans preserve actionable errors and the last usable list. Limited connectivity is debounced for three seconds; captive portal state is immediate, and disabled connectivity checks report unknown. Latency averages the last five valid-or-timeout samples within the loss window; missing measurements clear stale samples. SSID identity comes from NetworkManager rather than comparing escaped `iw` text with raw names.

QR sharing is hidden for Enterprise and OWE. The QR helper explicitly reports OWE as unsupported rather than requesting a nonexistent secret. Band changes retain UUID identity and report a failed rollback separately from a successful restoration. Activation waits are bounded; a timed-out join cancels only its still-pending activation, never a replacement or an established connection.

## Validation

`test/monarch-network-panel-test.sh` exercises the actual panel logic with simulated asynchronous completions and the Python helper's actual grouping, identity, credential update and request-file paths. The fixture uses Lua-compatible transformation of Luau; this does not replace a real Noctalia rendering check. The network, controls, band, QR and option-boundary suites cover the Bash contracts. No test requires a real radio or saved credentials.
