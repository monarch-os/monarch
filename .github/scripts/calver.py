import os
import re
import subprocess
import tempfile


TAG_PATTERN = re.compile(r"v([1-9][0-9]{3})\.(0[1-9]|1[0-2])\.(0|[1-9][0-9]*)")
INITIAL_MONTH = "2026.10"


def version(tag):
  match = TAG_PATTERN.fullmatch(tag)
  return tuple(map(int, match.groups())) if match else None


def next_tag(tags, pointed_tags, month=""):
  versions = {tag: version(tag) for tag in tags if version(tag) is not None}
  latest = max(versions.values(), default=None)
  if month:
    if not re.fullmatch(r"[1-9][0-9]{3}\.(0[1-9]|1[0-2])", month):
      raise ValueError("Monthly milestone must use YYYY.MM")
    tag = f"v{month}.0"
    if tag in versions:
      if tag not in pointed_tags:
        raise ValueError("Monthly milestone already belongs to another commit")
      return tag
    if latest and tuple(map(int, month.split("."))) <= latest[:2]:
      raise ValueError("Monthly milestone must advance the active month")
    return tag
  existing = [tag for tag in pointed_tags if version(tag) is not None]
  if existing:
    return max(existing, key=version)
  if latest is None:
    return f"v{INITIAL_MONTH}.0"
  year, month_number, patch = latest
  return f"v{year}.{month_number:02d}.{patch + 1}"


def run(*args):
  return subprocess.check_output(args, text=True).strip()


def main():
  month = os.environ.get("RELEASE_MONTH", "")
  notes = os.environ.get("RELEASE_NOTES", "")
  if month and not notes.strip():
    raise ValueError("Monthly publication requires reviewed patch notes")
  run("git", "fetch", "origin", "--tags")
  commit = run("git", "rev-parse", "HEAD")
  tags = run("git", "tag", "--list").splitlines()
  pointed_tags = run("git", "tag", "--points-at", commit).splitlines()
  tag = next_tag(tags, pointed_tags, month)
  ref = os.environ.get("GITHUB_REF", "")
  if ref.startswith("refs/tags/") and ref != f"refs/tags/{tag}":
    raise ValueError("Dispatch on a tag can only publish that existing milestone")
  if month and tag not in tags:
    latest = max((t for t in tags if version(t)), key=version, default=None)
    if latest:
      subprocess.run(["git", "merge-base", "--is-ancestor", latest, commit], check=True)
  if tag not in pointed_tags:
    run("git", "tag", tag, commit)
    run("git", "push", "origin", f"refs/tags/{tag}")
  print(f"{tag}: {commit}")
  if month:
    exists = subprocess.run(["gh", "release", "view", tag], capture_output=True)
    if exists.returncode == 0:
      return
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md") as notes_file:
      notes_file.write(notes)
      notes_file.flush()
      run("gh", "release", "create", tag, "--verify-tag", "--title",
          f"Monarch {month}", "--notes-file", notes_file.name)


if __name__ == "__main__":
  main()
