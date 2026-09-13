import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


STOCK_FASTFETCH_HASHES = frozenset({
  "07027778c12914c7077022cc835de4ac6c38af90aed539a871b13c7c89603e87",
  "0bc8cb0a24ec07e786cccbad446fd80b72520e7effd9bff8cfa27b7361211f4b",
  "22565532d139ab8c2ddb21dcfe56460dc9f2f8a712b8d29f125c1c8b29beca37",
  "2378d85bbf03c04c56c7c57b583d10b0047840a7939ccf0bb647854e5183b0ec",
  "2cc59c562e51ed3a58a784a17414ad40699253d0a9522eb7ce01faf6d7cff7c2",
  "3d153225131d3031b99b2e1a07e84d22cd0e51fcae1e701b08f6b6a558bc7a9c",
  "404d0273c380cfdad4a037fa87202fc1d96be178c867e8a9d27b0a772f6e2fa1",
  "4a98ff77ed46109d08ef7301249ea6823d1abba6c39c0871680feebf96620bf2",
  "62fa26fa5fb8e11d31c5ec9f3a53b9b6b1124b29134b19329a092878ff624581",
  "6adebf87d93902fb4bc68824a8e7c71e482846af23fea199e489c5496f791590",
  "89258689d6b0e41a3f126b041ab04e85f5567e527c1433a2b45de81d40962c86",
  "91971c9744c8bb7923bedb04ef76dca39e69302301a3374378f605a65c2aeb32",
  "97aefdea2103d6c73e063bf0d11ad26da8fe60630305ac4eb2970cfc50cb0d91",
  "a9f8b0f6378a122ac28ac872c64e5127141d149d12ef1ec874e8b7397a21776e",
  "abb336459df8dea8f84df1dd54a2f223adec558df3de39cce84ca83f88acc02f",
  "b2e5757851f0703edb8bcfc4b51a00bf5e303c1df26b8c63e6b7df6be4ead4ed",
  "b65cb9ca36eed45929bfc35443762b14957d3847f6bed361a338224a87450e3a",
  "c827c3a24f64c418d309244a8a967def0c522d824addf65d8ee0741afbc970bd",
  "c909b43ba000887cd418d9eaf98c1c9c5ba938aa27f9246cf8fa5662946c4e87",
  "cd380e77a8687b192caec701f032f5914b235f7b61de993fb4946fd5db9a10f8",
  "f1c9a999a4f31a215b10474eeac8894ce6da220d680c30d2aab7b3c1b7a539a6",
  "fa74c9c09e44c88b1fb7ca6f1ea7b7c25bf5f422b7b9b60f7dccd3b07a5377d5",
  "fe61d9f7cfac800adb7bd21f75f1bfcca266c609b6efa02a6e25303ac192e86e",
})


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


def migrate_app(config, runtime, relative, transform, retire_hashes=frozenset()):
  path = config / relative
  if not os.path.lexists(path):
    if retire_hashes:
      return
    publish(path, (runtime / "config" / relative).read_bytes())
    return
  if path.is_symlink() or not path.is_file():
    print(f"Preserving user-managed config: {path}")
    return
  original_bytes = path.read_bytes()
  if hashlib.sha256(original_bytes).hexdigest() in retire_hashes:
    path.unlink()
    return
  original = original_bytes.decode()
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
  migrate_app(
    home / ".config", runtime, "fastfetch/config.jsonc", fastfetch_config,
    STOCK_FASTFETCH_HASHES,
  )


if __name__ == "__main__":
  try:
    main()
  except (OSError, ValueError) as error:
    sys.exit(f"Cannot migrate Noctalia V4 configuration: {error}")
