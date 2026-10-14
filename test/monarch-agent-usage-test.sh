#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

python3 - <<'PY'
import errno
import json
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import unittest


class UsageTests(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.home = Path(self.temporary.name)
    self.bin = self.home / 'bin'
    self.bin.mkdir()
    self.root = Path(os.environ['ROOT'])
    self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ':/usr/bin',
                    CODEXBAR_CONFIG=str(self.home / 'config/codexbar.json'), ROOT=str(self.root),
                    TEST_CALLS=str(self.home / 'calls'), TEST_KEY='dummy-secret-for-tests',
                    TEST_HOME=str(self.home))
    self.script('monarch-cmd-present', 'command -v "$1" >/dev/null')
    self.script('codexbar', 'exec python3 "$ROOT/test/fixtures/codexbar-config.py" "$@"')
    self.script('noctalia', 'exit 1')
    self.script('gum', '''
case "$1" in
input)
  [[ ${TEST_CANCEL:-false} != true ]] || exit 130
  printf '%s' "${TEST_KEY}"
  ;;
filter)
  [[ ! -f $TEST_HOME/selected ]] || exit 130
  touch "$TEST_HOME/selected"
  printf '%s\n' 'synthetic | Synthetic | disabled'
  ;;
choose)
  if [[ $* == *'Authentication for'* ]]; then
    echo 'API key'
  else
    echo "${TEST_ACTION:-Configure authentication}"
  fi
  ;;
esac
''')

  def script(self, name, content):
    path = self.bin / name
    path.write_text('#!/bin/bash\n' + content + '\n')
    path.chmod(0o755)

  def run_usage(self, *args, terminal=False, trace=False):
    command = ['bash'] + (['-x'] if trace else []) + [str(self.root / 'bin/monarch-agent-usage'), *args]
    if not terminal:
      return subprocess.run(command, env=self.env, text=True, capture_output=True, timeout=10)
    master, slave = pty.openpty()
    try:
      process = subprocess.Popen(command, env=self.env, stdin=slave, stdout=slave, stderr=slave)
      os.close(slave)
      slave = None
      code = process.wait(timeout=10)
      output = b''
      while True:
        try:
          part = os.read(master, 4096)
          if not part:
            break
          output += part
        except OSError as error:
          if error.errno != errno.EIO:
            raise
          break
      return subprocess.CompletedProcess(command, code, output.decode(), '')
    finally:
      if slave is not None:
        os.close(slave)
      os.close(master)

  def data(self):
    return {entry['provider']: entry for entry in json.loads(Path(self.env['CODEXBAR_CONFIG']).read_text())}

  def test_wiki_enable_disable_status(self):
    self.assertEqual(self.run_usage('enable', 'claude').returncode, 0)
    self.assertEqual(self.run_usage('status', 'claude').stdout.strip(), 'claude: enabled')
    self.assertEqual(self.run_usage('disable', 'claude').returncode, 0)
    self.assertEqual(self.run_usage('status', 'claude').stdout.strip(), 'claude: disabled')
    self.assertIn('openrouter', self.run_usage('providers').stdout)

  def test_unknown_provider_and_arguments_do_not_mutate(self):
    for args in [('enable', 'unknown'), ('disable',), ('status', 'unknown'), ('providers', 'claude')]:
      self.assertNotEqual(self.run_usage(*args).returncode, 0)
    self.assertFalse(Path(self.env['CODEXBAR_CONFIG']).exists())

  def test_key_uses_stdin_and_stays_out_of_trace(self):
    result = self.run_usage('setup', 'synthetic', terminal=True, trace=True)
    self.assertEqual(result.returncode, 0, result.stdout)
    self.assertEqual(self.data()['synthetic']['apiKey'], self.env['TEST_KEY'])
    self.assertTrue(self.data()['synthetic']['enabled'])
    self.assertEqual(self.data()['synthetic']['source'], 'api')
    calls = Path(self.env['TEST_CALLS']).read_text()
    self.assertIn('--stdin', calls)
    self.assertNotIn(self.env['TEST_KEY'], calls + result.stdout)
    self.assertFalse((self.home / '.config/monarch/agents').exists())

  def test_cancel_empty_key_and_rejected_key_do_not_mutate(self):
    for overrides in ({'TEST_CANCEL': 'true'}, {'TEST_KEY': '   '}, {'TEST_KEY_FAILURE': 'true'}):
      self.env.update(overrides)
      self.assertNotEqual(self.run_usage('setup', 'synthetic', terminal=True).returncode, 0)
      self.assertFalse(Path(self.env['CODEXBAR_CONFIG']).exists())
      self.env.pop('TEST_CANCEL', None)
      self.env.pop('TEST_KEY_FAILURE', None)
      self.env['TEST_KEY'] = 'dummy-secret-for-tests'

  def test_native_auth_setup_needs_no_key(self):
    for provider, source in [('claude', 'oauth'), ('codex', 'cli')]:
      self.assertEqual(self.run_usage('setup', provider, terminal=True).returncode, 0)
      self.assertEqual(self.data()[provider]['source'], source)
      self.assertNotIn('apiKey', self.data()[provider])

  def test_noninteractive_setup_fails_without_mutation(self):
    self.assertNotEqual(self.run_usage('setup', 'synthetic').returncode, 0)
    self.assertFalse(Path(self.env['CODEXBAR_CONFIG']).exists())

  def test_manager_can_disable_a_provider(self):
    self.run_usage('enable', 'synthetic')
    self.env['TEST_ACTION'] = 'Disable'
    self.assertEqual(self.run_usage('manage', terminal=True).returncode, 0)
    self.assertFalse(self.data()['synthetic']['enabled'])

  @unittest.skipUnless(os.environ.get('MONARCH_TEST_CODEXBAR'), 'Optional real CodexBar CLI check')
  def test_real_codexbar_config_roundtrip(self):
    self.script('codexbar', 'exec "$MONARCH_TEST_CODEXBAR" "$@"')
    result = self.run_usage('setup', 'synthetic', terminal=True)
    self.assertEqual(result.returncode, 0, result.stdout)
    config = Path(self.env['CODEXBAR_CONFIG'])
    data = json.loads(config.read_text())
    synthetic = next(provider for provider in data['providers'] if provider['id'] == 'synthetic')
    self.assertEqual(synthetic['apiKey'], self.env['TEST_KEY'])
    self.assertEqual(synthetic['source'], 'api')
    self.assertEqual(config.stat().st_mode & 0o777, 0o600)
    self.assertNotIn(self.env['TEST_KEY'], result.stdout)
    self.assertEqual(self.run_usage('status', 'synthetic').stdout.strip(), 'synthetic: enabled')
    self.assertEqual(self.run_usage('disable', 'synthetic').returncode, 0)
    self.assertEqual(self.run_usage('status', 'synthetic').stdout.strip(), 'synthetic: disabled')


unittest.main()
PY
