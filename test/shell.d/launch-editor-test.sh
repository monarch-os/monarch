#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    commands = fixture / "bin"
    commands.mkdir()
    editor = commands / "editor-stub"
    editor.write_text('''#!/bin/bash
printf '%s\\n' "$BASHPID" >"$EDITOR_TEST_CASE/pid"
: >"$EDITOR_TEST_CASE/argv"
for argument in "$@"; do
  printf '%s\\0' "$argument" >>"$EDITOR_TEST_CASE/argv"
done
cat
exit "${EDITOR_TEST_STATUS:-0}"
''')
    editor.chmod(0o755)
    for name in ["nvim", "vim", "nano", "micro", "hx", "helix", "fresh", "code", "subl"]:
        (commands / name).symlink_to(editor)
    for name in ["monarch-launch-tui", "setsid", "uwsm-app"]:
        stub = commands / name
        stub.write_text('''#!/bin/bash
: >"$EDITOR_TEST_CASE/''' + name + '''"
for argument in "$@"; do
  printf '%s\\0' "$argument" >>"$EDITOR_TEST_CASE/''' + name + '''"
done
''' + ('[[ $1 == "--" ]] || exit 99\nshift\n' if name == "uwsm-app" else '') + 'exec "$@"\n')
        stub.chmod(0o755)

    environment = {**os.environ, "HOME": str(fixture / "home"),
                   "MONARCH_PATH": str(root), "PATH": f"{commands}:{root / 'bin'}:/usr/bin"}
    environment.pop("EDITOR", None)
    files = ["file with spaces.md", "-draft.md", "--help", "$(touch unexpected); `id`"]

    def arguments(path):
        return path.read_bytes().rstrip(b"\0").split(b"\0")

    def run(name, selection, inline=False, status=0, dispatcher=False):
        case = fixture / name
        case.mkdir()
        env = {**environment, "EDITOR_TEST_CASE": str(case), "EDITOR_TEST_STATUS": str(status)}
        if selection is not None:
            env["EDITOR"] = selection
        command = [str(root / "bin/monarch"), "launch", "editor"] if dispatcher else [str(root / "bin/monarch-launch-editor")]
        if inline:
            command.append("--inline")
        command.extend(files)
        process = subprocess.Popen(command, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        output, errors = process.communicate(b"editor input\n", timeout=10)
        assert process.returncode == status, (name, process.returncode, errors)
        assert output == b"editor input\n", (name, output, errors)
        assert arguments(case / "argv") == [b"--", *map(os.fsencode, files)], name
        if inline and selection not in ["code", "sublime_text"]:
            assert int((case / "pid").read_text()) == process.pid, name
            assert not (case / "monarch-launch-tui").exists(), name
            assert not (case / "setsid").exists(), name
            assert not (case / "uwsm-app").exists(), name
        elif selection in ["code", "sublime_text"]:
            executable = "subl" if selection == "sublime_text" else selection
            assert arguments(case / "setsid") == [b"uwsm-app", b"--", os.fsencode(executable), b"--", *map(os.fsencode, files)], name
            assert not (case / "monarch-launch-tui").exists(), name
        else:
            assert arguments(case / "monarch-launch-tui") == [os.fsencode(selection), b"--", *map(os.fsencode, files)], name

    for name in ["nvim", "vim", "nano", "micro", "hx", "helix", "fresh"]:
        run(f"inline-{name}", name, inline=True)
    run("inline-absolute", str(commands / "nvim"), inline=True)
    run("inline-unset", None, inline=True)
    run("inline-empty", "", inline=True)
    run("inline-missing", "missing-editor-fixture", inline=True)
    run("inline-failure", "nvim", inline=True, status=7)
    run("inline-dispatch", "nvim", inline=True, dispatcher=True)
    run("window-terminal", "nvim")
    run("window-absolute", str(commands / "nvim"))
    for name in ["code", "sublime_text"]:
        run(f"window-{name}", name)
        run(f"inline-{name}", name, inline=True)
PY

pass "inline terminal editors retain the process, streams, arguments and exit status"
pass "default terminal windows and graphical editors retain their launch paths"
pass "missing editors and legacy Sublime names keep their fallbacks"
