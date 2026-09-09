import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


def publish(path, data, mode=0o644, replace=False):
  if not replace and os.path.lexists(path):
    return
  path.parent.mkdir(parents=True, exist_ok=True)
  fd, temporary = tempfile.mkstemp(prefix=".monarch-v4-", dir=path.parent)
  try:
    with os.fdopen(fd, "wb") as output:
      output.write(data)
      os.fchmod(output.fileno(), mode)
    if replace:
      os.replace(temporary, path)
    else:
      try:
        os.link(temporary, path)
      except FileExistsError:
        pass
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)


def migrate_app(config, runtime, relative, transform):
  path = config / relative
  if not os.path.lexists(path):
    publish(path, (runtime / "config" / relative).read_bytes())
    return
  if path.is_symlink() or not path.is_file():
    print(f"Preserving user-managed config: {path}")
    return
  original = path.read_bytes().decode()
  updated = transform(original)
  if updated == original:
    return
  mode = stat.S_IMODE(path.stat().st_mode)
  backup = path.with_name(path.name + ".bak.monarch-v5")
  if os.path.lexists(backup) and (backup.is_symlink() or backup.read_bytes() != original.encode()):
    raise ValueError(f"Cannot preserve original config: {backup} already exists")
  publish(backup, original.encode(), mode)
  publish(path, updated.encode(), mode, replace=True)


def herdr_config(text, runtime):
  normalized = text
  for key, token in (("panel_bg", "surface_container"), ("accent", "primary")):
    normalized = re.sub(
      rf'(?m)^({key}\s*=\s*")#[0-9a-fA-F]{{6}}("\s*)$',
      lambda match: match[1] + "{{colors." + token + ".default.hex}}" + match[2],
      normalized,
    )
  # Only the unmodified V4 template output is owned by Monarch.
  if hashlib.sha256(normalized.encode()).hexdigest() == "3959426bdc72aab761291e1c6e8d571fb11af7f3e41c2b294769cf6ae0069075":
    return (runtime / "config/herdr/config.toml").read_text()
  return text


def fastfetch_config(text):
  old = 'theme=$(jq -r \'.colorSchemes.predefinedScheme // "Monarch"\' ~/.config/noctalia/settings.json 2>/dev/null);'
  new = "theme=$(noctalia msg color-scheme-get 2>/dev/null | cut -d' ' -f2-); theme=${theme:-Monarch};"

  def update(match):
    token = match[0]
    if not token.startswith('"'):
      return token
    value = json.loads(token)
    if not value.startswith(old):
      return token
    return json.dumps(new + value[len(old):], ensure_ascii=False)

  return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"', update, text)


def read_settings(config, archive):
  path = config / "settings.json"
  if not os.path.lexists(path):
    path = archive / "settings.json"
  if not os.path.lexists(path):
    return {}
  value = json.loads(path.read_text())
  if not isinstance(value, dict):
    raise ValueError(f"Expected a settings object: {path}")
  return value


def migrate_palettes(config, archive, runtime):
  source = config / "colorschemes"
  if not source.exists():
    source = archive / "colorschemes"
  names = {}
  paths = sorted(source.glob("*/*.json"))
  reserved = {path.parent.name for path in paths}
  reserved.update(path.stem for path in (runtime / "config/noctalia/palettes").glob("*.json"))
  for path in paths:
    name = path.parent.name
    # V4 stores each scheme in <name>/<name>.json, not its metadata JSON.
    if path.name != name + ".json":
      continue
    data = path.read_bytes()
    try:
      palette = json.loads(data)
      valid = isinstance(palette, dict) and isinstance(palette.get("dark"), dict)
    except (ValueError, UnicodeError):
      valid = False
    if not valid:
      print(f"Keeping incompatible palette in the V4 archive: {path}", file=sys.stderr)
      continue
    packaged = runtime / "config/noctalia/palettes" / path.name
    if packaged.exists():
      if json.loads(packaged.read_bytes()) == palette:
        names[name] = name
        publish(config / "palettes" / path.name, data)
        continue
      name = "V4-" + name
      while name in reserved:
        name = "V4-" + name
    names[path.parent.name] = name
    publish(config / "palettes" / (name + ".json"), data)
  return names


def preferences(settings, palettes, runtime):
  sections = {}
  colors = settings.get("colorSchemes", {})
  if not isinstance(colors, dict):
    raise ValueError("Expected colorSchemes to be an object")
  theme = {}
  if type(colors.get("darkMode")) is bool:
    theme["mode"] = "dark" if colors["darkMode"] else "light"
  scheme = colors.get("predefinedScheme")
  builtin = {"Ayu", "Catppuccin", "Dracula", "Eldritch", "Gruvbox", "Kanagawa",
             "Noctalia", "Nord", "Rosé Pine", "Tokyo-Night"}
  shipped = {path.stem for path in (runtime / "config/noctalia/palettes").glob("*.json")}
  if colors.get("useWallpaperColors") is True:
    theme["source"] = "wallpaper"
  elif isinstance(scheme, str):
    if scheme in palettes or scheme in shipped:
      theme.update(source="custom", custom_palette=palettes.get(scheme, scheme))
    elif scheme in builtin:
      theme.update(source="builtin", builtin=scheme)
    else:
      print(f"No compatible V5 palette for {scheme!r}; keeping the V4 archive", file=sys.stderr)
  if theme:
    sections["theme"] = theme

  idle = settings.get("idle", {})
  if not isinstance(idle, dict):
    raise ValueError("Expected idle to be an object")
  enabled = idle.get("enabled", True)
  if type(enabled) is not bool:
    raise ValueError("Expected idle.enabled to be a boolean")
  for old, name, action in (("lockTimeout", "lock", "lock"),
                            ("screenOffTimeout", "screen-off", "screen_off"),
                            ("suspendTimeout", "suspend", "lock_and_suspend")):
    if old not in idle and enabled:
      continue
    behavior = {"action": action, "enabled": enabled}
    if old in idle:
      timeout = idle[old]
      if type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout < 0:
        raise ValueError(f"Invalid idle timeout: {old}")
      behavior.update(timeout=timeout, enabled=enabled and timeout > 0)
    sections[f'idle.behavior."{name}"'] = behavior

  commands = idle.get("customCommands")
  if isinstance(commands, str):
    commands = json.loads(commands)
  if commands is not None and not isinstance(commands, list):
    raise ValueError("Expected idle.customCommands to be a list")
  if commands is not None or not enabled:
    sections["idle.behavior.screensaver"] = {"enabled": False}
  for index, command in enumerate(commands or []):
    timeout = command.get("timeout") if isinstance(command, dict) else None
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or timeout < 0:
      raise ValueError("Invalid custom idle timeout")
    value, resume = command.get("command"), command.get("resumeCommand", "")
    if not isinstance(value, str) or not isinstance(resume, str):
      raise ValueError("Invalid custom idle command")
    name = "screensaver" if value == "monarch-launch-screensaver" else f"v4-command-{index}"
    behavior = {"action": "command", "enabled": enabled and timeout > 0,
                "timeout": timeout, "command": value}
    if resume or name != "screensaver":
      behavior["resume_command"] = resume
    sections[f"idle.behavior.{name}"] = behavior
  return sections


def toml(sections):
  text = ""
  for name, values in sections.items():
    text += f"[{name}]\n"
    text += "".join(f"{key} = {json.dumps(value, ensure_ascii=False)}\n" for key, value in values.items())
    text += "\n"
  return text.encode()


def main():
  home = Path.home()
  runtime = Path(os.environ["MONARCH_PATH"])
  config = home / ".config/noctalia"
  archive = home / ".local/state/monarch/reconcile/1-to-2/legacy-noctalia-config"
  settings = read_settings(config, archive)
  palettes = migrate_palettes(config, archive, runtime)
  prefs = preferences(settings, palettes, runtime)
  if prefs:
    publish(config / "monarch-v4.toml", toml(prefs))
  bar = settings.get("bar", {})
  if isinstance(bar, dict) and bar.get("position") in ("top", "bottom", "left", "right"):
    publish(config / "zz-monarch-bar-position.toml", toml({"bar.default": {"position": bar["position"]}}))
  migrate_app(home / ".config", runtime, "herdr/config.toml", lambda text: herdr_config(text, runtime))
  migrate_app(home / ".config", runtime, "fastfetch/config.jsonc", fastfetch_config)


if __name__ == "__main__":
  try:
    main()
  except (OSError, ValueError) as error:
    sys.exit(f"Cannot migrate Noctalia V4 configuration: {error}")
