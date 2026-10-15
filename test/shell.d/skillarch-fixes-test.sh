#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

python3 <<'PY'
import json
import os
import pty
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(os.environ["ROOT"])
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    tools = fixture / "bin"
    tools.mkdir()
    log = fixture / "calls"
    stub = '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + "\\n")
if name == "sudo":
    print(os.environ.get("SOCKETS", 'tcp LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("caido",pid=4218,fd=3))\\nudp UNCONN 0 0 127.0.0.53:53 0.0.0.0:* users:(("systemd-resolve",pid=611,fd=4))\\ntcp LISTEN 0 128 [::1]:631 [::]:*\\ntcp LISTEN 0 128 *:22 *:* users:(("sshd",pid=842,fd=3),("systemd",pid=1,fd=4))'))
sys.exit(int(os.environ.get(name.upper() + "_STATUS", "0")))
'''
    for name in ("curl", "mkdir", "python", "sudo", "pipx"):
        command = tools / name
        command.write_text(stub)
        command.chmod(0o755)
    env = {**os.environ, "PATH": f"{tools}:{os.environ['PATH']}", "CALLS": str(log),
           "MONARCH_PATH": str(root)}

    def run(command, extra=None, expected=0, tty=False):
        log.write_text("")
        run_env = {**env, **(extra or {})}
        if tty:
            master, slave = pty.openpty()
            try:
                result = subprocess.run(command, stdout=slave, stderr=subprocess.PIPE, env=run_env)
                os.close(slave)
                slave = None
                output = b""
                while True:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                result.stdout = output.replace(b"\r\n", b"\n")
            finally:
                os.close(master)
                if slave is not None:
                    os.close(slave)
        else:
            result = subprocess.run(command, capture_output=True, env=run_env)
        assert result.returncode == expected, (command, result.returncode, result.stderr)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        return result, calls

    urls = fixture / "urls with spaces.txt"
    urls.write_text("https://example.invalid/a\\b?x=1&y=2\nhttps://example.invalid/last")
    for shell in ("bash", "zsh"):
        if not shutil.which(shell):
            print(f"SKIP: {shell} is unavailable")
            continue
        flags = "-fc" if shell == "zsh" else "-c"
        load = ('source "$ROOT/default/shells/aliases"; '
                'source "$ROOT/default/shells/functions"; '
                'source "$ROOT/default/shells/aliases"; '
                'source "$ROOT/default/shells/functions"; ')

        def helper(program, **kwargs):
            return run([shell, flags, load + program], **kwargs)

        result, calls = helper('shopt -s expand_aliases 2>/dev/null || true; eval "sop"')
        lines = result.stdout.decode().splitlines()
        assert lines[0].split() == ["PROTO", "PORT", "LOCAL", "ADDRESS", "PROCESS", "PID"]
        assert [line.split()[1] for line in lines[1:]] == ["22", "53", "631", "8080"], lines
        assert "UDP" in lines[2] and "systemd-resolve" in lines[2]
        assert "[::1]" in lines[3] and "—" in lines[3]
        assert "sshd, systemd" in lines[1] and "842, 1" in lines[1]
        assert b"\x1b" not in result.stdout
        assert calls == [["sudo", "ss", "-H", "-lntup"]], calls
        color_env = {**env, "TERM": "xterm-256color"}
        color_env.pop("NO_COLOR", None)
        saved_env = env
        env = color_env
        try:
            result, _ = helper("show-open-ports", tty=True)
            assert b"\x1b[36mTCP" in result.stdout and b"\x1b[33mUDP" in result.stdout
            for options in ({"NO_COLOR": ""}, {"TERM": "dumb"}):
                result, _ = helper("show-open-ports", tty=True, extra=options)
                assert b"\x1b" not in result.stdout
        finally:
            env = saved_env
        result, _ = helper("show-open-ports", extra={"SOCKETS": ""})
        assert b"No listening TCP or UDP sockets." in result.stdout
        result, _ = helper("show-open-ports", extra={"SUDO_STATUS": "17"}, expected=17)
        assert result.stdout == b""
        result, calls = helper('probe-urls "$URLS"', extra={"URLS": str(urls)})
        assert [call[2] for call in calls] == urls.read_text().splitlines(), calls
        assert all(call[1] == "-sk" and call[3:5] == ["-o", "/dev/null"] for call in calls)
        for args in ("", "a b"):
            result, calls = helper("probe-urls " + args, expected=2)
            assert b"Usage:" in result.stderr and not calls
        result, calls = helper('probe-urls "$URLS"', extra={"URLS": str(fixture / "missing")}, expected=1)
        assert not calls
        result, calls = helper("pysrv")
        assert calls == [["mkdir", "-pv", "/tmp/empty"],
                         ["python", "-m", "http.server", "-d", "/tmp/empty"]], calls
        result, calls = helper("pysrv", extra={"MKDIR_STATUS": "17"}, expected=17)
        assert calls == [["mkdir", "-pv", "/tmp/empty"]], calls

    installer = root / "bin/monarch-install-exegol"
    result, calls = run([str(installer)])
    assert calls == [["pipx", "install", "--python", "3.14", "--fetch-missing-python", "exegol"]], calls
    run([str(installer)], extra={"PIPX_STATUS": "19"}, expected=19)
    for menu in ("exegol", "pentestenv"):
        source = (root / f"bin/monarch-menu-{menu}").read_text()
        assert "&& monarch-install-exegol" in source
        assert "pipx install exegol" not in source

print("SkillArch fixes: Bash/Zsh UDP, URL boundaries, server guard and Exegol runtime passed")
PY
