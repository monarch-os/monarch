import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile


RESERVED_NAMES = {
  "SHARED_ENV_FILE", "PATH", "FPATH", "ENV", "BASH_ENV", "ZDOTDIR", "IFS",
  "HOME", "SHELLOPTS", "PS4", "PROMPT", "RPROMPT",
  # Assigning Zsh credential parameters changes process identity; others are read-only.
  "UID", "EUID", "GID", "EGID", "USERNAME", "ARGC", "HISTCMD", "LINENO",
  "PPID", "TTYIDLE", "ZSH_EVAL_CONTEXT", "ZSH_SUBSHELL",
}


def validate(data):
  if not isinstance(data, dict):
    raise ValueError("expected an object of environment variables")
  for name, value in data.items():
    if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", name):
      raise ValueError("variable names must use uppercase letters, digits and underscores")
    if name in RESERVED_NAMES or name.startswith("LD_"):
      raise ValueError(f"{name} cannot be shared")
    if not isinstance(value, str) or "\0" in value:
      raise ValueError("values must be strings without NUL bytes")
  return data


def read(path):
  if path.is_symlink():
    raise ValueError("refusing a symlinked shared environment")
  try:
    return validate(json.loads(path.read_text(encoding="utf-8")))
  except FileNotFoundError:
    return {}


def main():
  path = Path(sys.argv[1])
  action = sys.argv[2]
  if action in ("set", "clear"):
    os.umask(0o077)
    lock = os.open(str(path) + ".lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock, "w") as handle:
      fcntl.flock(handle, fcntl.LOCK_EX)
      if action == "clear":
        if path.is_symlink():
          raise ValueError("refusing a symlinked shared environment")
        path.unlink(missing_ok=True)
        return
      data = read(path)
      name, separator, value = sys.stdin.read().partition("=")
      if not separator:
        raise ValueError("expected VARIABLE=value")
      data.update(validate({name: value}))
      fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
      try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
          json.dump(data, output, ensure_ascii=True)
          output.write("\n")
        os.replace(temporary, path)
      finally:
        if os.path.exists(temporary):
          os.unlink(temporary)
  else:
    data = read(path)
    if action == "load":
      sys.stdout.buffer.write("\0".join(f"{name}={value}" for name, value in data.items()).encode("utf-8") + b"\0")
    elif action == "list":
      print(json.dumps(data, ensure_ascii=True, indent=2))
    else:
      raise ValueError("unknown shared environment action")


if __name__ == "__main__":
  try:
    main()
  except (OSError, ValueError, UnicodeError) as error:
    sys.exit(f"shared environment: {error}")
