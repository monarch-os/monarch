import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("crash_model", ROOT / "default/monarch/crash-report/model.py")
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class Reports(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.draft = model.Draft(ROOT, "a" * 32 + ":42:123456789", self.temp.name)
    self.draft.data = {"report": {"crash": {"application": "app", "signal": "SIGILL"}},
      "documents": [], "analysis": None, "additional": "", "frozen": None, "endpoint": None,
      "submission": "c253c081-d0e4-44d9-bb22-fafc675cf27e"}

  def test_only_approved_versions_leave_the_machine(self):
    self.draft.add_document("stack.txt", "stack", "path /home/alex/private\n#0 main")
    doc = self.draft.data["documents"][0]
    self.assertEqual(self.draft.payload()["attachments"], [])
    self.draft.approve(doc, True)
    payload = self.draft.payload()
    self.assertNotIn("original", payload["attachments"][0])
    self.assertNotIn("/home/alex", json.dumps(payload))
    self.draft.edit(doc, "changed")
    self.assertEqual(self.draft.payload()["attachments"], [])
    self.draft.approve(doc, True)
    doc["content"] = "changed behind the reviewer"
    with self.assertRaises(ValueError):
      self.draft.payload()

  def test_failure_needs_explicit_override(self):
    self.draft.add_document("raw.txt", "purpose", "text", "failed")
    doc = self.draft.data["documents"][0]
    with self.assertRaises(ValueError):
      self.draft.approve(doc, True)
    self.draft.approve(doc, True, True)
    self.assertTrue(self.draft.payload()["attachments"][0]["override"])

  def test_budgets_are_bytes_and_binary_is_rejected(self):
    model.text("é" * (model.FILE_LIMIT // 2))
    for value in ["é" * (model.FILE_LIMIT // 2 + 1), "text\x00binary"]:
      with self.assertRaises(ValueError):
        model.text(value)
    for i in range(6):
      self.draft.add_document(f"file{i}.txt", "purpose", "a" * model.FILE_LIMIT)
      self.draft.approve(self.draft.data["documents"][-1], True)
    with self.assertRaises(ValueError):
      self.draft.payload()

  def test_filter_removes_common_secrets(self):
    filtered = model.filtered("token=private\n/home/alex/file\nalex@example.com\nhttps://private.example/path\n#0 main (app + 0xff)")
    self.assertNotIn("private", filtered)
    self.assertNotIn("alex", filtered)
    self.assertIn("0xff", filtered)

  def test_local_redaction_sources_restore_exact_passages(self):
    original = "Préfixe [REDACTED]\nhttps://example.com/home/alex/file\nalex@example.com\n/home/alex/file\ntoken=secret\nFin"
    spans = []
    value = model.filtered(original, spans)
    self.assertEqual(value, model.filtered(original))
    self.assertEqual(len(spans), 4)
    self.assertEqual(spans[0]["original"], "https://example.com/home/alex/file")
    for span in reversed(spans):
      self.assertEqual(value[span["start"]:span["end"]], "[REDACTED]")
      value, _ = model.replace_span(value, [], span["start"], span["end"], span["original"])
    self.assertEqual(value, original)

  def test_failed_send_freezes_payload_and_success_cleans_only_draft(self):
    self.draft.save()
    sibling = self.draft.folder.parent / "source.txt"
    sibling.write_text("keep")
    endpoint = "https://crashes.example.com"
    with patch.object(self.draft, "endpoint", return_value=endpoint), patch.object(self.draft, "request", side_effect=ValueError("offline")):
      with self.assertRaises(ValueError):
        self.draft.send(endpoint)
    self.assertTrue(self.draft.file.exists())
    with self.assertRaises(ValueError):
      self.draft.add_document("new.txt", "purpose", "changed")
    receipt = {"reference": "MCR-0123456789ABCDEF", "url": endpoint + "/admin/reports/" + model.digest(self.draft.data["submission"])}
    with patch.object(self.draft, "endpoint", return_value=endpoint), patch.object(self.draft, "request", return_value=receipt):
      self.draft.send(endpoint)
    self.assertFalse(self.draft.folder.exists())
    self.assertTrue(self.draft.receipt_file.exists())
    self.assertEqual(sibling.read_text(), "keep")

  def test_cleanup_failure_preserves_receipt_and_can_retry_without_upload(self):
    endpoint = "https://crashes.example.com"
    receipt = {"reference": "MCR-0123456789ABCDEF", "url": endpoint + "/admin/reports/" + model.digest(self.draft.data["submission"])}
    with patch.object(self.draft, "endpoint", return_value=endpoint), patch.object(self.draft, "request", return_value=receipt) as upload:
      with patch.object(model.shutil, "rmtree", side_effect=PermissionError("read-only folder")):
        result = self.draft.send(endpoint)
        self.assertIn("cleanupError", result)
        self.assertTrue(self.draft.receipt_file.exists())
        self.assertTrue(self.draft.folder.exists())
        with self.assertRaises(PermissionError):
          self.draft.discard()
      self.draft.discard()
      self.draft.discard()
      self.assertFalse(self.draft.folder.exists())
      self.assertTrue(self.draft.receipt_file.exists())
      upload.assert_called_once()

  def test_enrichment_collisions_preserve_both_versions_unapproved(self):
    for index in (1, 2):
      job = Path(self.temp.name) / f"agent-{index}"
      job.mkdir()
      (job / "result.json").write_text(json.dumps({"analysis": f"analysis {index}", "anonymized": True,
        "documents": [{"name": "thread-stacks.txt", "purpose": "threads", "content": f"version {index}", "anonymized": True}]}))
      self.draft.import_agent(job)
      if index == 1:
        self.draft.approve(self.draft.data["documents"][0], True)
    first, second = self.draft.data["documents"]
    self.assertEqual(first["name"], "thread-stacks.txt")
    self.assertEqual(first["content"], "version 1")
    self.assertEqual(first["decision"], "included")
    self.assertEqual(second["name"], "thread-stacks-2.txt")
    self.assertEqual(second["content"], "version 2")
    self.assertEqual(second["decision"], "pending")
    self.assertEqual(self.draft.data["analysis"]["content"], "analysis 2")
    self.assertEqual(self.draft.data["analysis"]["decision"], "pending")

  def test_import_is_atomic_and_does_not_read_attachment_paths(self):
    job = Path(self.temp.name) / "agent"
    job.mkdir()
    data = {"analysis": "summary", "anonymized": False, "documents": [
      {"name": "good.txt", "purpose": "test", "content": "safe", "original": "local-only-secret", "anonymized": True},
      {"name": "../bad.txt", "purpose": "test", "content": "bad"}]}
    (job / "result.json").write_text(json.dumps(data))
    with self.assertRaises(ValueError):
      self.draft.import_agent(job)
    self.assertEqual(self.draft.data["documents"], [])
    data["documents"].pop()
    (job / "result.json").write_text(json.dumps(data))
    self.draft.import_agent(job)
    self.assertEqual(self.draft.data["analysis"]["anonymization"], "failed")
    self.assertEqual(self.draft.payload()["attachments"], [])
    doc = self.draft.data["documents"][0]
    self.assertEqual(doc["original"], "local-only-secret")
    self.draft.approve(doc, True)
    self.assertNotIn("local-only-secret", json.dumps(self.draft.payload()))


if __name__ == "__main__":
  unittest.main()
