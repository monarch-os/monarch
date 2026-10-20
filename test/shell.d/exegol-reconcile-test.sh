#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
python3 - "$ROOT" <<'PY'
import hashlib
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile

root = Path(sys.argv[1])
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("exegol_reconcile", root / "install/reconcile/exegol.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for value in ("~/.exegol/my-resources", "'~/.exegol/my-resources'",
              '"~/.exegol/my-resources"', "~/.exegol/my-resources # default"):
  assert module.default_resource_location(f"volumes:\n  my_resources_path: {value}\n")
for config_text in (
    "volumes:\n  my_resources_path: ~/personal-resources\nnotes: |\n  my_resources_path: ~/.exegol/my-resources\n",
    "notes:\n  my_resources_path: ~/.exegol/my-resources\n",
    "volumes:\n  nested:\n    my_resources_path: ~/.exegol/my-resources\n",
    "volumes:\n  my_resources_path: ~/.exegol/my-resources\n  my_resources_path: ~/personal-resources\n",
    "volumes:\n  my_resources_path: ~/.exegol/my-resources\nvolumes:\n  my_resources_path: ~/personal-resources\n",
    "volumes:\n  my_resources_path: &path ~/.exegol/my-resources\n",
    "volumes:\n  <<: *custom\n  my_resources_path: ~/.exegol/my-resources\n"):
  assert not module.default_resource_location(config_text), config_text
assert 'python3 -I "$MONARCH_PATH/install/reconcile/exegol.py" "$MONARCH_PATH" "$HOME"' in (
  root / "install/reconcile/user.sh").read_text()
with tempfile.TemporaryDirectory() as directory:
  temporary = Path(directory)
  absent = temporary / "absent"
  absent.mkdir()
  module.reconcile(root, absent)
  assert not (absent / ".exegol").exists()
  home = temporary / "home"
  resources = home / ".exegol/my-resources"
  (resources / "setup/zsh").mkdir(parents=True)
  config = home / ".exegol/config.yml"
  shutil.copy(root / "default/exegol/config.yml", config)
  # Synthetic old defaults exercise ownership recognition without requiring Git history in CI.
  originals = {"setup/zsh/zshrc": b"# original zshrc\n", "setup/zsh/aliases": b"# original aliases\n"}
  fingerprints = {name: hashlib.sha256(content).hexdigest() for name, content in originals.items()}
  for name, content in originals.items():
    (resources / name).write_bytes(content)
  custom = resources / "personal.txt"
  custom.write_text("keep me")
  module.reconcile(root, home, fingerprints)
  files = (*originals, "tools/shared-env.py")
  for name in files:
    assert (resources / name).read_bytes() == (root / "default/exegol/my-resources" / name).read_bytes()
  inodes = [(resources / name).stat().st_ino for name in files]
  module.reconcile(root, home, fingerprints)
  assert inodes == [(resources / name).stat().st_ino for name in files]
  assert custom.read_text() == "keep me"
  for name in files:
    (resources / name).write_text("# user customization\n")
  module.reconcile(root, home, fingerprints)
  assert all((resources / name).read_text() == "# user customization\n" for name in files)
  (resources / "setup/zsh/zshrc").write_bytes(originals["setup/zsh/zshrc"])
  module.reconcile(root, home, fingerprints)
  assert (resources / "setup/zsh/zshrc").read_bytes() == originals["setup/zsh/zshrc"]
  (resources / "tools/shared-env.py").unlink()
  target = temporary / "untouched"
  target.write_text("keep")
  (resources / "tools/shared-env.py").symlink_to(target)
  module.reconcile(root, home, fingerprints)
  assert target.read_text() == "keep"
  assert (resources / "setup/zsh/zshrc").read_bytes() == originals["setup/zsh/zshrc"]
  (resources / "tools/shared-env.py").unlink()
  for location in ("~/personal-resources", "~/xexegol/my-resources"):
    config.write_text(f"volumes:\n  my_resources_path: {location}\n")
    module.reconcile(root, home, fingerprints)
    assert not (resources / "tools/shared-env.py").exists()
  shutil.copy(root / "default/exegol/config.yml", config)
  incomplete = temporary / "incomplete"
  (incomplete / "default/exegol/my-resources").mkdir(parents=True)
  try:
    module.reconcile(incomplete, home, fingerprints)
  except FileNotFoundError:
    pass
  else:
    raise AssertionError("missing replacement was accepted")
  assert not (resources / "tools/shared-env.py").exists()
  # A symlinked parent is also user-owned, even if its leaves look like stock files.
  (resources / "tools").rmdir()
  outside = temporary / "outside-tools"
  outside.mkdir()
  (resources / "tools").symlink_to(outside, target_is_directory=True)
  module.reconcile(root, home, fingerprints)
  assert not (outside / "shared-env.py").exists()
  (resources / "tools").unlink()
  (resources / "tools").write_text("custom regular file")
  module.reconcile(root, home, fingerprints)
  assert (resources / "tools").read_text() == "custom regular file"
  assert (resources / "setup/zsh/zshrc").read_bytes() == originals["setup/zsh/zshrc"]
print("PASS: Exegol resource upgrade, idempotence, custom files and paths, dependency-first deployment")
PY
