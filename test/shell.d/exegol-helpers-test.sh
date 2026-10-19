#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

python3 - "$ROOT" <<'PY'
import ast
import os
from pathlib import Path
import shutil
import subprocess
import sys

aliases = Path(sys.argv[1]) / "default/exegol/my-resources/setup/zsh/aliases"
for shell in ("bash", "zsh"):
  if not shutil.which(shell):
    raise SystemExit(f"Required test shell missing: {shell}")

  def run(name, data=b"", *args):
    return subprocess.run(
      [shell, "-fc", 'source "$ALIASES"; source "$ALIASES"; "$@"', "test", name, *args],
      env={**os.environ, "ALIASES": str(aliases)}, input=data, capture_output=True,
    )

  original = 'é <&> " \\ \t\n\n\x00'.encode()
  encoded = run("jsonescape", original)
  assert encoded.returncode == 0, encoded.stderr
  decoded = run("jsonunescape", encoded.stdout)
  assert decoded.returncode == 0 and decoded.stdout == original, decoded
  assert run("jsonescape", b"ignored", "").stdout == b'""'
  assert run("jsonescape", b"", "-n").stdout == b'"-n"'
  assert run("jsonunescape", b'""').returncode == 0
  payload = bytes(range(256))
  result = run("hex2py", payload.hex().encode())
  assert result.returncode == 0 and ast.literal_eval(result.stdout.decode()) == payload
  assert run("hex2c", b"", "00 ff 0a").stdout == b"{0x00, 0xff, 0x0a}"
  for name, data in (("hex2py", b"001"), ("hex2c", b"00gg"),
                     ("jsonunescape", b"{}"), ("jsonunescape", b'"ok" "extra"'),
                     ("jsonunescape", b'"ok" broken'), ("jsonunescape", b"")):
    result = run(name, data)
    assert result.returncode != 0 and not result.stdout and result.stderr, (name, result)
  for name in ("jsonescape", "jsonunescape", "hex2py", "hex2c"):
    assert run(name, b"", "one", "two").returncode != 0
  print(f"PASS: {shell} Exegol helpers, reloads, stdin, argument boundaries and invalid input")
PY
