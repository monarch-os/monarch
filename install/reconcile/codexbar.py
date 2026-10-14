import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import tomllib


def write_atomic(path, content, mode):
  path.parent.mkdir(parents=True, exist_ok=True)
  fd, temporary = tempfile.mkstemp(prefix=".codexbar-", dir=path.parent)
  try:
    os.fchmod(fd, mode)
    with os.fdopen(fd, "w") as stream:
      stream.write(content)
    os.replace(temporary, path)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)


home = Path.home()
config_home = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
state_home = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
config = Path(os.environ.get("CODEXBAR_CONFIG") or config_home / "codexbar/config.json")
legacy = home / ".codexbar/config.json"

if not config.exists() and not config.is_symlink() and not legacy.exists():
  providers = []
  for provider, directory in (
    ("claude", Path(os.environ.get("CLAUDE_CONFIG_DIR") or home / ".claude")),
    ("codex", Path(os.environ.get("CODEX_HOME") or home / ".codex")),
  ):
    disabled = (state_home / "monarch/agents/disabled" / provider).exists()
    providers.append({"id": provider, "enabled": directory.is_dir() and not disabled,
                      "source": "cli" if provider == "codex" else "oauth"})
  synthetic = config_home / "monarch/agents/synthetic.json"
  if synthetic.exists():
    key = json.loads(synthetic.read_text()).get("apiKey")
    if key:
      providers.append({"id": "synthetic", "apiKey": key,
                        "enabled": not (state_home / "monarch/agents/disabled/synthetic").exists()})
  write_atomic(config, json.dumps({"version": 1, "providers": providers}) + "\n", 0o600)

files = list((config_home / "noctalia").glob("*.toml"))
files.append(state_home / "noctalia/settings.toml")
for path in files:
  if not path.is_file() or path.is_symlink():
    continue
  old = path.read_text()
  new = old
  for entry in ("monarch/agent:usage", "salemsayed/codexbar-meter:bar"):
    new = new.replace('"' + entry + '"', '"monarch/agents:usage"')
    new = new.replace("'" + entry + "'", "'monarch/agents:usage'")
  new = new.replace('[plugin_settings."monarch/agent"]', '[plugin_settings."monarch/agents"]')
  new = new.replace("[plugin_settings.'monarch/agent']", "[plugin_settings.'monarch/agents']")
  sections = re.split(r"(?m)(?=^\[)", new)
  for index, section in enumerate(sections):
    if not section.startswith("[plugins]\n"):
      continue
    enabled = tomllib.loads(section).get("plugins", {}).get("enabled", [])
    if not any(name in enabled for name in ("monarch/agent", "salemsayed/codexbar-meter")):
      continue
    enabled = list(dict.fromkeys(
      "monarch/agents" if name in ("monarch/agent", "salemsayed/codexbar-meter") else name
      for name in enabled
    ))
    sections[index] = re.sub(r"(?ms)^enabled\s*=\s*\[.*?\]",
                             "enabled = " + json.dumps(enabled), section, count=1)
  new = "".join(sections)
  if new != old:
    backup = path.with_name(path.name + ".before-codexbar")
    if not backup.exists():
      shutil.copy2(path, backup)
    write_atomic(path, new, path.stat().st_mode & 0o777)

plugin = home / ".local/share/noctalia/plugins/monarch-agents"
backup = state_home / "monarch/backups/noctalia/monarch-agents"
if (plugin / "service.luau").is_file() and not plugin.is_symlink() and not backup.exists():
  backup.parent.mkdir(parents=True, exist_ok=True)
  plugin.rename(backup)
