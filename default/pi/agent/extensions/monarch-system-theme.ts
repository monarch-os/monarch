/**
 * Syncs pi's light/dark theme with Noctalia's appearance.
 *
 * Light/dark is owned by Noctalia's global toggle. v4 kept it as
 * `colorSchemes.darkMode` in settings.json, which this extension read directly;
 * v5 splits its config across every *.toml in ~/.config/noctalia/ plus a mutable
 * state file, so there is no single file to read. `noctalia msg theme-mode-get`
 * is the supported way to ask, and it reports the *resolved* mode — which
 * matters because the setting also accepts "auto".
 */

import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** Falls back to dark when the shell is not running or the mode is unreadable. */
function monarchPiTheme(done: (theme: "light" | "dark") => void): void {
  execFile("noctalia", ["msg", "theme-mode-get"], (error, stdout) => {
    done(!error && stdout.trim() === "light" ? "light" : "dark");
  });
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  pi.on("session_start", (_event, ctx) => {
    let currentTheme: "light" | "dark" = "dark";
    monarchPiTheme((theme) => {
      currentTheme = theme;
      ctx.ui.setTheme(theme);
    });

    // Async now that this shells out, so the poll never blocks pi's event loop.
    intervalId = setInterval(() => {
      monarchPiTheme((nextTheme) => {
        if (nextTheme !== currentTheme) {
          currentTheme = nextTheme;
          ctx.ui.setTheme(nextTheme);
        }
      });
    }, 2000);
  });

  pi.on("session_shutdown", () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  });
}
