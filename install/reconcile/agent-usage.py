import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


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
plugin = home / ".local/share/noctalia/plugins/monarch-agents"
if plugin.is_symlink() or not (plugin / "service.luau").is_file():
  raise SystemExit(0)
config_home = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
state_home = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
config = Path(os.environ.get("CODEXBAR_CONFIG") or config_home / "codexbar/config.json")
legacy = home / ".codexbar/config.json"
backup = state_home / "monarch/backups/noctalia/monarch-agents"
if backup.is_symlink() or (backup.exists() and subprocess.run(
  ["diff", "-qr", "--no-dereference", str(plugin), str(backup)],
  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
).returncode != 0):
  raise RuntimeError(f"Legacy agent plugin backup already exists: {backup}")

if not config.exists() and not config.is_symlink() and not legacy.exists() and not legacy.is_symlink():
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

subprocess.run(["codexbar", "config", "validate"], check=True, stdout=subprocess.DEVNULL)
backup.parent.mkdir(parents=True, exist_ok=True)
if not backup.exists():
  staging = Path(tempfile.mkdtemp(prefix=".monarch-agents-", dir=backup.parent))
  try:
    shutil.copytree(plugin, staging, dirs_exist_ok=True, symlinks=True)
    staging.rename(backup)
  finally:
    if staging.exists():
      shutil.rmtree(staging)
