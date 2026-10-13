import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("calver", ROOT / ".github/scripts/calver.py")
CALVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CALVER)


class AllocationTest(unittest.TestCase):
  def test_bootstrap_ignores_upstream_tags(self):
    self.assertEqual(CALVER.next_tag(["v4.0.4", "v0.12.0"], []), "v2026.10.0")

  def test_numeric_increment(self):
    self.assertEqual(CALVER.next_tag(["v2026.10.9", "v2026.10.10"], []), "v2026.10.11")

  def test_retry(self):
    self.assertEqual(CALVER.next_tag(["v2026.10.1", "v2026.10.2"], ["v2026.10.1"]), "v2026.10.1")

  def test_monthly_rollover_and_retry(self):
    self.assertEqual(CALVER.next_tag(["v2026.10.9"], [], "2026.11"), "v2026.11.0")
    self.assertEqual(CALVER.next_tag(["v2026.11.0"], ["v2026.11.0"], "2026.11"), "v2026.11.0")
    self.assertEqual(CALVER.next_tag(["v2026.12.9"], [], "2027.01"), "v2027.01.0")

  def test_invalid_months_and_existing_milestone(self):
    for month in ["2026.1", "2026.00", "2026.13", "2026.10", "2026.09", "$(exit 1)"]:
      with self.subTest(month=month), self.assertRaises(ValueError):
        CALVER.next_tag(["v2026.10.2"], [], month)
    with self.assertRaises(ValueError):
      CALVER.next_tag(["v2026.11.0"], [], "2026.11")


class GitTest(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.addCleanup(self.tmp.cleanup)
    self.repo = Path(self.tmp.name) / "repo"
    remote = Path(self.tmp.name) / "remote.git"
    subprocess.run(["git", "init", "--bare", "--quiet", str(remote)], check=True)
    self.repo.mkdir()
    self.git("init", "--quiet")
    self.git("config", "user.name", "Test")
    self.git("config", "user.email", "test@example.invalid")
    self.git("remote", "add", "origin", str(remote))
    self.commit()
    (self.repo / "version").write_text("0.12.0\n")

  def git(self, *args):
    return subprocess.check_output(["git", *args], cwd=self.repo, text=True).strip()

  def commit(self):
    self.git("commit", "--quiet", "--allow-empty", "-m", "Change")

  def allocate(self, **env):
    environment = dict(os.environ, RELEASE_MONTH="", RELEASE_NOTES="")
    environment.update(env)
    return subprocess.run(["python3", str(ROOT / ".github/scripts/calver.py")],
                          cwd=self.repo, env=environment, capture_output=True, text=True)

  def cli(self, *args):
    return subprocess.run(["bash", str(ROOT / "bin/monarch-version"), *args],
                          env=dict(os.environ, MONARCH_PATH=str(self.repo)),
                          capture_output=True, text=True)

  def test_push_and_retry_tag_exact_commit(self):
    result = self.allocate()
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(self.git("rev-parse", "v2026.10.0"), self.git("rev-parse", "HEAD"))
    self.assertEqual(self.allocate().returncode, 0)
    self.commit()
    self.assertEqual(self.allocate().returncode, 0)
    self.assertEqual(self.git("tag", "--list"), "v2026.10.0\nv2026.10.1")
    self.assertIn("refs/tags/v2026.10.1", self.git("ls-remote", "--tags", "origin"))

  def test_source_version_and_out_of_order_tags(self):
    self.git("tag", "v2026.10.2")
    self.commit()
    self.git("tag", "v2026.10.1")
    self.assertRegex(self.cli().stdout.strip(), r"^2026\.10\.2\.r1\.g[0-9a-f]+$")
    self.assertEqual(self.cli("--commit").stdout.strip(), self.git("rev-parse", "HEAD"))

  def test_legacy_and_packaged_identity(self):
    self.assertEqual(self.cli().stdout, "0.12.0\n")
    self.assertEqual(self.cli("--invalid").returncode, 2)
    self.assertEqual(self.cli("--commit", "extra").returncode, 2)
    (self.repo / "revision").write_text("abcdef\n")
    self.assertEqual(self.cli("--commit").stdout, "abcdef\n")
    (self.repo / ".git").rename(Path(self.tmp.name) / "git")
    (self.repo / "version").write_text("2026.10.3\n")
    self.assertEqual(self.cli().stdout, "2026.10.3\n")
    self.assertEqual(self.cli("--commit").stdout, "abcdef\n")
    (self.repo / "revision").unlink()
    self.assertEqual(self.cli("--commit").returncode, 1)

  def test_monthly_notes_required_before_tagging(self):
    environment = dict(os.environ, RELEASE_MONTH="2026.11", RELEASE_NOTES="")
    result = subprocess.run(["python3", str(ROOT / ".github/scripts/calver.py")],
                            cwd=self.repo, env=environment, capture_output=True)
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.git("tag", "--list"), "")

  def test_monthly_publication_and_retry(self):
    tools = Path(self.tmp.name) / "bin"
    tools.mkdir()
    state = Path(self.tmp.name) / "release"
    gh = tools / "gh"
    gh.write_text("#!/bin/bash\n"
                  'if [[ $2 == view ]]; then [[ -f $RELEASE_STATE ]]; exit; fi\n'
                  '[[ $2 == create && $3 == v2026.11.0 ]] || exit 2\n'
                  '[[ ${FAIL_RELEASE:-0} == 0 ]] || exit 1\n'
                  'printf "%s\\n" "$*" >"$RELEASE_STATE"\n')
    gh.chmod(0o755)
    self.assertEqual(self.allocate().returncode, 0)
    self.commit()
    environment = dict(RELEASE_MONTH="2026.11", RELEASE_NOTES="Reviewed notes",
                       RELEASE_STATE=str(state), PATH=f"{tools}:{os.environ['PATH']}")
    failed = self.allocate(**dict(environment, FAIL_RELEASE="1"))
    self.assertNotEqual(failed.returncode, 0)
    self.assertIn("v2026.11.0", self.git("tag", "--list"))
    self.commit()
    self.assertEqual(self.allocate().returncode, 0)
    self.git("checkout", "--quiet", "v2026.11.0")
    result = self.allocate(**environment)
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertIn("--verify-tag", state.read_text())
    self.assertEqual(self.allocate(**environment).returncode, 0)
    self.assertEqual(self.git("tag", "--list"), "v2026.10.0\nv2026.11.0\nv2026.11.1")

  def test_monthly_rejects_old_revision(self):
    self.git("tag", "v2026.10.0")
    first = self.git("rev-parse", "HEAD")
    self.commit()
    self.git("tag", "v2026.10.1")
    self.git("checkout", "--quiet", first)
    result = self.allocate(RELEASE_MONTH="2026.11", RELEASE_NOTES="Reviewed notes")
    self.assertNotEqual(result.returncode, 0)
    self.assertNotIn("v2026.11.0", self.git("tag", "--list"))

  def test_tag_dispatch_cannot_create_new_month(self):
    self.assertEqual(self.allocate().returncode, 0)
    result = self.allocate(RELEASE_MONTH="2026.11", RELEASE_NOTES="Reviewed notes",
                           GITHUB_REF="refs/tags/v2026.10.0")
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(self.git("tag", "--list"), "v2026.10.0")


if __name__ == "__main__":
  unittest.main()
