#!/bin/bash

set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
python3 - "$ROOT" <<'PY'
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]) / "default/exegol/my-resources"
tool = root / "tools/shared-env.py"
with tempfile.TemporaryDirectory() as directory:
  home = Path(directory)
  rc = home / "zshrc"
  rc.write_text((root / "setup/zsh/zshrc").read_text().replace(
    "/opt/my-resources/tools/shared-env.py", '"' + str(tool) + '"'))
  marker = home / "executed"
  legacy = home / ".shared_env"
  legacy.write_text(f"touch {marker}\n")
  value = 'quotes "\' `touch ' + str(marker) + '` $(touch ' + str(marker) + ') \\ = é\n\n'
  env = {**os.environ, "HOME": str(home), "RC": str(rc), "VALUE": value}

  def shell(code):
    return subprocess.run(["zsh", "-fc", 'source "$RC"; ' + code], env=env, capture_output=True)

  result = shell('setpass "$VALUE" && [[ $PASS == "$VALUE" ]]')
  assert result.returncode == 0, result.stderr
  result = shell('[[ $PASS == "$VALUE" ]] && unset PASS; loadshared; [[ $PASS == "$VALUE" ]]')
  assert result.returncode == 0, result.stderr
  assert not marker.exists() and legacy.exists()
  data = home / ".shared_env.json"
  assert data.stat().st_mode & 0o777 == 0o600
  assert json.loads(data.read_text())["PASS"] == value
  assert shell('setip "10.0.0.1" && [[ $IP == "10.0.0.1" ]]').returncode == 0
  assert shell('setshared EMPTY= && loadshared && [[ ${EMPTY+x} == x && -z $EMPTY ]]').returncode == 0
  before = data.read_bytes()
  for invalid in ('setshared "BAD-NAME=x"', 'setshared noequals', 'setshared A=1 extra', 'setshared PATH=bad'):
    assert shell(invalid).returncode != 0, invalid
    assert data.read_bytes() == before

  def write(index):
    result = subprocess.run([sys.executable, str(tool), str(data), "set"],
                            input=f"ITEM_{index}={index}".encode(), capture_output=True)
    assert result.returncode == 0, result.stderr

  with ThreadPoolExecutor(max_workers=8) as pool:
    list(pool.map(write, range(20)))
  saved = json.loads(data.read_text())
  assert all(saved[f"ITEM_{index}"] == str(index) for index in range(20))
  data.write_text('{"IP": "new", "BAD-NAME": "bad"}')
  result = shell('IP=old; loadshared; result=$?; [[ $result != 0 && $IP == old ]]')
  assert result.returncode == 0, result.stderr
  data.write_bytes(before)
  assert shell('clearshared && [[ ! -e $SHARED_ENV_FILE ]]').returncode == 0
  assert legacy.exists() and not marker.exists()
  target = home / "keep"
  target.write_text("untouched")
  data.symlink_to(target)
  assert shell('setip 10.0.0.2').returncode != 0
  assert target.read_text() == "untouched"
print("PASS: literal shared values, startup reload, legacy isolation, validation, private atomic concurrent writes")
PY
