/**
 * Syncs pi's light/dark theme with Noctalia's appearance.
 *
 * Light/dark is owned by Noctalia's global toggle, stored as
 * `colorSchemes.darkMode` in ~/.config/noctalia/settings.json.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = process.env.HOME ?? "";
const noctaliaSettings = join(home, ".config/noctalia/settings.json");

function monarchPiTheme(): "light" | "dark" {
  try {
    const raw = readFileSync(noctaliaSettings, "utf8");
    const darkMode = JSON.parse(raw)?.colorSchemes?.darkMode;
    return darkMode === false ? "light" : "dark";
  } catch {
    return "dark";
  }
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  pi.on("session_start", (_event, ctx) => {
    let currentTheme = monarchPiTheme();
    ctx.ui.setTheme(currentTheme);

    intervalId = setInterval(() => {
      const nextTheme = monarchPiTheme();
      if (nextTheme !== currentTheme) {
        currentTheme = nextTheme;
        ctx.ui.setTheme(currentTheme);
      }
    }, 2000);
  });

  pi.on("session_shutdown", () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  });
}
