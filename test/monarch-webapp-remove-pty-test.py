#!/usr/bin/env python3
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import tempfile
import termios
import time

root = Path(__file__).resolve().parent.parent


def run(home, keys):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(HOME=str(home), TERM="xterm", PATH=f"{root / 'bin'}:/usr/bin:/bin")
        os.execv(root / "bin/monarch-webapp-remove", ["monarch-webapp-remove"])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    output = b""
    try:
        for key, pause in [(b"", 0.7), *keys]:
            if key:
                os.write(fd, key)
            deadline = time.monotonic() + pause
            while time.monotonic() < deadline:
                if not select.select([fd], [], [], 0.05)[0]:
                    continue
                try:
                    output += os.read(fd, 65536)
                except OSError:
                    break
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                return os.waitstatus_to_exitcode(status), output
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    output += os.read(fd, 65536)
                except OSError:
                    pass
        raise AssertionError(f"selector did not exit: {output!r}")
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass
        os.close(fd)


with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    apps = home / ".local/share/applications"
    apps.mkdir(parents=True)
    for name in ("Alpha", "Beta"):
        (apps / f"{name}.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName={name}\nExec=monarch-launch-webapp https://example.com\n"
        )
    status, output = run(home, [(b"\r", 0.5), (b" ", 0.2), (b"\x1b[B", 0.2), (b" ", 0.2), (b"\r", 0.2)])
    assert status == 0, (status, output)
    assert b"Select at least one app" in output, output
    assert not list(apps.glob("*.desktop")), output
    (apps / "Keep.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Keep\nExec=monarch-launch-webapp https://example.com\n"
    )
    status, output = run(home, [(b"\x1b", 0.5)])
    assert status == 0, (status, output)
    assert (apps / "Keep.desktop").exists()
print("PASS: webapp removal keyboard interaction")
