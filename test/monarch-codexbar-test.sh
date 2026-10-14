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
import tomllib
import unittest


class MigrationTests(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.home = Path(self.temporary.name)
    self.config = self.home / 'config'
    self.state = self.home / 'state'
    self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                    XDG_STATE_HOME=str(self.state))
    for name in ('CODEXBAR_CONFIG', 'CLAUDE_CONFIG_DIR', 'CODEX_HOME'):
      self.env.pop(name, None)

  def put(self, path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return path

  def run_migration(self):
    subprocess.run(['python3', os.environ['ROOT'] + '/install/reconcile/codexbar.py'],
                   env=self.env, check=True)

  def test_migration_preserves_history_and_backs_up_layout(self):
    (self.home / '.claude').mkdir()
    (self.home / '.codex').mkdir()
    disabled = self.put(self.state / 'monarch/agents/disabled/claude', '')
    history = self.put(self.state / 'monarch/agents/usage/codex.json', '{"ready":true}')
    key = self.put(self.config / 'monarch/agents/synthetic.json', '{"apiKey":"test-secret"}')
    layout = self.put(self.config / 'noctalia/config.toml',
                      '[bar.default]\nend = ["tray", "monarch/agents:usage", "volume"]\n')
    mutable = self.put(self.state / 'noctalia/settings.toml', layout.read_text())
    mutable.write_text(mutable.read_text() + '\n[plugins]\nenabled = ["monarch/menu", "monarch/agents", "salemsayed/codexbar-meter"]\n')
    plugin = self.put(self.home / '.local/share/noctalia/plugins/monarch-agents/plugin.toml',
                       'id = "monarch/agents"')
    self.put(plugin.parent / 'service.luau', 'legacy collector')
    self.run_migration()
    target = self.config / 'codexbar/config.json'
    providers = {p['id']: p for p in json.loads(target.read_text())['providers']}
    self.assertFalse(providers['claude']['enabled'])
    self.assertTrue(providers['codex']['enabled'])
    self.assertEqual(providers['codex']['source'], 'cli')
    self.assertEqual(providers['synthetic']['apiKey'], 'test-secret')
    self.assertEqual(target.stat().st_mode & 0o777, 0o600)
    self.assertIn('monarch/agents:usage', layout.read_text())
    self.assertEqual(tomllib.loads(mutable.read_text())['bar'], tomllib.loads(layout.read_text())['bar'])
    self.assertEqual(tomllib.loads(mutable.read_text())['plugins']['enabled'],
                     ['monarch/menu', 'monarch/agents'])
    self.assertTrue(mutable.with_name('settings.toml.before-codexbar').exists())
    self.assertFalse(plugin.exists())
    self.assertTrue((self.state / 'monarch/backups/noctalia/monarch-agents/plugin.toml').exists())
    self.assertTrue(history.exists() and disabled.exists() and key.exists())
    inode = target.stat().st_ino
    self.run_migration()
    self.assertEqual(target.stat().st_ino, inode)

  def test_existing_config_is_not_overwritten(self):
    path = self.put(self.config / 'codexbar/config.json', '{"custom":"keep"}')
    self.run_migration()
    self.assertEqual(path.read_text(), '{"custom":"keep"}')

  def test_current_plugin_is_not_archived(self):
    plugin = self.put(self.home / '.local/share/noctalia/plugins/monarch-agents/plugin.toml',
                      'id = "monarch/agents"')
    self.run_migration()
    self.run_migration()
    self.assertTrue(plugin.exists())
    self.assertFalse((self.state / 'monarch/backups/noctalia/monarch-agents').exists())

  def test_singular_plugin_references_migrate(self):
    layout = self.put(self.config / 'noctalia/config.toml',
                     '[bar.default]\nend = ["monarch/agent:usage"]\n'
                     '[plugins]\nenabled = ["monarch/agent", "monarch/agents"]\n'
                     '[plugin_settings."monarch/agent"]\nrefreshIntervalSec = 120\n')
    self.run_migration()
    migrated = tomllib.loads(layout.read_text())
    self.assertEqual(migrated['bar']['default']['end'], ['monarch/agents:usage'])
    self.assertEqual(migrated['plugins']['enabled'], ['monarch/agents'])
    self.assertEqual(migrated['plugin_settings']['monarch/agents']['refreshIntervalSec'], 120)

  def test_legacy_config_is_not_shadowed(self):
    self.put(self.home / '.codexbar/config.json', '{"custom":"keep"}')
    self.run_migration()
    self.assertFalse((self.config / 'codexbar/config.json').exists())

  def test_fresh_install_has_no_enabled_providers(self):
    self.run_migration()
    data = json.loads((self.config / 'codexbar/config.json').read_text())
    self.assertFalse(any(p['enabled'] for p in data['providers']))

  def test_symlinked_layout_is_untouched(self):
    target = self.put(self.home / 'custom.toml', 'end = ["monarch/agents:usage"]')
    link = self.config / 'noctalia/config.toml'
    link.parent.mkdir(parents=True)
    link.symlink_to(target)
    self.run_migration()
    self.assertEqual(target.read_text(), 'end = ["monarch/agents:usage"]')


unittest.main()
PY

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" MONARCH_PATH="$ROOT"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
export MONARCH_CODEXBAR_PLUGIN_ROOT="$TEST_ROOT/plugins"
unset CODEXBAR_CONFIG CLAUDE_CONFIG_DIR CODEX_HOME
source "$ROOT/install/reconcile/config-files.sh"
source "$ROOT/install/reconcile/codexbar.sh"
monarch-cmd-present() { [[ ${cli_ready:-false} == "true" ]]; }
codexbar() { return 0; }
plugins_changed=false
if monarch_reconcile_codexbar 2>/dev/null; then
  echo "Migration succeeded without its replacement" >&2
  exit 1
fi
[[ ! -e $XDG_CONFIG_HOME/codexbar/config.json ]]
mkdir -p "$MONARCH_CODEXBAR_PLUGIN_ROOT/monarch-agents"
printf 'id = "monarch/agents"\n' >"$MONARCH_CODEXBAR_PLUGIN_ROOT/monarch-agents/plugin.toml"
cli_ready=true
monarch_reconcile_codexbar
[[ $plugins_changed == "true" ]]
[[ -f $HOME/.local/share/noctalia/plugins/monarch-agents/plugin.toml ]]
plugins_changed=false
monarch_reconcile_codexbar
[[ $plugins_changed == "false" ]]
echo "CodexBar migration tests passed"
