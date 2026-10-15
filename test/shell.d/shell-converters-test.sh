#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

python3 <<'PY'
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import quote_from_bytes

root = Path(os.environ["ROOT"])
env = {**os.environ, "MONARCH_PATH": str(root)}
load = ('source "$ROOT/default/shells/aliases"; '
        'alias b64url="printf stale"; '
        'source "$ROOT/default/shells/functions"; '
        'source "$ROOT/default/shells/aliases"; '
        'source "$ROOT/default/shells/functions"; ')
names = ("b64url", "b64urld", "urlencode", "urldecode", "toHex", "fromHex",
         "utf16le", "utf16to8", "nthash")
payload = bytes(range(256)) + b"\x00\xff\n\n"

for shell in ("bash", "zsh"):
    if not shutil.which(shell):
        print(f"SKIP: {shell} is unavailable")
        continue
    flags = "-fc" if shell == "zsh" else "-c"

    for name, data, expected in (
        ("b64e", payload, base64.b64encode(payload)),
        ("b64d", base64.b64encode(payload), payload),
    ):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input with spaces"
            source.write_bytes(data)
            program = load + 'shopt -s expand_aliases 2>/dev/null || true; '
            for invocation in (name, name + ' -- "$INPUT_FILE"'):
                result = subprocess.run(
                    [shell, flags, program + "eval '" + invocation + "'"],
                    input=data, capture_output=True, env={**env, "INPUT_FILE": str(source)},
                )
                assert result.returncode == 0 and result.stdout == expected, (name, result.stderr)

    def convert(name, data=b"", args=(), success=True, extra=None):
        result = subprocess.run(
            [shell, flags, load + '"$@"', "converter-test", name, *args],
            input=data, capture_output=True, env={**env, **(extra or {})},
        )
        if success:
            assert result.returncode == 0, (shell, name, result.stderr)
            assert result.stderr == b"", result.stderr
        else:
            assert result.returncode != 0, (shell, name, args)
            assert result.stdout == b"", (name, result.stdout)
            assert result.stderr, name
        return result

    for encode, decode, expected in (
        ("b64url", "b64urld", base64.urlsafe_b64encode(payload).rstrip(b"=")),
        ("urlencode", "urldecode", quote_from_bytes(payload, safe="").encode()),
        ("toHex", "fromHex", payload.hex().encode()),
    ):
        encoded = convert(encode, payload).stdout
        assert encoded == expected, encode
        assert convert(decode, encoded).stdout == payload, decode
        assert convert(decode, args=(encoded.decode(),)).stdout == payload

    for raw in (b"", b"f", b"fo", b"foo", b"\xfb\xff", b"text\n\n"):
        encoded = base64.urlsafe_b64encode(raw)
        assert convert("b64urld", encoded).stdout == raw
        assert convert("b64urld", encoded.rstrip(b"=")).stdout == raw
        assert convert("b64urld", b" \t" + encoded + b"\r\n").stdout == raw
    for invalid in (b"A", b"Zg=", b"Zg===", b"=Zg", b"Zm9v=", b"ab+c", b"ab/c", b"a!", b"\xff"):
        convert("b64urld", invalid, success=False)
    for invalid in (b"a", b"00zz", b"0x41", b"\\x41", b"\xff"):
        convert("fromHex", invalid, success=False)
    assert convert("fromHex", b"00 ff\n41\t").stdout == b"\x00\xffA"
    for invalid in (b"%", b"%2", b"%GG", b"ok%41%no"):
        convert("urldecode", invalid, success=False)
    assert convert("urldecode", b"a+b%00%ff\n\n").stdout == b"a+b\x00\xff\n\n"

    text = "hello café 🌍\x00\n\n"
    encoded = convert("utf16le", text.encode()).stdout
    assert encoded == text.encode("utf-16le")
    assert convert("utf16to8", encoded).stdout == text.encode()
    assert convert("utf16to8", b"\xff\xfeA\x00").stdout == "\ufeffA".encode()
    convert("utf16le", b"\xff", success=False)
    for invalid in (b"\x00", b"\x00\xd8"):
        convert("utf16to8", invalid, success=False)

    for password, expected in (
        (b"", b"31d6cfe0d16ae931b73c59d7e0c089c0"),
        (b"password", b"8846f7eaee8fb117ad06bdd830b7586c"),
        (b"Password1", b"64f12cddaa88057e06a81b54e73b949b"),
    ):
        assert convert("nthash", password).stdout == expected
        assert convert("nthash", args=(password.decode(),)).stdout == expected
    assert convert("nthash", b"Password1\n").stdout != b"64f12cddaa88057e06a81b54e73b949b"
    convert("nthash", b"\xff", success=False)

    for name in names:
        assert convert(name, data=b"not consumed", args=("",)).stdout == (
            b"31d6cfe0d16ae931b73c59d7e0c089c0" if name == "nthash" else b""
        )
        failed = convert(name, args=("a", "b"), success=False)
        assert failed.returncode == 2
    assert convert("urlencode", args=("-n",)).stdout == b"-n"
    assert convert("urlencode", args=("$(touch /not-executed); ' \\\n",)).stdout.startswith(b"%24%28")
    assert convert("b64url", args=("café\n\n",)).stdout == base64.urlsafe_b64encode("café\n\n".encode()).rstrip(b"=")

    with tempfile.TemporaryDirectory() as directory:
        openssl = Path(directory) / "openssl"
        openssl.write_text("#!/bin/bash\nprintf partial\nexit 19\n")
        openssl.chmod(0o755)
        result = convert("nthash", b"Password1", success=False,
                         extra={"PATH": f"{directory}:{os.environ['PATH']}"})
        assert b"legacy MD4 provider" in result.stderr

    print(f"PASS: {shell} converter roundtrips, binary boundaries, invalid input and NT hash vectors")
PY
