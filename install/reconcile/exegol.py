import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile


# Stock files predating the data-only shared environment; customized copies stay user-owned.
LEGACY_HASHES = {
  "setup/zsh/aliases": "2e89c03e5ba9b401b49c5633348964ecf4639d172126e32bdf766a7ebbaf2dde",
  "setup/zsh/zshrc": "27365a06e35811e428b2b727720c1e1a091044ac66010dc9c9648e12f03de7c0",
}


def safe_path(path, home):
  leaf = path
  while path != home:
    if path.is_symlink() or (path != leaf and path.exists() and not path.is_dir()):
      return False
    path = path.parent
  return True


def default_resource_location(text):
  # Only the simple mapping/scalar subset shipped by Monarch is eligible for automatic updates.
  stack = []
  entries = {}
  for line in text.splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
      continue
    match = re.fullmatch(r"( *)([A-Za-z_][A-Za-z0-9_]*):(?: +(.*))?", line.rstrip())
    if not match:
      return False
    indent, key, value = len(match[1]), match[2], match[3]
    while stack and stack[-1][0] >= indent:
      stack.pop()
    if (not stack and indent != 0) or (stack and stack[-1][2] is not None):
      return False
    path = tuple(item[1] for item in stack) + (key,)
    if path in entries:
      return False
    if value is not None and value.startswith("#"):
      value = None
    if value is not None:
      if value.startswith('"'):
        scalar = re.fullmatch(r'("(?:[^"\\]|\\.)*")(?: +#.*)?', value)
        if not scalar:
          return False
        try:
          value = json.loads(scalar[1])
        except ValueError:
          return False
      elif value.startswith("'"):
        scalar = re.fullmatch(r"('(?:[^']|'')*')(?: +#.*)?", value)
        if not scalar:
          return False
        value = scalar[1][1:-1].replace("''", "'")
      else:
        value = value.split(" #", 1)[0].rstrip()
        if not value or value[0] in "|>&*!{[-" or ": " in value:
          return False
    entries[path] = value
    stack.append((indent, key, value))
  return entries.get(("volumes", "my_resources_path")) == "~/.exegol/my-resources"


def publish(source, target):
  target.parent.mkdir(parents=True, exist_ok=True)
  fd, temporary = tempfile.mkstemp(prefix=".monarch-exegol-", dir=target.parent)
  try:
    with os.fdopen(fd, "wb") as output:
      output.write(source.read_bytes())
      os.fchmod(output.fileno(), source.stat().st_mode & 0o777)
    os.replace(temporary, target)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)


def reconcile(root, home, legacy_hashes=LEGACY_HASHES):
  resources = home / ".exegol/my-resources"
  config = home / ".exegol/config.yml"
  if not safe_path(resources, home) or not resources.is_dir():
    return
  if not safe_path(config, home) or not config.is_file():
    return
  if not default_resource_location(config.read_text()):
    print("Keeping custom Exegol resource location; defaults were not deployed.", file=sys.stderr)
    return
  source = root / "default/exegol/my-resources"
  files = ("tools/shared-env.py", "setup/zsh/zshrc", "setup/zsh/aliases")
  for name in files:
    if not (source / name).is_file():
      raise FileNotFoundError(f"Missing Exegol replacement: {name}")
  helper_ready = False
  for name in files:
    target = resources / name
    replacement = source / name
    if name == "setup/zsh/zshrc" and not helper_ready:
      continue
    if not safe_path(target, home) or (target.exists() and not target.is_file()):
      print(f"Keeping custom Exegol path: {target}", file=sys.stderr)
      continue
    if target.exists():
      content = target.read_bytes()
      if content == replacement.read_bytes():
        helper_ready = helper_ready or name == "tools/shared-env.py"
        continue
      if hashlib.sha256(content).hexdigest() != legacy_hashes.get(name):
        print(f"Keeping customized Exegol file: {target}", file=sys.stderr)
        continue
    publish(replacement, target)
    helper_ready = helper_ready or name == "tools/shared-env.py"


if __name__ == "__main__":
  reconcile(Path(sys.argv[1]), Path(sys.argv[2]))
