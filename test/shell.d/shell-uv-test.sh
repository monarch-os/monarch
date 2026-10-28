#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

python3 <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(os.environ["ROOT"])
real_uv = shutil.which("uv")
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    tools = fixture / "bin"
    tools.mkdir()
    empty_path = fixture / "empty-path"
    empty_path.mkdir()
    calls = fixture / "calls"
    presence_calls = fixture / "presence-calls"
    runtime = fixture / "runtime"
    (runtime / "bin").mkdir(parents=True)
    presence = runtime / "bin/monarch-cmd-present"
    presence.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$PRESENCE_CALLS"\n'
                        '[[ -z ${PRESENCE_STATUS:-} ]] || exit "$PRESENCE_STATUS"\n'
                        'exec "$ROOT/bin/monarch-cmd-present" "$@"\n')
    presence.chmod(0o755)
    stub = tools / "uv"
    stub.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
with open(os.environ["UV_CALLS"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
code = int(os.environ.get("UV_STATUS", "0"))
if not code and sys.argv[1:3] == ["venv", ".venv"]:
    activation = Path(".venv/bin/activate")
    activation.parent.mkdir(parents=True)
    activation.write_text('export VIRTUAL_ENV="$PWD/.venv"\\nexport UV_ACTIVATED=yes\\n')
sys.exit(code)
''')
    stub.chmod(0o755)
    env = {**os.environ, "MONARCH_PATH": str(runtime), "UV_CALLS": str(calls),
           "PRESENCE_CALLS": str(presence_calls),
           "PATH": f"{tools}:{os.environ['PATH']}"}
    load = ('source "$ROOT/default/shells/fns/python-uv"; '
            'source "$ROOT/default/shells/fns/python-uv"; ')

    for shell in ("bash", "zsh"):
        shell_path = shutil.which(shell)
        if not shell_path:
            print(f"SKIP: {shell} is unavailable")
            continue
        flags = "-fc" if shell == "zsh" else "-c"
        workspace = fixture / f"{shell} workspace"
        workspace.mkdir()

        def run(program, args=(), extra=None, expected=0):
            calls.write_text("")
            presence_calls.write_text("")
            result = subprocess.run([shell_path, flags, program, "uv-test", *args],
                                    cwd=workspace, env={**env, **(extra or {})}, capture_output=True)
            assert result.returncode == expected, (shell, program, result.stderr, result.returncode)
            assert presence_calls.read_text().splitlines() == ["uv", "uv"]
            return result, [json.loads(line) for line in calls.read_text().splitlines()]

        literal = ("script with spaces.py", "$(not-executed)", "a'b", "line\nbreak", "")
        for name, prefix in (
            ("uvr", ["run"]),
            ("uvreq", ["pip", "install", "-r", "requirements.txt"]),
            ("uvpwn", ["run", "--isolated", "--no-project", "--with", "pwntools", "python"]),
        ):
            result, recorded = run(load + '"$@"', args=(name, *literal))
            assert recorded == [[*prefix, *literal]], recorded
            run(load + '"$@"', args=(name,), extra={"UV_STATUS": "17"}, expected=17)

        result, recorded = run(load + 'uvv && printf "%s|%s" "$UV_ACTIVATED" "$VIRTUAL_ENV"')
        assert result.stdout == f"yes|{workspace}/.venv".encode()
        assert recorded == [["venv", ".venv"]], recorded
        activation = workspace / ".venv/bin/activate"
        before = activation.stat().st_ino
        result, recorded = run(load + 'uvv && printf "%s" "$UV_ACTIVATED"')
        assert result.stdout == b"yes" and not recorded
        assert activation.stat().st_ino == before
        result, recorded = run(load + 'uvv custom', expected=2)
        assert b"Usage:" in result.stderr and not recorded
        activation.unlink()
        result, recorded = run(load + 'uvv', expected=1)
        assert b"existing files were left unchanged" in result.stderr and not recorded
        (workspace / ".venv/bin").rmdir()
        (workspace / ".venv").rmdir()
        result, recorded = run(load + 'uvv; code=$?; printf "%s" "${UV_ACTIVATED:-no}"; exit "$code"',
                               extra={"UV_STATUS": "17"}, expected=17)
        assert result.stdout == b"no" and not (workspace / ".venv").exists()

        result, recorded = run(
            'alias uvr="printf user-owned"; ' + load +
            'for name in uvv uvreq uvpwn; do command -v "$name" && exit 1; done; alias uvr',
            extra={"PATH": str(empty_path)},
        )
        assert b"user-owned" in result.stdout and not recorded

        result, recorded = run(
            'alias uvr="printf user-owned"; ' + load +
            'for name in uvv uvreq uvpwn; do command -v "$name" && exit 1; done; alias uvr',
            extra={"PRESENCE_STATUS": "1"},
        )
        assert b"user-owned" in result.stdout and not recorded

        if real_uv:
            runtime_path = str(Path(real_uv).parent) + ":" + os.environ["PATH"]
            result, recorded = run(
                load + 'uvv && printf "%s" "$VIRTUAL_ENV"',
                extra={"PATH": runtime_path, "UV_OFFLINE": "1", "UV_PYTHON_DOWNLOADS": "never",
                       "UV_PYTHON": sys.executable, "UV_CACHE_DIR": str(fixture / "cache")},
            )
            assert result.stdout == str(workspace / ".venv").encode(), result.stdout
            assert (workspace / ".venv/bin/python").exists() and not recorded
        print(f"PASS: {shell} uv argument forwarding, activation, preservation, errors and optional loading")

    zsh = shutil.which("zsh")
    if zsh:
        startup = fixture / "startup"
        (startup / "default/zsh").mkdir(parents=True)
        (startup / "default/shells").mkdir(parents=True)
        (startup / "bin").mkdir()
        shutil.copy(root / "default/zsh/rc", startup / "default/zsh/rc")
        shutil.copy(root / "default/shells/envs", startup / "default/shells/envs")
        shutil.copy(root / "bin/monarch-cmd-present", startup / "bin/monarch-cmd-present")
        for file in ("default/zsh/shell", "default/zsh/inputrc", "default/shells/init", "default/shells/aliases"):
            (startup / file).write_text(":\n")
        (startup / "default/shells/functions").write_text('source "$ROOT/default/shells/fns/python-uv"\n')
        for location in (".local/bin", ".local/share/mise/shims"):
            home = fixture / ("home-" + location.replace("/", "-"))
            uv = home / location / "uv"
            uv.parent.mkdir(parents=True)
            uv.write_text("#!/bin/bash\nexit 0\n")
            uv.chmod(0o755)
            result = subprocess.run(
                [zsh, "-fc", 'source "$MONARCH_PATH/default/zsh/rc"; '
                 'for name in uv uvv uvr uvreq uvpwn; do '
                 'command -v "$name" >/dev/null || { print -u2 "Missing after Zsh startup: $name"; exit 1; }; done'],
                env={"ROOT": str(root), "HOME": str(home), "MONARCH_PATH": str(startup),
                     "PATH": str(empty_path), "EDITOR": "vi"},
                capture_output=True,
            )
            assert result.returncode == 0, (location, result.stderr)
        print("PASS: Zsh startup discovers uv helpers in both supported user install locations")
PY
