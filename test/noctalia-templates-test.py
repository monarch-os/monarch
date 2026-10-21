#!/usr/bin/python3

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / 'install/reconcile/noctalia-templates.py'
BUNDLE = ROOT / 'default/noctalia/community-templates'
spec = importlib.util.spec_from_file_location('seed', HELPER)
module = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(module)


def snapshot(root):
  return {str(path.relative_to(root)): (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns)
          for path in root.rglob('*') if path.is_file()}


with tempfile.TemporaryDirectory() as temporary:
  root = Path(temporary)
  home = root / 'home'
  home.mkdir()
  state = root / 'state with spaces'
  runtime = root / 'runtime'
  packaged = runtime / 'default/noctalia/community-templates'
  shutil.copytree(BUNDLE, packaged)
  catalog_bytes = b'{"templates":[]}\n'
  (packaged / 'catalog.json').write_bytes(catalog_bytes)
  for name in module.IDS:
    (packaged / name / '.noctalia-cache.json').write_text('{"version":1,"files":{}}\n')
  env = dict(os.environ, HOME=str(home), MONARCH_PATH=str(runtime), XDG_STATE_HOME=str(state))

  def seed(success=True, environment=env):
    result = subprocess.run(['python3', str(HELPER)], env=environment, capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stderr
    return result

  seed()
  cache = state / 'noctalia/community-templates'
  assert (cache / 'catalog.json').read_bytes() == catalog_bytes
  for name in module.IDS:
    directory = cache / name
    for source in (packaged / name).iterdir():
      copied = directory / source.name
      assert copied.read_bytes() == source.read_bytes()
      assert copied.stat().st_mode == source.stat().st_mode
    config = tomllib.loads((directory / 'template.toml').read_text())
    for entry in config['templates'].values():
      assert (directory / entry['input_path']).is_file()
  before = snapshot(cache)
  seed()
  assert snapshot(cache) == before
  print('ok - packaged templates and opaque metadata are copied intact and seeded idempotently')

  (cache / 'catalog.json').write_text('user catalog')
  (cache / 'neovim/matugen-template.lua').write_text('user template')
  before = snapshot(cache)
  seed()
  assert snapshot(cache) == before
  assert not (state / 'noctalia/settings.toml').exists()
  print('ok - existing catalog, customized templates and mutable Noctalia settings remain untouched')

  missing = cache / 'obsidian/obsidian.css'
  missing.unlink()
  (cache / 'obsidian/apply.sh').unlink()
  unknown = cache / 'obsidian/unknown.txt'
  unknown.write_text('different cache generation')
  before = snapshot(cache)
  seed()
  assert snapshot(cache) == before
  assert not missing.exists()
  assert not (cache / 'obsidian/apply.sh').exists()
  shutil.rmtree(cache / 'vscode')
  seed()
  assert (cache / 'vscode/template.toml').is_file()
  assert not missing.exists()
  print('ok - partial caches are preserved without blocking other missing templates')

  target = root / 'upstream'
  target.mkdir()
  (target / 'template.toml').write_text('[templates.other]\ninput_path="other.txt"\noutput_path="rendered.txt"\n')
  (target / 'other.txt').write_text('upstream')
  shutil.rmtree(cache / 'zed')
  (cache / 'zed').symlink_to(target, target_is_directory=True)
  before = snapshot(target)
  seed()
  assert snapshot(target) == before
  assert (cache / 'zed').is_symlink()
  (target / 'other.txt').unlink()
  seed()
  assert not (target / 'zed.json').exists()
  (target / 'other.txt').write_text('upstream')
  print('ok - symlinked and newer upstream templates are never replaced or reclassified')

  (cache / 'zed').unlink()
  (cache / 'zed').symlink_to(root / 'absent')
  seed()
  assert (cache / 'zed').is_symlink() and not (root / 'absent').exists()
  (cache / 'zed').unlink()
  (cache / 'zed').write_text('not a directory')
  seed()
  assert (cache / 'zed').read_text() == 'not a directory'
  (cache / 'zed').unlink()
  (cache / 'zed').mkdir()
  seed()
  assert not list((cache / 'zed').iterdir())
  (cache / 'zed/template.toml').write_text('not valid TOML')
  seed()
  assert (cache / 'zed/template.toml').read_text() == 'not valid TOML'
  print('ok - dangling links, files, empty directories and malformed manifests are preserved')

  original_copytree = shutil.copytree

  def failed_copy(source, destination, **kwargs):
    (destination / 'partial').write_text('interrupted')
    raise OSError('simulated copy failure')

  with patch.object(shutil, 'copytree', side_effect=failed_copy):
    try:
      module.seed(BUNDLE / 'zed', root / 'failed')
    except OSError:
      pass
    else:
      raise AssertionError('copy failure reported success')
  assert not (root / 'failed').exists()
  assert not list(root.glob('.monarch-template-*'))
  print('ok - failed initial copies do not publish an incomplete template')

  concurrent = root / 'concurrent'

  def concurrent_copy(source, destination, **kwargs):
    original_copytree(source, destination, **kwargs)
    concurrent.mkdir()

  with patch.object(shutil, 'copytree', side_effect=concurrent_copy):
    module.seed(BUNDLE / 'zed', concurrent)
  assert not list(concurrent.iterdir())
  assert not list(root.glob('.monarch-template-*'))
  print('ok - concurrent creation of an empty cache is preserved')

  absent_state = root / 'unpackaged-state'
  seed(success=False, environment=dict(env, MONARCH_PATH=str(ROOT), XDG_STATE_HOME=str(absent_state)))
  assert not absent_state.exists()
  print('ok - unpackaged sources fail before publishing caches without metadata')

  skel = root / 'etc/skel/.local/state'
  subprocess.run(['python3', str(HELPER), '--state-home', str(skel)], env=env, check=True)
  assert (skel / 'noctalia/community-templates/obsidian/apply.sh').is_file()
  assert (cache / 'catalog.json').read_text() == 'user catalog'
  print('ok - packaging can seed skel independently of the calling user state')

  vault = home / 'Documents/test vault/.obsidian'
  vault.mkdir(parents=True)
  (vault / 'appearance.json').write_text('{"theme":"moonstone","enabledCssSnippets":["personal"]}')
  obsidian = cache / 'obsidian'
  shutil.rmtree(obsidian)
  seed()
  hook_env = dict(env, XDG_CONFIG_HOME=str(home / '.config'))
  result = subprocess.run(['bash', str(obsidian / 'apply.sh'), 'output'], env=hook_env,
                          capture_output=True, text=True, check=True)
  assert result.stdout.splitlines() == [str(vault / 'snippets/noctalia.css')]
  assert (vault / 'snippets').is_dir()
  for _ in range(2):
    subprocess.run(['bash', str(obsidian / 'apply.sh'), 'apply'], env=hook_env, check=True)
  appearance = json.loads((vault / 'appearance.json').read_text())
  assert appearance == {'theme': 'moonstone', 'enabledCssSnippets': ['personal', 'noctalia']}
  print('ok - packaged upstream Obsidian hook exposes dynamic outputs and enables the snippet idempotently')
