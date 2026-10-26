#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$root" <<'PY'
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='lazyvpn-integration-') as temporary:
    tmp = Path(temporary)
    root, home, bins = tmp / 'runtime', tmp / 'home', tmp / 'bin'
    bins.mkdir()
    home.mkdir()
    files = ['bin/monarch-install-lazyvpn', 'bin/monarch-remove-lazyvpn',
             'install/helpers/lazyvpn.sh', 'install/reconcile/lazyvpn.sh',
             'default/monarch/lazyvpn/niri/monarch-lazyvpn.kdl',
             'default/monarch/lazyvpn/noctalia/lazyvpn.toml']
    for relative in files:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        text = (repo / relative).read_text()
        # Redirect trusted package paths only in the disposable test runtime.
        text = text.replace('/usr/bin/monarch-lazyvpn', str(bins / 'monarch-lazyvpn'))
        text = text.replace('/usr/share/monarch-lazyvpn', str(tmp / 'assets'))
        text = text.replace('/usr/share/applications/monarch-lazyvpn.desktop', str(tmp / 'app.desktop'))
        target.write_text(text)
        target.chmod(0o755 if relative.startswith('bin/') else 0o644)

    def stub(name, text):
        target = bins / name
        target.write_text('#!/bin/bash\n' + text)
        target.chmod(0o755)

    stub('monarch-lazyvpn', '''
if [[ $* == "--preview --help" ]]; then exit "${OLD_BACKEND:-0}"; fi
echo gui >>"$HOME/launch.log"
exit "${GUI_FAILURE:-0}"
''')
    stub('pacman', '''
[[ $* == "-Q monarch-lazyvpn" ]] || exit 2
[[ ${MISSING:-0} == 0 ]] || exit 1
echo "monarch-lazyvpn ${VERSION:-0.2.0-1}"
''')
    stub('monarch-pkg-add', 'exit "${PKG_FAILURE:-0}"\n')
    stub('monarch-pkg-drop', 'exit "${PKG_FAILURE:-0}"\n')
    stub('pgrep', 'exit 1\n')
    stub('monarch-cmd-present', 'exit 1\n')
    stub('terminal', 'echo terminal >>"$HOME/launch.log"\n')
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'),
               XDG_DATA_HOME=str(home / 'data'), PATH=f'{bins}:{root}/bin:' + os.environ['PATH'])
    config, data = Path(env['XDG_CONFIG_HOME']), Path(env['XDG_DATA_HOME'])
    target = config / 'niri/monarch-lazyvpn.kdl'
    target.parent.mkdir(parents=True)
    target.write_text('old shortcut\n')
    legacy = data / 'applications/LazyVPN.desktop'
    legacy.parent.mkdir(parents=True)
    legacy.write_text('Exec=monarch-launch-floating-terminal-with-presentation monarch-lazyvpn\n')
    (config / 'monarch-lazyvpn').mkdir()
    profile = config / 'monarch-lazyvpn/profile.conf'
    profile.write_text('preserve me')

    def run(script, success=True, **overrides):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', script],
                                env=dict(env, **overrides), capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result

    reconcile = f'source "{root}/install/reconcile/lazyvpn.sh"; monarch_reconcile_lazyvpn "{root}"'
    for overrides in ({'MISSING': '1'}, {'VERSION': '0.1.5-1'}, {'OLD_BACKEND': '1'}):
        run(reconcile, **overrides)
        assert target.read_text() == 'old shortcut\n' and legacy.exists()
    run(reconcile, success=False)
    assert target.read_text() == 'old shortcut\n' and legacy.exists()
    print('ok - absent/old/incomplete packages preserve the previous integration')

    (tmp / 'assets/noctalia').mkdir(parents=True)
    (tmp / 'assets/noctalia/lazyvpn.json').write_text('{}')
    (tmp / 'app.desktop').write_text('[Desktop Entry]\nExec=monarch-lazyvpn\n')
    run(reconcile)
    run(reconcile)
    assert 'spawn "monarch-lazyvpn";' in target.read_text()
    assert 'fixed 880' in target.read_text() and 'fixed 540' in target.read_text()
    assert target.with_suffix('.kdl.pre-gpui').read_text() == 'old shortcut\n'
    user = config / 'niri/user.kdl'
    assert user.read_text().count('include "./monarch-lazyvpn.kdl"') == 1
    assert not legacy.exists() and legacy.with_suffix('.desktop.pre-gpui').exists()
    assert (config / 'noctalia/lazyvpn.toml').is_file()
    assert profile.read_text() == 'preserve me'
    print('ok - reconciliation is idempotent, backs up integration and preserves profiles')

    for version in ('0.2.0', '0.2.0-12', '0.10.0-1', '1:0.2.0-1'):
        run(reconcile, VERSION=version)
    before = target.read_text()
    installer = f'"{root}/bin/monarch-install-lazyvpn"'
    run(installer)
    run(installer, success=False, PKG_FAILURE='9')
    run(installer, success=False, OLD_BACKEND='1')
    assert target.read_text() == before
    print('ok - fresh installation and package/backend failure paths')

    source = (repo / 'default/noctalia/plugins/monarch-indicators/lazyvpn.luau').read_text()
    callback = re.search(r'function onClick\(\).*?\nend', source, re.S).group()
    lua = shutil.which('lua5.4') or shutil.which('lua')
    assert lua, 'Lua is required for the indicator callback test'
    harness = tmp / 'indicator.lua'
    harness.write_text('''
local indicator = {
  pkgBin = function(_) return os.getenv('VPN_BINARY') end,
  bin = function(_) return os.getenv('VPN_TERMINAL') end
}
noctalia = { runAsync = function(command) print(command) end }
''' + callback + '\nonClick()\n')
    command = subprocess.check_output([lua, str(harness)], text=True,
        env=dict(env, VPN_BINARY=str(bins / 'monarch-lazyvpn'), VPN_TERMINAL=str(bins / 'terminal'))).strip()
    run(command)
    run(command, OLD_BACKEND='1')
    run(command, success=False, GUI_FAILURE='7')
    assert (home / 'launch.log').read_text().splitlines() == ['gui', 'terminal', 'gui']
    print('ok - actual indicator selects GUI or legacy terminal without masking GUI failures')

    remove = f'"{root}/bin/monarch-remove-lazyvpn"'
    run(remove, success=False, PKG_FAILURE='9')
    assert target.exists() and (config / 'noctalia/lazyvpn.toml').exists()
    run(remove)
    assert not target.exists() and not (config / 'noctalia/lazyvpn.toml').exists()
    assert 'monarch-lazyvpn.kdl' not in user.read_text()
    assert profile.read_text() == 'preserve me'
    print('ok - removal keeps integration on pacman failure and always preserves profile data')
PY
