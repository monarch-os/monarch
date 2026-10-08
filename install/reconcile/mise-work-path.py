import copy
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import tomllib


def reconcile(path):
  if path.is_symlink():
    return
  try:
    original = path.read_bytes().decode("utf-8")
    config = tomllib.loads(original)
  except (UnicodeDecodeError, tomllib.TOMLDecodeError):
    print(f"Keeping invalid user mise configuration: {path}", file=sys.stderr)
    return
  environment = config.get("env")
  directive = environment.get("_") if isinstance(environment, dict) else None
  if not isinstance(directive, dict) or directive.get("path") != "{{ cwd }}/bin":
    return

  expected = copy.deepcopy(config)
  expected["env"]["_"]["path"] = []
  strings = re.compile(r'"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\\n])*"|\x27[^\x27\n]*\x27')
  for match in strings.finditer(original):
    candidate = original[:match.start()] + "[]" + original[match.end():]
    try:
      if tomllib.loads(candidate) != expected:
        continue
    except tomllib.TOMLDecodeError:
      continue

    mode = stat.S_IMODE(path.stat().st_mode)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=path.parent, prefix=".monarch-mise-", delete=False) as stage:
      temporary = Path(stage.name)
      stage.write(candidate)
    try:
      os.chmod(temporary, mode)
      if path.is_symlink() or path.read_bytes().decode("utf-8") != original:
        raise RuntimeError(f"mise configuration changed during reconciliation: {path}")
      os.replace(temporary, path)
    finally:
      temporary.unlink(missing_ok=True)
    return
  raise RuntimeError(f"Could not safely remove the generated project PATH: {path}")


reconcile(Path(sys.argv[1]))
