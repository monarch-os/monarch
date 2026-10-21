#!/usr/bin/python3

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


IDS = ('neovim', 'obsidian', 'zed', 'vscode')


def publish_missing(path, content):
  if os.path.lexists(path):
    return
  fd, temporary = tempfile.mkstemp(prefix='.monarch-template-', dir=path.parent)
  try:
    with os.fdopen(fd, 'wb') as output:
      output.write(content)
      os.fchmod(output.fileno(), 0o644)
    try:
      os.link(temporary, path)
    except FileExistsError:
      pass
  finally:
    Path(temporary).unlink(missing_ok=True)


def seed(source, destination):
  if os.path.lexists(destination):
    return
  staging = Path(tempfile.mkdtemp(prefix='.monarch-template-', dir=destination.parent))
  try:
    shutil.copytree(source, staging, dirs_exist_ok=True)
    # GNU mv uses no-replace rename, preserving even a concurrently created empty directory.
    subprocess.run(['/usr/bin/mv', '-T', '--no-clobber', '--', str(staging), str(destination)], check=True)
  finally:
    if staging.exists():
      shutil.rmtree(staging)


def main():
  parser = argparse.ArgumentParser(description='Seed original offline templates into Noctalia-owned storage.')
  parser.add_argument('--state-home', type=Path)
  args = parser.parse_args()
  runtime = Path(os.environ.get('MONARCH_PATH', Path(__file__).resolve().parents[2]))
  bundle = runtime / 'default/noctalia/community-templates'
  catalog = (bundle / 'catalog.json').read_bytes()
  state = args.state_home or Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
  target = state / 'noctalia/community-templates'
  target.mkdir(parents=True, exist_ok=True)
  for name in IDS:
    seed(bundle / name, target / name)
  publish_missing(target / 'catalog.json', catalog)


if __name__ == '__main__':
  try:
    main()
  except (OSError, ValueError, subprocess.CalledProcessError) as error:
    print(f'Noctalia offline templates: {error}', file=sys.stderr)
    sys.exit(1)
