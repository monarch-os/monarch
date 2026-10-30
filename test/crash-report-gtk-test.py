import os
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "default/monarch/crash-report"))
from window import Window, Gtk, Gio, GLib
from model import Draft


class Reviewer(unittest.TestCase):
  def test_redaction_invalidates_approval_and_never_changes_original(self):
    with tempfile.TemporaryDirectory() as state:
      draft = Draft(ROOT, "a" * 32 + ":42:123456789", state)
      draft.data = {"report": {"crash": {"application": "msedge", "signal": "SIGILL", "date": "2026-10-21 17:14 UTC"}},
        "documents": [], "analysis": None, "additional": "", "frozen": None, "endpoint": None, "submission": "test"}
      draft.add_document("pile-threads.txt", "Localiser le crash et examiner les threads.", "Thread 1 — msedge\n#0 n/a (n/a + 0x0)\nModule : /home/alex/apps/module.so\nArchitecture : x86_64")
      draft.add_document("journal-cible.txt", "Événements proches du crash.", "SIGILL\nContexte : projet-client")
      draft.save()
      app = Gtk.Application(application_id="org.monarch.CrashReport.Test", flags=Gio.ApplicationFlags.NON_UNIQUE)
      app.register(None)
      with patch.object(Window, "run"):
        window = Window(app, draft)
      window.palette = json.loads((ROOT / "config/noctalia/palettes/Monarch.json").read_text())["dark"]
      window.apply_palette()
      window.documents()
      doc = draft.data["documents"][0]
      window.toggle(doc, True)
      self.assertEqual(doc["decision"], "included")
      window.buffer.select_range(window.buffer.get_iter_at_offset(0), window.buffer.get_iter_at_offset(8))
      window.redact()
      self.assertTrue(doc["content"].startswith("[REDACTED]"))
      self.assertEqual(doc["decision"], "pending")
      self.assertTrue(doc["original"].startswith("Thread 1"))
      window.undo()
      self.assertTrue(doc["content"].startswith("Thread 1"))
      window.toggle(doc, True)
      window.select_document(draft.data["documents"][1])
      window.toggle(draft.data["documents"][1], False)
      window.next_review()
      window.extra.set_text("Private context")
      window.extra.select_range(*window.extra.get_bounds())
      window.redact_extra()
      self.assertEqual(draft.data["additional"], "[REDACTED]")
      self.assertEqual(len(draft.payload()["attachments"]), 1)
      window.documents()
      if os.environ.get("MONARCH_CRASH_TEST_SCREENSHOT"):
        window.present()
        loop = GLib.MainLoop()
        def capture():
          import subprocess
          result = subprocess.run([str(ROOT / "bin/monarch-capture-screenshot"), "fullscreen", "save"], capture_output=True, text=True)
          print(result.stdout, result.stderr, flush=True)
          from gi.repository import Gdk
          paintable = Gtk.WidgetPaintable.new(window)
          snapshot = Gtk.Snapshot.new()
          paintable.snapshot(snapshot, window.get_width(), window.get_height())
          node = snapshot.to_node()
          texture = window.get_renderer().render_texture(node, None)
          texture.save_to_png("/tmp/opencode/crash-reviewer-gtk.png")
          loop.quit()
          return False
        GLib.timeout_add(2000, capture)
        loop.run()
      window.destroy()


if __name__ == "__main__":
  unittest.main()
