#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

python3 <<'PY'
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(os.environ["ROOT"])
environment = {**os.environ, "MONARCH_PATH": str(root)}


def run(command, data=b"", env=None, success=True):
    result = subprocess.run(command, input=data, capture_output=True, env=env or environment)
    if success:
        assert result.returncode == 0, (command, result.stderr)
    else:
        assert result.returncode != 0, command
        assert result.stdout == b"", result.stdout
    return result


with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory)
    tools = fixture / "tools"
    tools.mkdir()
    runtime = fixture / "runtime"
    (runtime / "bin").mkdir(parents=True)
    shutil.copy(root / "bin/monarch", runtime / "bin/monarch")
    fixture_command = runtime / "bin/monarch-show-fixture"
    fixture_command.write_text(
        '#!/bin/bash\n# monarch:summary=Fixture command description\n'
        '# monarch:args=<path>\n# monarch:examples=monarch show fixture "a b"\n'
        '# monarch:requires-sudo=true\nprintf executed > "$EXECUTION_MARKER"\n'
    )
    fixture_command.chmod(0o755)
    selector = tools / "fzf"
    selector.write_text('#!/bin/bash\ncat > "$PICKER_ROWS"\n'
                        '[[ ${PICKER_CANCEL:-0} == 0 ]] || exit 130\n'
                        'if [[ -n ${PICKER_CHOICE:-} ]]; then\n'
                        '  awk -F "\\t" -v choice="$PICKER_CHOICE" \'$1 == choice {print; exit}\' "$PICKER_ROWS"\n'
                        '  exit\nfi\n'
                        'sed -n "1p" "$PICKER_ROWS"\n')
    selector.chmod(0o755)
    env = {**environment, "MONARCH_PATH": str(runtime), "PATH": f"{tools}:{os.environ['PATH']}",
           "PICKER_ROWS": str(fixture / "rows"), "EXECUTION_MARKER": str(fixture / "executed")}
    picker = str(root / "bin/monarch-cmd-picker")
    assert run([picker], env=env).stdout == b"monarch show fixture\n"
    rows = (fixture / "rows").read_text()
    assert "Fixture command description" in rows and "Requires sudo" in rows
    assert "<path>" in rows and '"a b"' in rows
    assert not (fixture / "executed").exists()
    fixture_command.write_text(fixture_command.read_text().replace("Fixture command description", "Changed metadata"))
    assert b"Changed metadata" in run([picker, "--list"], env=env).stdout
    result = run([picker], env={**env, "PICKER_CANCEL": "1"}, success=False)
    assert result.returncode == 130

    shutil.copy(root / "bin/monarch-cmd-picker", runtime / "bin/monarch-cmd-picker")
    for shell in ("bash", "zsh"):
        if not shutil.which(shell):
            continue
        flags = "-fc" if shell == "zsh" else "-c"
        load_picker = 'source "$ROOT/default/shells/fns/command-picker"; '
        definitions = (
            'public_helper() { touch "$EXECUTION_MARKER"; }; '
            '_private_helper() { touch "$EXECUTION_MARKER"; }; '
            'shared_helper() { touch "$EXECUTION_MARKER"; }; '
            'alias shared_helper="printf alias"; '
            'alias public_alias=\'printf "a b"; touch "$EXECUTION_MARKER"\'; '
            'alias multiline_alias=$\'printf first\\nprintf second\\t\\033\'; '
        )
        entries = run([shell, flags, load_picker + definitions + '_monarch_command_picker_entries'], env=env)
        catalog = {entry["route"]: entry for entry in json.loads(entries.stdout)}
        assert "public_helper" in catalog and "public_alias" in catalog, catalog
        assert "_private_helper" not in catalog and "_monarch_command_picker" not in catalog
        assert catalog["shared_helper"]["summary"] == "Shell alias", catalog
        assert catalog["public_alias"]["definition"] == 'printf "a b"; touch "$EXECUTION_MARKER"'
        listing = run([picker, "--shell-commands", "--list"], data=entries.stdout, env=env).stdout
        assert b"public_helper\tUser-defined shell helper" in listing
        multiline_row = next(row for row in listing.splitlines() if row.startswith(b"multiline_alias\t"))
        assert len(multiline_row.split(b"\t")) == 8 and b"\x1b" not in multiline_row
        columns = multiline_row.split(b"\t")
        assert columns[1] == b"User-defined shell helper"
        assert columns[5] == b"Alias" and columns[7].strip() == b"Alias"
        assert b"printf first" in columns[3] and b"printf first" not in columns[1]

        for choice in ("public_alias", "public_helper"):
            selected_env = {**env, "PICKER_CHOICE": choice}
            selected = run([picker, "--shell-commands"], data=entries.stdout, env=selected_env)
            assert selected.stdout == (choice + "\n").encode()
            if shell == "bash":
                buffer = 'READLINE_LINE="before after"; READLINE_POINT=7; '
                output = 'printf "%s|%s" "$READLINE_LINE" "$READLINE_POINT"'
                expected = f"before {choice} after|{8 + len(choice)}".encode()
                cancelled = b"before after|7"
            else:
                buffer = 'zle() { :; }; LBUFFER="before "; RBUFFER="after"; '
                output = 'printf "%s%s" "$LBUFFER" "$RBUFFER"'
                expected = f"before {choice} after".encode()
                cancelled = b"before after"
            widget = load_picker + definitions + buffer + '_monarch_command_picker; ' + output
            assert run([shell, flags, widget], env=selected_env).stdout == expected
            assert run([shell, flags, widget], env={**selected_env, "PICKER_CANCEL": "1"}).stdout == cancelled
            assert not (fixture / "executed").exists()

    defaults = run([picker, "--list"], env={**env, "MONARCH_PATH": str(root)}).stdout
    clean_env = {key: value for key, value in environment.items() if key != "MONARCH_PATH"}
    assert run([picker, "--list"], env=clean_env).stdout == defaults
    assert b"cpy\tCopy input to the Wayland clipboard" in defaults
    assert b"dex\tRun a command in a selected Docker container" in defaults
    assert b"_monarch_command_picker\t" not in defaults
    description_lines = (root / "default/shells/command-descriptions.tsv").read_text().splitlines()
    descriptions = dict(line.split("\t") for line in description_lines)
    assert len(descriptions) == len(description_lines)
    default_rows = [row.split(b"\t") for row in defaults.splitlines()]
    helpers = [row for row in default_rows if row[5] in (b"Alias", b"Function")]
    assert all(row[0].decode() in descriptions for row in helpers)
    assert len({len(row[6]) for row in default_rows}) == 1
    assert len({len(row[7]) for row in default_rows}) == 1
    real_fzf = shutil.which("fzf")
    if real_fzf:
        filtered = run([
            real_fzf, "--filter=Copy input", "--delimiter=\t",
            "--with-nth=7,8,2", "--nth=1,2,3",
        ], data=defaults, env={**environment, "FZF_DEFAULT_OPTS": "", "FZF_DEFAULT_OPTS_FILE": ""})
        assert filtered.stdout.split(b"\t", 1)[0] == b"cpy", filtered.stdout

    (runtime / "bin/monarch-cmd-picker").write_text(
        '#!/bin/bash\n[[ ${PICKER_CANCEL:-0} == 0 ]] || exit 130\n'
        'printf "%s\\n" "monarch show fixture"\n'
    )
    (runtime / "bin/monarch-cmd-picker").chmod(0o755)
    docker_log = fixture / "docker.log"
    docker_mock = tools / "docker"
    docker_mock.write_text('''#!/usr/bin/python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["DOCKER_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:1] in (["ps"], ["images"]) or args[:2] in (["volume", "ls"], ["network", "ls"]):
    if int(os.environ.get("DOCKER_LIST_STATUS", "0")):
        sys.exit(int(os.environ["DOCKER_LIST_STATUS"]))
    if "--format" in args:
        print("abc123\\tapp with spaces\\timage:tag")
    else:
        print(os.environ.get("DOCKER_IDS", "abc123\\ndef456"))
elif args[:1] == ["inspect"]:
    if "-f" in args:
        print(os.environ.get("DOCKER_PID", "42"))
    else:
        print('[{"ip": "10.1.2.3"}]')
else:
    sys.exit(int(os.environ.get("DOCKER_ACTION_STATUS", "0")))
''')
    docker_mock.chmod(0o755)
    sudo_mock = tools / "sudo"
    sudo_mock.write_text('''#!/usr/bin/python3
import json, os, sys
with open(os.environ["DOCKER_LOG"], "a") as log:
    log.write(json.dumps(["sudo", *sys.argv[1:]]) + "\\n")
''')
    sudo_mock.chmod(0o755)
    result_file = fixture / "results with spaces.json"
    result_file.write_text('{"results":[{"status":200,"length":12,"lines":2,"words":3,"url":"https://example.invalid/a"}]}')
    invalid_file = fixture / "invalid.json"
    invalid_file.write_text('invalid json')
    for shell in ("bash", "zsh"):
        if not shutil.which(shell):
            print(f"SKIP: {shell} is unavailable")
            continue
        shell_flags = "-fc" if shell == "zsh" else "-c"
        source = 'source "$ROOT/default/shells/fns/command-picker"; '
        if shell == "bash":
            program = 'bind() { :; }; ' + source + (
                'READLINE_LINE="before after"; READLINE_POINT=7; '
                '_monarch_command_picker; printf "%s|%s" "$READLINE_LINE" "$READLINE_POINT"'
            )
            expected = b"before monarch show fixture after|28"
        else:
            program = 'zle() { :; }; bindkey() { :; }; ' + source + (
                'LBUFFER="before "; RBUFFER="after"; '
                '_monarch_command_picker; printf "%s%s" "$LBUFFER" "$RBUFFER"'
            )
            expected = b"before monarch show fixture after"
        assert run([shell, shell_flags, program], env=env).stdout == expected
        cancelled = run([shell, shell_flags, program], env={**env, "PICKER_CANCEL": "1"}).stdout
        assert cancelled == (b"before after|7" if shell == "bash" else b"before after")

        helper_env = {**env, "MONARCH_PATH": str(root)}
        utilities = ('source "$ROOT/default/shells/aliases"; source "$ROOT/default/shells/functions"; '
                     'curl() { printf "%s" "$*"; }; f() { printf kept; }; '
                     'cheat jq; printf "|"; f')
        assert run([shell, shell_flags, utilities], env=helper_env).stdout == b"-s cheat.sh/jq|kept"
        clipboard = ('source "$ROOT/default/shells/aliases"; '
                     'alias cpy; alias paste')
        aliases = run([shell, shell_flags, clipboard], env=helper_env).stdout
        assert b"wl-copy" in aliases and b"wl-paste --no-newline" in aliases

        load = ('source "$ROOT/default/shells/aliases"; source "$ROOT/default/shells/functions"; '
                'source "$ROOT/default/shells/aliases"; source "$ROOT/default/shells/functions"; ')
        docker_env = {**helper_env, "DOCKER_LOG": str(docker_log)}
        for name, expected_call in (
            ("dex", ["exec", "-it", "abc123", "printf", "%s", "a b"]),
            ("dexr", ["exec", "-it", "-u", "root", "abc123", "printf", "%s", "a b"]),
            ("dockns", ["sudo", "nsenter", "-a", "-t", "42", "printf", "%s", "a b"]),
        ):
            docker_log.write_text("")
            run([shell, shell_flags, load + name + " printf '%s' 'a b'"], env=docker_env)
            calls = [json.loads(line) for line in docker_log.read_text().splitlines()]
            assert calls[-1] == expected_call, calls
            docker_log.write_text("")
            cancelled = run([shell, shell_flags, load + name], env={**docker_env, "PICKER_CANCEL": "1"}, success=False)
            assert cancelled.returncode == 130
            calls = [json.loads(line) for line in docker_log.read_text().splitlines()]
            assert len(calls) == 1 and calls[0][0] == "ps", calls

        for name, expected_call in (
            ("dnorestart", ["update", "--restart=no", "abc123", "def456"]),
            ("dstopall", ["stop", "abc123", "def456"]),
            ("dwipe-image", ["rmi", "-f", "abc123", "def456"]),
            ("dwipe-network", ["network", "rm", "abc123", "def456"]),
            ("dwipe-process", ["rm", "abc123", "def456"]),
            ("dwipe-volume", ["volume", "rm", "abc123", "def456"]),
        ):
            docker_log.write_text("")
            run([shell, shell_flags, load + name], env=docker_env)
            calls = [json.loads(line) for line in docker_log.read_text().splitlines()]
            assert calls[-1] == expected_call, calls
            docker_log.write_text("")
            run([shell, shell_flags, load + name], env={**docker_env, "DOCKER_IDS": ""})
            assert len(docker_log.read_text().splitlines()) == 1
            failed = run([shell, shell_flags, load + name], env={**docker_env, "DOCKER_LIST_STATUS": "17"}, success=False)
            assert failed.returncode == 17

        failed = run([shell, shell_flags, load + "dockns"], env={**docker_env, "DOCKER_PID": "0"}, success=False)
        assert b"no running process" in failed.stderr
        docker_log.write_text("")
        run([shell, shell_flags, load + "dstopall --time=3"], env=docker_env)
        calls = [json.loads(line) for line in docker_log.read_text().splitlines()]
        assert calls[-1] == ["stop", "--time=3", "abc123", "def456"]
        assert run([shell, shell_flags, load + "din -r '.[0].ip'"], env=docker_env).stdout == b"10.1.2.3\n"
        assert run([shell, shell_flags, load + "dinp -n"], env=docker_env).stdout == b'3:    "ip": "10.1.2.3"\n'
        docker_log.write_text("")
        failed = run([shell, shell_flags, load + "dkillall"], env={**docker_env, "DOCKER_ACTION_STATUS": "19"}, success=False)
        assert failed.returncode == 19
        assert not any(json.loads(line)[0] == "stop" for line in docker_log.read_text().splitlines())

        document = load + 'xdg-open() { printf "%s|%s" "$#" "$1"; }; f() { printf kept; }; getinfo-bookhacktricks "a b"; printf "|"; f'
        assert run([shell, shell_flags, document], env=helper_env).stdout == b"1|https://book.hacktricks.wiki/en/index.html?search=a b|kept"
        local_env = {**helper_env, "RESULT_FILE": str(result_file)}
        assert run([shell, shell_flags, load + 'cfu "$RESULT_FILE"'], env=local_env).stdout == b"200\t12\t2\t3\thttps://example.invalid/a\n"
        for formatter in ("cfu", "cfu-clean", "cfu-clean-url"):
            run([shell, shell_flags, load + formatter + ' "$RESULT_FILE"'], env={**local_env, "RESULT_FILE": str(invalid_file)}, success=False)

print("Shell helpers: live metadata, Bash/Zsh insertion, Docker cancellation and argument boundaries passed")
PY
