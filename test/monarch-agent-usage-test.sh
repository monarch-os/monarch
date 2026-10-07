#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u MISE_DATA_DIR HOME="$TEST_HOME" \
  XDG_CACHE_HOME="$TEST_HOME/cache" XDG_DATA_HOME="$TEST_HOME/data" ROOT="$ROOT" \
  PYTHONDONTWRITEBYTECODE=1 python3 <<'PY'
import datetime as dt
import importlib.machinery
import importlib.util
import json
import io
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


def load(agent):
  loader = importlib.machinery.SourceFileLoader(agent, str(Path(os.environ['ROOT']) / 'bin' / ('monarch-agent-usage-' + agent)))
  spec = importlib.util.spec_from_loader(agent, loader)
  module = importlib.util.module_from_spec(spec)
  loader.exec_module(module)
  return module


class UsageTests(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory(dir=Path.home())
    self.addCleanup(self.tmp.cleanup)
    self.root = Path(self.tmp.name)
    self.claude = load('claude')
    self.codex = load('codex')
    self.projects = self.root / 'projects'
    self.projects.mkdir()
    self.cache = self.root / 'cache'
    self.cache.mkdir()
    for module in (self.claude, self.codex):
      override = patch.object(module, 'cache_root', return_value=self.cache)
      override.start()
      self.addCleanup(override.stop)

  def claude_line(self, output, model='claude', input=10):
    return json.dumps({'type': 'assistant', 'timestamp': dt.datetime.now(dt.timezone.utc).isoformat(), 'sessionId': 's',
      'message': {'id': 'm', 'model': model, 'usage': {'input_tokens': input, 'output_tokens': output}}}) + '\n'

  def test_claude_stream_snapshot_and_duplicates(self):
    (self.projects / 'a.jsonl').write_text(self.claude_line(1, 'old', 100) + self.claude_line(20, 'new', 10))
    (self.projects / 'b.jsonl').write_text(self.claude_line(2, 'old', 100))
    stats = self.claude.scan_projects(self.projects)
    self.assertEqual(stats['totalPrompts'], 1)
    self.assertEqual(stats['todayTotalTokens'], 30)
    self.assertEqual(set(stats['modelUsage']), {'new'})

  def test_claude_index_append_partial_rewrite_delete(self):
    path = self.projects / 'a.jsonl'
    index = self.cache / 'index.json'
    path.write_text(self.claude_line(1))
    first = self.claude.scan_projects(self.projects, index)
    with patch.object(self.claude, 'read_digest', side_effect=AssertionError('unchanged file reopened')):
      self.assertEqual(self.claude.scan_projects(self.projects, index), first)
    final = self.claude_line(20)
    with path.open('a') as f:
      f.write(final[:-1])
    self.assertEqual(self.claude.scan_projects(self.projects, index)['todayTotalTokens'], 11)
    with path.open('a') as f:
      f.write('\n')
    self.assertEqual(self.claude.scan_projects(self.projects, index)['todayTotalTokens'], 30)
    path.write_text(self.claude_line(5))
    self.assertEqual(self.claude.scan_projects(self.projects, index)['todayTotalTokens'], 15)
    path.unlink()
    self.assertEqual(self.claude.scan_projects(self.projects, index)['totalPrompts'], 0)

  def test_claude_corrupt_caches_and_force(self):
    path = self.projects / 'a.jsonl'
    path.write_text(self.claude_line(5))
    summary, _, index = self.claude.scan_cache_paths(self.projects)
    summary.write_text('[]')
    index.write_text(json.dumps({'version': self.claude.INDEX_VERSION, 'zone': self.claude.index_zone(), 'files': {str(path): {'records': [[]]}}}))
    self.assertEqual(self.claude.cached_scan(self.projects, 900)['todayTotalTokens'], 15)
    summary.write_text(json.dumps({'schemaVersion': 2, 'scanDate': '2000-01-01', 'stats': {'totalPrompts': 999}}))
    self.assertEqual(self.claude.cached_scan(self.projects, 900)['totalPrompts'], 1)
    with patch.object(self.claude, 'parse_usage_records', wraps=self.claude.parse_usage_records) as parse:
      self.claude.cached_scan(self.projects, 0, use_index=False)
      self.assertIsNone(parse.call_args.args[1])

  def test_claude_plan_is_scoped_to_config_home(self):
    credentials = {'claudeAiOauth': {'accessToken': 'fixture', 'expiresAt': 1, 'refreshTokenExpiresAt': 2,
      'rateLimitTier': 'default_claude_max_5x', 'subscriptionType': 'team'}}
    (self.root / '.credentials.json').write_text(json.dumps(credentials))
    (self.root / '.claude.json').write_text(json.dumps({'oauthAccount': {'organizationRateLimitTier': 'default_claude_max_20x'}}))
    self.assertEqual(self.claude.oauth_login(self.root), ('fixture', 1, 2, 'Team 20x'))
    (self.root / '.claude.json').write_text('[]')
    self.assertEqual(self.claude.oauth_login(self.root)[3], 'Team 5x')

  def test_claude_expiry_freshness_and_failure(self):
    now = time.time() * 1000
    future = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)
    limits = [{'label': 'Session', 'percent': 0.4, 'resetsAt': future.isoformat()}]
    self.claude.write_json(self.cache / 'claude-limits.json', {'fetchedAtMs': now - 60000, 'limits': limits})
    with patch.object(self.claude, 'probe_limits', side_effect=AssertionError('expired token was probed')):
      paused = self.claude.collect_limits('fixture', now - 1, now + 60000, True)
      self.assertEqual(paused['usageStatusText'], 'Limits paused')
      self.assertFalse(paused['live'])
      expired = self.claude.collect_limits('fixture', now - 1, now - 1, True)
      self.assertEqual(expired['usageStatusText'], 'Sign-in expired')
    with patch.object(self.claude, 'probe_limits', return_value={'ok': True, 'limits': limits}) as probe:
      live = self.claude.collect_limits('fixture', now + 60000, 0, True)
      self.assertTrue(live['live'])
      self.claude.collect_limits('fixture', now + 60000, 0, False)
      self.assertEqual(probe.call_count, 1)
    with patch.object(self.claude, 'probe_limits', return_value={'ok': False, 'helpText': 'offline', 'transport': True}):
      failed = self.claude.collect_limits('fixture', now + 60000, 0, True)
      self.assertEqual(failed['limits'], limits)
      self.assertTrue(failed['retryAdvised'])
      self.assertFalse(failed['live'])

  def test_claude_invalid_endpoint_json(self):
    with patch.object(self.claude.urllib.request, 'urlopen', return_value=io.BytesIO(b'[]')):
      self.assertFalse(self.claude.probe_limits('fixture')['ok'])

  def test_elapsed_cached_window_has_no_old_usage_or_reset(self):
    old = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)
    cached = {'limits': [{'label': 'Session', 'percent': 0.95, 'resetsAt': old.isoformat()}]}
    self.assertEqual(self.claude.usable_cached_limits(cached), [{'label': 'Session', 'percent': 0.0, 'resetsAt': ''}])

  def test_codex_partial_limit_payload(self):
    self.assertIsNone(self.codex.limit_window({'usedPercent': 'bad'}))
    self.assertIsNone(self.codex.limit_window({'usedPercent': float('nan')}))
    self.assertEqual(self.codex.limit_window({'usedPercent': 25, 'resetsAt': 'bad'})['percent'], 0.25)

  def test_claude_opencode_v1_v2_and_malformed_rows(self):
    db = Path(os.environ['XDG_DATA_HOME']) / 'opencode' / 'opencode.db'
    db.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db) as conn:
      conn.execute('CREATE TABLE message (session_id TEXT, data TEXT)')
      conn.execute('CREATE TABLE session_message (session_id TEXT, data TEXT, type TEXT)')
      conn.execute('INSERT INTO message VALUES (?, ?)', ('s1', json.dumps({'role': 'assistant', 'providerID': 'anthropic', 'modelID': 'claude', 'tokens': {'input': 10, 'output': 5}})))
      conn.execute('INSERT INTO message VALUES (?, ?)', ('bad', '[]'))
      for provider in ('anthropic', 'anthropic-proxy'):
        conn.execute('INSERT INTO session_message VALUES (?, ?, ?)', ('s2', json.dumps({'model': {'providerID': provider, 'id': 'claude'}, 'tokens': {'input': 10, 'output': 5}}), 'assistant'))
    conn.close()
    self.addCleanup(db.unlink)
    stats = self.claude.scan_opencode_usage(0)
    self.assertEqual(stats['totalPrompts'], 2)
    self.assertEqual(stats['todayTotalTokens'], 30)

  def codex_file(self, provider='openai'):
    path = self.root / 'rollout.jsonl'
    events = [{'type': 'session_meta', 'payload': {'model_provider': provider}}, {'type': 'turn_context', 'payload': {'model': 'gpt'}}]
    for total in (15, 15, 30):
      events.append({'type': 'event_msg', 'timestamp': dt.datetime.now(dt.timezone.utc).isoformat(), 'payload': {'type': 'token_count',
        'info': {'last_token_usage': {'input_tokens': 10, 'cached_input_tokens': 3, 'output_tokens': 5}, 'total_token_usage': {'total_tokens': total}}}})
    path.write_text(''.join(json.dumps(event) + '\n' for event in events))
    return path

  def test_codex_provider_and_cumulative_duplicates(self):
    path = self.codex_file()
    record = self.codex.read_native_codex_session(path, path.stat())
    self.codex.merge_file_record(str(path), record)
    self.assertEqual(self.codex.local_stats()['todayTotalTokens'], 30)
    self.assertEqual(self.codex.local_stats()['totalPrompts'], 2)
    self.assertEqual(self.codex.local_stats()['modelUsage']['gpt']['inputTokens'], 14)
    path = self.codex_file('ollama')
    self.assertEqual(self.codex.read_native_codex_session(path, path.stat())['days'], {})

  def test_codex_file_cache_validation(self):
    path = self.codex_file()
    record = self.codex.read_native_codex_session(path, path.stat())
    self.codex.write_file_cache({str(path): record})
    loaded = self.codex.read_file_cache()
    self.assertEqual(self.codex.reusable_record(loaded, str(path), path.stat()), record)
    with path.open('a') as f:
      f.write('{}\n')
    self.assertIsNone(self.codex.reusable_record(loaded, str(path), path.stat()))
    self.codex.file_cache_path().write_text(json.dumps({'schemaVersion': self.codex.FILE_CACHE_SCHEMA, 'zone': self.codex.file_cache_zone(), 'files': {'bad': []}}))
    self.assertEqual(self.codex.read_file_cache(), {})

  def test_codex_scan_reuses_unchanged_files_and_force_rereads(self):
    home = self.root / 'codex'
    sessions = home / 'sessions'
    sessions.mkdir(parents=True)
    path = self.codex_file()
    path.rename(sessions / path.name)
    with patch.dict(os.environ, {'CODEX_HOME': str(home)}):
      first = self.codex.cached_local_stats(0)
      second = load('codex')
      with patch.object(second, 'cache_root', return_value=self.cache), \
           patch.object(second, 'read_native_codex_session', side_effect=AssertionError('unchanged file reopened')):
        self.assertEqual(second.cached_local_stats(0), first)
      third = load('codex')
      with patch.object(third, 'cache_root', return_value=self.cache), \
           patch.object(third, 'read_native_codex_session', wraps=third.read_native_codex_session) as read:
        self.assertEqual(third.cached_local_stats(0, use_file_cache=False), first)
        self.assertEqual(read.call_count, 1)

  def test_codex_lazy_launcher_is_never_executed(self):
    lazy = self.root / 'lazy'
    real = self.root / 'real'
    lazy.mkdir()
    real.mkdir()
    (lazy / 'codex').write_text('#!/bin/bash\nmise use -g codex\n')
    (real / 'codex').write_text('#!/bin/bash\nexit 0\n')
    for path in (lazy / 'codex', real / 'codex'):
      path.chmod(0o755)
    with patch.dict(self.codex.ENV, {'PATH': str(lazy) + ':' + str(real)}):
      self.assertEqual(self.codex.find_codex_binary(), str(real / 'codex'))

  def rpc_process(self, body):
    proc = subprocess.Popen([sys.executable, '-u', '-c', body], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def cleanup():
      if proc.poll() is None:
        proc.kill()
      proc.wait()
      proc.stdin.close()
      proc.stdout.close()
    self.addCleanup(cleanup)
    return proc

  def test_rpc_batched_notifications_and_buffered_reply(self):
    proc = self.rpc_process('import sys,time; sys.stdin.readline(); sys.stdout.write(\'{}\\n{"id":1,"result":{}}\\n{"id":2,"result":{}}\\n\'); sys.stdout.flush(); time.sleep(10)')
    self.assertEqual(self.codex.rpc_request(proc, 1, 'first', timeout=1)['id'], 1)
    self.assertEqual(self.codex.rpc_request(proc, 2, 'second', timeout=0.1)['id'], 2)

  def test_rpc_partial_line_has_a_real_deadline(self):
    proc = self.rpc_process('import sys,time; sys.stdin.readline(); sys.stdout.write(\'{"id":1\'); sys.stdout.flush(); time.sleep(10)')
    start = time.monotonic()
    with self.assertRaises(TimeoutError):
      self.codex.rpc_request(proc, 1, 'partial', timeout=0.2)
    self.assertLess(time.monotonic() - start, 1)

  def test_codex_limits_do_not_require_identity(self):
    proc = self.rpc_process('import sys,time; sys.stdin.readline(); time.sleep(10)')
    def reply(proc, request_id, method, *args, **kwargs):
      if method == 'initialize':
        return {'result': {}}
      if method == 'account/rateLimits/read':
        return {'result': {'rateLimits': {'primary': {'usedPercent': 25}}}}
      raise TimeoutError('account/read')
    with patch.object(self.codex, 'find_codex_binary', return_value='/fixture/codex'), \
         patch.object(self.codex.subprocess, 'Popen', return_value=proc), \
         patch.object(self.codex, 'rpc_request', side_effect=reply) as rpc:
      record = self.codex.fetch_codex_rpc()
    self.assertEqual([call.args[2] for call in rpc.call_args_list], ['initialize', 'account/rateLimits/read', 'account/read'])
    self.assertEqual(record['limits'][0]['percent'], 0.25)
    self.assertFalse(record['limitsStale'])


unittest.main(verbosity=2)
PY
