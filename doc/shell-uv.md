# Optional uv shell helpers

These Bash/Zsh functions are loaded only when `uv` is available on `PATH`.
They do not install uv or change `pyreq`, `pv`, pipx, or the global Python selection.
After installing uv, open a new terminal to load them.

- `uvv`: create `.venv` in the current directory and activate it in the current
  shell. An existing environment is activated without recreation. If `.venv`
  exists but has no readable `bin/activate`, the helper refuses to replace it.
  It takes no arguments; use `uv venv` directly for custom locations or options.
- `uvr …`: run `uv run …`, forwarding arguments unchanged.
- `uvreq …`: run `uv pip install -r requirements.txt …`, forwarding additional
  arguments unchanged. uv selects the environment using its normal rules.
- `uvpwn …`: run Python with pwntools using
  `uv run --isolated --no-project --with pwntools python …`. It does not discover
  or synchronize the current project. Arguments go to Python, not to uv.

The wrappers preserve uv's exit status. Running them can download Python or
dependencies according to uv's own configuration; merely loading the shell
does not install or download anything. pwntools is resolved by uv, not pinned
by Monarch.

```bash
uvv
uvreq
uvr script.py 'an argument with spaces'
uvpwn exploit.py --help
deactivate
```
