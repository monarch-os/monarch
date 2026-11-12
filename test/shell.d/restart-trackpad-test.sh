#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = (Path(sys.argv[1]) / 'bin/monarch-restart-trackpad').read_text()
with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    driver = tmp / 'driver'
    mocks = tmp / 'bin'
    driver.mkdir()
    mocks.mkdir()
    log = tmp / 'calls'
    for name, kind in [('i2c-touch', 'touchpad'), ('i2c-keyboard', 'keyboard'), ('i2c-screen', 'screen')]:
        input_path = driver / name / 'hid' / 'input' / 'input0'
        input_path.mkdir(parents=True)
        (input_path / 'kind').write_text(kind)
    (mocks / 'udevadm').write_text('''#!/bin/bash
kind=$(cat "$3/kind")
[[ $kind != "${FAIL_UDEV:-}" ]] || exit 1
[[ $kind != touchpad ]] || echo ID_INPUT_TOUCHPAD=1
''')
    (mocks / 'sudo').write_text('''#!/bin/bash
read -r device
echo "$device ${2##*/}" >> "$LOG"
[[ ${2##*/} != "${FAIL_WRITE:-}" ]] || exit 1
''')
    (mocks / 'sleep').write_text('#!/bin/bash\nexit 0\n')
    for mock in mocks.iterdir():
        mock.chmod(0o755)
    script = tmp / 'script'
    script.write_text(source.replace('/sys/bus/i2c/drivers/i2c_hid_acpi', str(driver)))
    env = dict(os.environ, PATH=f'{mocks}:' + os.environ['PATH'], LOG=str(log))

    def run(**extra):
        log.write_text('')
        result = subprocess.run(['bash', str(script)], env=env | extra, text=True, capture_output=True, timeout=5)
        return result, log.read_text().splitlines()

    result, calls = run()
    assert result.returncode == 0, result.stderr
    assert calls == ['i2c-touch unbind', 'i2c-touch bind'], calls
    result, calls = run(FAIL_UDEV='touchpad')
    assert result.returncode != 0 and not calls, (result.stderr, calls)
    result, calls = run(FAIL_WRITE='unbind')
    assert result.returncode != 0 and calls == ['i2c-touch unbind'] and 'Done' not in result.stdout
    result, calls = run(FAIL_WRITE='bind')
    assert result.returncode != 0 and calls == ['i2c-touch unbind', 'i2c-touch bind'] and 'Done' not in result.stdout
    (driver / 'i2c-touch' / 'hid' / 'input' / 'input0' / 'kind').write_text('keyboard')
    result, calls = run()
    assert result.returncode != 0 and not calls
    print('PASS: targeted trackpad reset and failure handling')
PY
