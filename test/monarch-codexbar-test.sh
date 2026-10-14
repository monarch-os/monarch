#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class TransitionTests(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.home = Path(self.temporary.name)
    self.config = self.home / 'config'
    self.state = self.home / 'state'
    self.plugin = self.home / '.local/share/noctalia/plugins/monarch-agents'
    self.backup = self.state / 'monarch/backups/noctalia/monarch-agents'
    binary = self.put(self.home / 'bin/codexbar', '#!/bin/bash\nexit "${TEST_CLI_STATUS:-0}"\n')
    binary.chmod(0o755)
    self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                    XDG_STATE_HOME=str(self.state), PATH=str(binary.parent) + ':/usr/bin')
    for name in ('CODEXBAR_CONFIG', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME'):
      self.env.pop(name, None)

  def put(self, path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path

  def seed_legacy(self):
    self.put(self.plugin / 'plugin.toml', 'id = "monarch/agents"')
    self.put(self.plugin / 'service.luau', 'legacy collector')

  def run_transition(self, success=True):
    result = subprocess.run(['python3', os.environ['ROOT'] + '/install/reconcile/agent-usage.py'],
                            env=self.env, capture_output=True, text=True)
    self.assertEqual(result.returncode == 0, success, result.stderr)

  def test_transition_preserves_credentials_history_and_noctalia_configuration(self):
    self.seed_legacy()
    (self.home / '.claude').mkdir()
    (self.home / '.codex').mkdir()
    disabled = self.put(self.state / 'monarch/agents/disabled/claude', '')
    history = self.put(self.state / 'monarch/agents/usage/codex.json', '{"ready":true}')
    key = self.put(self.config / 'monarch/agents/synthetic.json', '{"apiKey":"test-secret"}')
    layout_text = '[bar.default]\nend = ["tray", "monarch/agents:usage", "volume"]\n'
    layout = self.put(self.config / 'noctalia/config.toml', layout_text)
    self.run_transition()
    target = self.config / 'codexbar/config.json'
    providers = {p['id']: p for p in json.loads(target.read_text())['providers']}
    self.assertFalse(providers['claude']['enabled'])
    self.assertTrue(providers['codex']['enabled'])
    self.assertEqual(providers['codex']['source'], 'cli')
    self.assertEqual(providers['synthetic']['apiKey'], 'test-secret')
    self.assertEqual(target.stat().st_mode & 0o777, 0o600)
    self.assertEqual(layout.read_text(), layout_text)
    self.assertEqual((self.backup / 'service.luau').read_text(), 'legacy collector')
    self.assertFalse(self.plugin.exists())
    self.assertTrue(history.exists() and disabled.exists() and key.exists())
    inode = target.stat().st_ino
    self.run_transition()
    self.assertEqual(target.stat().st_ino, inode)

  def test_existing_codexbar_configuration_is_not_overwritten(self):
    self.seed_legacy()
    path = self.put(self.config / 'codexbar/config.json', '{"version":1,"providers":[]}')
    self.run_transition()
    self.assertEqual(path.read_text(), '{"version":1,"providers":[]}')

  def test_legacy_codexbar_configuration_is_not_shadowed(self):
    self.seed_legacy()
    self.put(self.home / '.codexbar/config.json', '{"version":1,"providers":[]}')
    self.run_transition()
    self.assertFalse((self.config / 'codexbar/config.json').exists())

  def test_fresh_install_does_not_create_provider_configuration(self):
    self.run_transition()
    self.assertFalse((self.config / 'codexbar/config.json').exists())

  def test_current_plugin_does_not_run_backend_validation(self):
    self.put(self.plugin / 'plugin.toml', 'id = "monarch/agents"')
    self.env['TEST_CLI_STATUS'] = '1'
    self.run_transition()
    self.assertTrue((self.plugin / 'plugin.toml').exists())
    self.assertFalse(self.backup.exists())

  def test_invalid_backend_keeps_the_old_collector_and_can_retry(self):
    self.seed_legacy()
    self.env['TEST_CLI_STATUS'] = '1'
    self.run_transition(success=False)
    self.assertTrue((self.plugin / 'service.luau').exists())
    self.assertFalse(self.backup.exists())
    self.env['TEST_CLI_STATUS'] = '0'
    self.run_transition()
    self.assertTrue((self.backup / 'service.luau').exists())

  def test_backup_collision_preserves_both_plugins(self):
    self.seed_legacy()
    self.put(self.backup / 'service.luau', 'previous archive')
    self.run_transition(success=False)
    self.assertEqual((self.plugin / 'service.luau').read_text(), 'legacy collector')
    self.assertEqual((self.backup / 'service.luau').read_text(), 'previous archive')


unittest.main()
PY

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" MONARCH_PATH="$ROOT"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
unset CODEXBAR_CONFIG CLAUDE_CONFIG_DIR CODEX_HOME
source "$ROOT/install/reconcile/agent-usage.sh"
monarch-cmd-present() { return 1; }
monarch_prepare_agent_usage_transition
[[ ! -e $XDG_CONFIG_HOME/codexbar/config.json ]]
mkdir -p "$HOME/.local/share/noctalia/plugins/monarch-agents"
printf 'legacy collector\n' >"$HOME/.local/share/noctalia/plugins/monarch-agents/service.luau"
if monarch_prepare_agent_usage_transition 2>/dev/null; then
  echo "Transition succeeded without its backend" >&2
  exit 1
fi
[[ -f $HOME/.local/share/noctalia/plugins/monarch-agents/service.luau ]]
echo "Agent usage transition tests passed"
