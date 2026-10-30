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
      self.assertFalse(window.next_button.get_sensitive())
      doc = draft.data["documents"][0]
      self.assertFalse(window.restore_button.get_sensitive())
      content = doc["content"]
      window.original_button.set_active(True)
      self.assertFalse(window.editor.get_editable())
      self.assertFalse(window.include_button.get_sensitive())
      self.assertEqual(doc["content"], content)
      self.assertEqual(window.buffer.get_text(*window.buffer.get_bounds(), True), doc["original"])
      window.original_button.set_active(False)
      self.assertEqual(window.buffer.get_text(*window.buffer.get_bounds(), True), content)
      window.toggle(doc, True)
      self.assertEqual(doc["decision"], "included")
      window.buffer.select_range(window.buffer.get_iter_at_offset(0), window.buffer.get_iter_at_offset(8))
      window.redact()
      self.assertTrue(doc["content"].startswith("[REDACTED]"))
      self.assertEqual(doc["decision"], "pending")
      self.assertTrue(doc["original"].startswith("Thread 1"))
      window.select_document(draft.data["documents"][1])
      window.select_document(doc)
      window.buffer.place_cursor(window.buffer.get_iter_at_offset(3))
      self.assertTrue(window.restore_button.get_sensitive())
      window.restore_redaction()
      self.assertFalse(window.restore_button.get_sensitive())
      self.assertTrue(doc["content"].startswith("Thread 1"))
      window.buffer.insert(window.buffer.get_start_iter(), "Préfixe — ")
      offset = doc["content"].index("[REDACTED]")
      window.buffer.select_range(window.buffer.get_iter_at_offset(offset), window.buffer.get_iter_at_offset(offset + 10))
      self.assertTrue(window.restore_button.get_sensitive())
      window.toggle(doc, True)
      window.restore_redaction()
      self.assertIn("/home/alex/apps/module.so", doc["content"])
      self.assertEqual(doc["decision"], "pending")
      self.assertFalse(window.next_button.get_sensitive())
      window.buffer.insert(window.buffer.get_end_iter(), " [REDACTED]")
      window.buffer.place_cursor(window.buffer.get_iter_at_offset(len(doc["content"]) - 4))
      self.assertFalse(window.restore_button.get_sensitive())
      self.assertNotIn("redactions", json.dumps(draft.payload()))
      window.toggle(doc, True)
      window.select_document(draft.data["documents"][1])
      self.assertNotIn("redactions", json.dumps(draft.payload()))
      window.toggle(draft.data["documents"][1], False)
      self.assertTrue(window.next_button.get_sensitive())
      window.buffer.set_text("Revised journal")
      self.assertFalse(window.next_button.get_sensitive())
      window.toggle(draft.data["documents"][1], False)
      self.assertTrue(window.next_button.get_sensitive())
      window.next_review()
      def descendants(widget):
        yield widget
        child = widget.get_first_child()
        while child:
          yield from descendants(child)
          child = child.get_next_sibling()
      def settle():
        loop = GLib.MainLoop()
        GLib.timeout_add(150, lambda: (loop.quit(), False)[1])
        loop.run()
      window.present()
      settle()
      preview = next(widget for widget in descendants(window.content) if isinstance(widget, Gtk.Button))
      section = preview.get_parent()
      compact_height = section.get_height()
      for _ in range(2):
        preview.emit("clicked")
        settle()
        dialog = window.preview_window
        self.assertTrue(dialog.get_modal())
        self.assertIs(dialog.get_transient_for(), window)
        reader = next(widget for widget in descendants(dialog) if isinstance(widget, Gtk.TextView))
        self.assertFalse(reader.get_editable())
        self.assertEqual(json.loads(reader.get_buffer().get_text(*reader.get_buffer().get_bounds(), True)), draft.data["report"])
        dialog.destroy()
        settle()
        self.assertLessEqual(section.get_height(), compact_height + 2,
          "Document preview must not change the report summary layout")
      window.extra.set_text("Private context")
      window.extra.select_range(*window.extra.get_bounds())
      window.redact_extra()
      self.assertEqual(draft.data["additional"], "[REDACTED]")
      self.assertEqual(len(draft.payload()["attachments"]), 1)
      old_context = window.extra
      with patch.object(sys, "excepthook") as errors:
        window.documents()
        old_context.place_cursor(old_context.get_start_iter())
        old_context.select_range(*old_context.get_bounds())
      errors.assert_not_called()
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
