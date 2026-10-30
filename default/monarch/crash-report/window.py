import fcntl
import json
import os
from pathlib import Path
import re
import sys
import threading

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gio, GLib, Gtk
from model import Draft, command, filtered, issue_url, replace_span, text


def label(value, muted=False):
  widget = Gtk.Label(label=value, xalign=0, wrap=True, selectable=True)
  if muted:
    widget.add_css_class("dim-label")
  return widget


def button(title, callback, primary=False):
  widget = Gtk.Button(label=title)
  if primary:
    widget.add_css_class("suggested-action")
  widget.connect("clicked", lambda *_: callback())
  return widget


def box(vertical=True, spacing=8):
  return Gtk.Box(orientation=Gtk.Orientation.VERTICAL if vertical else Gtk.Orientation.HORIZONTAL, spacing=spacing)


class Window(Gtk.ApplicationWindow):
  def __init__(self, app, draft, analyze=False):
    super().__init__(application=app, title="Monarch · Rapport de crash", default_width=900, default_height=660)
    self.draft = draft
    self.analyze = analyze
    self.busy = False
    self.current = None
    self.job = None
    self.receipt = None
    self.palette = None
    self.agent = False
    self.edit_range = None
    self.showing_original = False
    self.extra = None
    self.connect("close-request", self.close_requested)
    self.shell = box()
    for edge in ("top", "bottom", "start", "end"):
      getattr(self.shell, "set_margin_" + edge)(16)
    self.set_child(self.shell)
    self.heading = label("Préparation du rapport…")
    self.heading.add_css_class("title-3")
    self.heading.set_selectable(False)
    self.shell.append(self.heading)
    self.content = box()
    self.content.set_vexpand(True)
    self.shell.append(self.content)
    self.status = label("", True)
    self.shell.append(self.status)
    self.footer = box(False)
    self.shell.append(self.footer)
    self.run(self.load, self.loaded)

  def run(self, task, done):
    if self.busy:
      return
    self.busy = True
    self.content.set_sensitive(False)
    self.footer.set_sensitive(False)
    def work():
      try:
        value = task()
        GLib.idle_add(finish, value, None)
      except Exception as error:
        GLib.idle_add(finish, None, str(error))
    def finish(value, error):
      self.busy = False
      self.content.set_sensitive(True)
      self.footer.set_sensitive(True)
      if error:
        self.status.set_text(error)
      else:
        done(value)
      return False
    threading.Thread(target=work, daemon=True).start()

  def load(self):
    try:
      self.palette = json.loads(command([str(self.draft.root / "bin/monarch-theme-colors")], timeout=3))
    except Exception:
      pass
    if self.draft.receipt_file.exists():
      return json.loads(self.draft.receipt_file.read_text())
    self.draft.load()
    try:
      agent = command([str(self.draft.root / "bin/monarch-default-agent")]).strip()
      import shutil
      self.agent = bool(agent and shutil.which(agent))
    except Exception:
      self.agent = False
    return None

  def loaded(self, receipt):
    self.apply_palette()
    if receipt:
      self.receipt = receipt
      self.sent()
    elif self.draft.data["frozen"]:
      self.review()
    elif self.analyze and self.agent:
      self.deep()
    else:
      self.documents()

  def apply_palette(self):
    colors = self.palette
    keys = ("mSurface", "mOnSurface", "mSurfaceVariant", "mOutline", "mPrimary", "mOnPrimary")
    if not isinstance(colors, dict) or any(not re.fullmatch(r"#[0-9a-fA-F]{6}", colors.get(k, "")) for k in keys):
      return
    self.add_css_class("crash-report")
    css = f"""
      .crash-report {{ background: {colors['mSurface']}; color: {colors['mOnSurface']}; }}
      .crash-report button {{ background: {colors['mSurfaceVariant']}; color: {colors['mOnSurface']}; border-color: {colors['mOutline']}; box-shadow: none; }}
      .crash-report button.suggested-action {{ background: {colors['mPrimary']}; color: {colors['mOnPrimary']}; }}
      .crash-report button:disabled {{ background: {colors['mSurfaceVariant']}; color: {colors['mOnSurface']}; opacity: 0.4; }}
      .crash-report button.flat {{ background: transparent; border-color: transparent; }}
      .crash-report button.document-active {{ background: {colors['mSurfaceVariant']}; border-color: {colors['mPrimary']}; }}
      .crash-report button.document-included {{ border-left: 3px solid #65b889; }}
      .crash-report button.document-excluded {{ border-left: 3px solid #df8080; }}
      .crash-report textview text {{ background: {colors['mSurfaceVariant']}; color: {colors['mOnSurface']}; }}
      .crash-report .review-context textview text {{ background: {colors['mSurfaceVariant']}; }}
      .crash-report .review-heading {{ font-weight: 600; color: {colors['mOnSurface']}; border-bottom: 1px solid {colors['mOutline']}; padding-bottom: 6px; margin-bottom: 3px; }}
    """
    provider = Gtk.CssProvider()
    provider.load_from_string(css)
    Gtk.StyleContext.add_provider_for_display(self.get_display(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    self.css = provider

  def page(self, title):
    self.extra = None
    self.heading.set_text(title)
    self.status.set_text("")
    for parent in (self.content, self.footer):
      while parent.get_first_child():
        parent.remove(parent.get_first_child())

  def safe(self, action):
    try:
      action()
    except Exception as error:
      self.status.set_text(str(error))

  def close_requested(self, *_):
    if self.busy:
      self.status.set_text("Attendez la fin de l’opération avant de fermer.")
      return True
    if self.receipt or not self.draft.data:
      return False
    dialog = Gtk.MessageDialog(transient_for=self, modal=True, text="Fermer le brouillon ?",
      secondary_text="Conservez-le pour reprendre plus tard, ou abandonnez pour supprimer les copies locales. Les sources restent intactes.")
    dialog.add_button("Revenir", 0)
    dialog.add_button("Conserver", 1)
    dialog.add_button("Abandonner", 2)
    def response(widget, choice):
      widget.destroy()
      if choice == 2:
        self.draft.discard()
      if choice in (1, 2):
        self.destroy()
    dialog.connect("response", response)
    dialog.present()
    return True

  def offer(self):
    self.page("Améliorer le rapport avec l’IA ?" if self.agent else "Préparer le rapport")
    crash = self.draft.data["report"]["crash"]
    self.content.append(label(crash["application"] + " · " + crash["signal"] + " · " + crash["date"], True))
    self.content.append(label("Le rapport technique et les pièces proposées restent sur cette machine jusqu’à votre confirmation d’envoi à Monarch."))
    for warning in self.draft.data.get("warnings", []):
      self.content.append(label(warning))
    if self.agent:
      self.content.append(label("L’agent recevra le rapport filtré et les copies filtrées des documents. Il pourra proposer une analyse et de nouvelles pièces."))
      self.content.append(label("Selon sa configuration, ces données sont transmises à son fournisseur. Le mode limité est une consigne à l’agent, pas un confinement système.", True))
      self.footer.append(button("Améliorer avec l’IA", lambda: self.start_agent(False), True))
    self.footer.append(button("Continuer sans IA" if self.agent else "Examiner les documents", self.documents))
    self.footer.append(button("Voir les données proposées", self.inputs))
    if self.draft.data["analysis"]:
      self.footer.append(button("Revoir l’analyse existante", self.analysis_done))
    jobs = sorted(self.draft.folder.glob("agent-*/result.json"))
    if jobs:
      self.footer.append(button("Importer l’analyse disponible", lambda: self.wait_agent(jobs[-1].parent)))

  def inputs(self):
    self.page("Données proposées à l’agent")
    from model import filtered
    value = {"report": self.draft.data["report"], "documents": [
      {"name": d["name"], "content": filtered(d["content"])} for d in self.draft.data["documents"]]}
    self.content.append(self.reader(json.dumps(value, indent=2, ensure_ascii=False)))
    self.footer.append(button("Retour", self.offer))

  def deep(self):
    self.page("Autoriser une investigation approfondie ?")
    self.content.append(label("L’agent pourra examiner le core local et les journaux ciblés pour expliquer le crash et préparer des pièces utiles."))
    self.content.append(label("Ces sources peuvent contenir des informations privées. Des extraits peuvent être transmis au fournisseur de votre agent. L’anonymisation ultérieure ne retire pas ces transmissions."))
    self.content.append(label("Le core brut ne sera jamais joint au rapport Monarch.", True))
    self.footer.append(button("Autoriser l’investigation", lambda: self.start_agent(True), True))
    self.footer.append(button("Rester sur les données filtrées", self.offer))

  def start_agent(self, deep):
    self.status.set_text("Ouverture de l’agent…")
    self.run(lambda: self.draft.agent_job(deep), self.wait_agent)

  def wait_agent(self, job):
    self.job = job
    self.page("Analyse en cours dans l’agent")
    self.content.append(label("Terminez l’analyse dans le terminal, puis importez les résultats. Aucune pièce n’est sélectionnée automatiquement."))
    self.footer.append(button("Importer les résultats", self.import_agent, True))
    self.footer.append(button("Continuer sans les résultats", self.documents))

  def import_agent(self):
    self.run(lambda: self.draft.import_agent(self.job), lambda _: self.analysis_done())

  def analysis_done(self):
    self.page("Analyse disponible")
    self.content.append(self.reader(self.draft.data["analysis"]["content"]))
    self.content.append(label("L’analyse et les pièces proposées doivent encore être relues et sélectionnées.", True))
    self.footer.append(button("Examiner les documents", self.documents, True))
    self.footer.append(button("Approfondir l’investigation…", self.deep))

  def reader(self, value):
    view = Gtk.TextView(editable=False, cursor_visible=True, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR)
    view.get_buffer().set_text(value)
    scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True, min_content_height=140)
    scroll.set_child(view)
    return scroll

  def documents(self):
    self.set_default_size(900, 660)
    self.page("1 · Choisir les documents à joindre")
    crash = self.draft.data["report"]["crash"]
    self.content.append(label(crash["application"] + " · " + crash["signal"] + " · " + crash["date"], True))
    self.content.append(label("Relisez chaque document, masquez les passages privés, puis choisissez de le joindre ou de l’ignorer. Rien n’est envoyé à cette étape."))
    for warning in self.draft.data.get("warnings", []):
      self.content.append(label(warning, True))
    self.items = list(self.draft.data["documents"])
    if self.draft.data["analysis"]:
      self.items.append(self.draft.data["analysis"])
    self.paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, position=230, vexpand=True)
    self.content.append(self.paned)
    self.list = box(spacing=4)
    side = Gtk.ScrolledWindow(min_content_width=190)
    side.set_child(self.list)
    self.paned.set_start_child(side)
    right = box()
    right.set_margin_start(12)
    self.paned.set_end_child(right)
    toolbar = box(False, 6)
    self.redact_button = button("Anonymiser", lambda: self.safe(self.redact))
    toolbar.append(self.redact_button)
    self.restore_button = button("Déanonymiser", lambda: self.safe(self.restore_redaction))
    toolbar.append(self.restore_button)
    self.original_button = Gtk.ToggleButton(icon_name="view-reveal-symbolic")
    self.original_button.set_tooltip_text("Afficher l’original local (non transmis)")
    self.original_button.connect("toggled", lambda *_: self.original())
    toolbar.append(self.original_button)
    right.append(toolbar)
    self.doc_title = label("")
    right.append(self.doc_title)
    self.doc_purpose = label("", True)
    right.append(self.doc_purpose)
    self.editor = Gtk.TextView(monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=8, bottom_margin=8, left_margin=8, right_margin=8)
    self.buffer = self.editor.get_buffer()
    self.tag = self.buffer.create_tag("redacted", background="#47345f", foreground="#e0c9ff")
    self.changing = False
    self.buffer.connect("changed", self.on_edit)
    self.buffer.connect("insert-text", lambda _, location, value, length: self.track_edit(location.get_offset(), location.get_offset(), value))
    self.buffer.connect("delete-range", lambda _, start, end: self.track_edit(start.get_offset(), end.get_offset(), ""))
    self.buffer.connect("mark-set", lambda *_: self.update_editor_actions() if not self.changing else None)
    scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True)
    scroll.set_child(self.editor)
    right.append(scroll)
    self.override = Gtk.CheckButton(label="Inclure malgré l’échec de l’anonymisation")
    self.override.set_visible(False)
    right.append(self.override)
    decisions = box(False)
    self.include_button = button("Joindre ce document", lambda: self.toggle(self.current, True), True)
    decisions.append(self.include_button)
    decisions.append(button("Ne pas joindre", lambda: self.toggle(self.current, False)))
    right.append(decisions)
    right.append(label("Passages violets : masqués. Seul [REDACTED] sera transmis. Le filtrage peut manquer des informations sensibles.", True))
    if self.agent:
      self.footer.append(button("Analyse IA…", self.offer))
    self.progress = label("", True)
    self.progress.set_hexpand(True)
    self.footer.append(self.progress)
    self.next_button = button("Vérifier le rapport", lambda: self.safe(self.next_review), True)
    self.footer.append(self.next_button)
    self.refresh_list()
    if self.items:
      self.select_document(self.items[0])
    else:
      self.doc_title.set_text("Aucune pièce proposée")
      self.editor.set_sensitive(False)
      decisions.set_sensitive(False)

  def refresh_list(self):
    while self.list.get_first_child():
      self.list.remove(self.list.get_first_child())
    for doc in self.items:
      title = doc.get("name", "Analyse IA")
      state = {"pending": "À examiner", "included": "Inclus", "excluded": "Exclu"}[doc["decision"]]
      item = button(title + "\n" + state, lambda d=doc: self.select_document(d))
      item.add_css_class("flat")
      item.add_css_class("document-" + doc["decision"])
      item.get_child().set_xalign(0)
      if self.current is doc:
        item.add_css_class("document-active")
      item.set_hexpand(True)
      self.list.append(item)
    pending = sum(doc["decision"] == "pending" for doc in self.items)
    self.progress.set_text(f"{len(self.items) - pending}/{len(self.items)} documents examinés")
    self.next_button.set_sensitive(pending == 0)

  def select_document(self, doc):
    self.current = doc
    if "redactions" not in doc:
      spans = []
      value = filtered(doc["original"], spans)
      doc["redactions"] = spans if value == doc["content"] else []
    self.showing_original = False
    self.original_button.set_active(False)
    self.changing = True
    self.buffer.set_text(doc["content"])
    self.changing = False
    self.highlight()
    self.update_editor_actions()
    self.doc_title.set_text(doc.get("name", "Analyse IA"))
    size = len(doc["content"].encode()) / 1024
    self.doc_purpose.set_text(doc.get("purpose", "Observations, hypothèses et limites proposées par l’agent.") + f" · {size:.1f} Kio")
    self.override.set_visible(doc["anonymization"] == "failed")
    self.override.set_active(False)
    self.status.set_text("Choisissez « Joindre ce document » ou « Ne pas joindre » après lecture.")
    self.refresh_list()

  def toggle(self, doc, include):
    if doc is None:
      return
    if include and self.showing_original:
      self.status.set_text("Revenez à la version à transmettre avant de la valider.")
      return
    if include and self.current is not doc:
      self.select_document(doc)
      self.refresh_list()
      self.status.set_text("Examinez ce document puis choisissez de le joindre.")
      return
    self.safe(lambda: self.draft.approve(doc, include, self.override.get_active()))
    self.refresh_list()
    if doc["decision"] != "pending":
      self.status.set_text("Document joint." if include else "Document non joint.")

  def highlight(self):
    start, end = self.buffer.get_bounds()
    self.buffer.remove_tag(self.tag, start, end)
    value = self.buffer.get_text(start, end, True)
    offset = 0
    while (offset := value.find("[REDACTED]", offset)) >= 0:
      self.buffer.apply_tag(self.tag, self.buffer.get_iter_at_offset(offset), self.buffer.get_iter_at_offset(offset + 10))
      offset += 10

  def track_edit(self, start, end, value):
    if not self.changing:
      self.edit_range = (start, end, value)

  def on_edit(self, *_):
    if self.changing or self.current is None or self.showing_original:
      return
    value = self.buffer.get_text(*self.buffer.get_bounds(), True)
    try:
      spans = []
      if self.edit_range:
        expected, spans = replace_span(self.current["content"], self.current.get("redactions", []), *self.edit_range)
        if expected != value:
          spans = []
      self.draft.edit(self.current, value)
      self.current["redactions"] = spans
      self.draft.save()
      self.status.set_text("Document modifié : sa validation doit être renouvelée.")
    except Exception as error:
      self.status.set_text(str(error))
      self.changing = True
      self.buffer.set_text(self.current["content"])
      self.changing = False
    self.edit_range = None
    self.highlight()
    self.refresh_list()
    self.update_editor_actions()

  def redact(self):
    if self.showing_original:
      return
    bounds = self.buffer.get_selection_bounds()
    if not bounds:
      raise ValueError("Sélectionnez un passage dans le document.")
    start, end = bounds
    a, b = start.get_offset(), end.get_offset()
    if any(a < span["end"] and b > span["start"] for span in self.current.get("redactions", [])):
      raise ValueError("Sélectionnez un passage qui n’est pas déjà anonymisé.")
    original = self.current["content"][a:b]
    value, spans = replace_span(self.current["content"], self.current.get("redactions", []), a, b, "[REDACTED]", original)
    self.apply_edit(value, spans, a)

  def selected_redaction(self):
    if self.current is None or self.showing_original:
      return None
    bounds = self.buffer.get_selection_bounds()
    if bounds:
      a, b = (position.get_offset() for position in bounds)
    else:
      a = b = self.buffer.get_iter_at_mark(self.buffer.get_insert()).get_offset()
    matches = [span for span in self.current.get("redactions", [])
      if self.current["content"][span["start"]:span["end"]] == "[REDACTED]"
      and ((a == b and span["start"] <= a < span["end"])
        or (a < b and span["start"] <= a and b <= span["end"]))]
    return matches[0] if len(matches) == 1 else None

  def restore_redaction(self):
    span = self.selected_redaction()
    if span:
      value, spans = replace_span(self.current["content"], self.current["redactions"], span["start"], span["end"], span["original"])
      self.apply_edit(value, spans, span["start"])

  def apply_edit(self, value, spans, cursor):
    self.draft.edit(self.current, value)
    self.current["redactions"] = spans
    self.draft.save()
    self.changing = True
    self.buffer.set_text(value)
    self.buffer.place_cursor(self.buffer.get_iter_at_offset(cursor))
    self.changing = False
    self.highlight()
    self.refresh_list()
    self.update_editor_actions()
    self.status.set_text("Document modifié : vérifiez puis validez à nouveau cette version.")

  def update_editor_actions(self):
    self.editor.set_editable(not self.showing_original)
    self.redact_button.set_sensitive(not self.showing_original and bool(self.buffer.get_selection_bounds()))
    self.include_button.set_sensitive(not self.showing_original)
    self.restore_button.set_sensitive(self.selected_redaction() is not None)
    self.restore_button.set_tooltip_text("Rétablir le passage original sous le curseur ou sélectionné."
      if self.selected_redaction() else "Placez le curseur dans un marqueur dont l’original est disponible localement.")

  def original(self):
    if not self.current:
      return
    self.showing_original = self.original_button.get_active()
    self.changing = True
    self.buffer.set_text(self.current["original" if self.showing_original else "content"])
    self.changing = False
    self.highlight()
    self.update_editor_actions()
    title = self.current.get("name", "Analyse IA")
    self.doc_title.set_text(title + (" · Original local — non transmis" if self.showing_original else ""))
    self.original_button.set_tooltip_text("Revenir à la version à transmettre" if self.showing_original else "Afficher l’original local (non transmis)")
    self.status.set_text("Original en lecture seule. Copiez un passage puis revenez à la version à transmettre pour le rétablir."
      if self.showing_original else "Version à transmettre : les passages anonymisés restent masqués.")

  def next_review(self):
    for doc in self.items:
      if doc["decision"] == "pending":
        self.select_document(doc)
        raise ValueError("Choisissez de joindre ou non chaque document avant de vérifier le rapport.")
    self.review()

  def review(self):
    self.set_default_size(900, 480)
    self.page("2 · Vérifier le rapport")
    frozen = self.draft.data["frozen"]
    try:
      payload = frozen or self.draft.payload()
    except Exception as error:
      self.status.set_text(str(error))
      self.footer.append(button("Revenir aux documents", self.documents))
      return
    crash = payload["report"]["crash"]
    self.content.append(label(crash["application"] + " · " + crash["signal"], True))
    sections = box(spacing=16)
    sections.set_valign(Gtk.Align.START)
    scroll = Gtk.ScrolledWindow(vexpand=True)
    scroll.set_child(sections)
    columns = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL, position=430, vexpand=True)
    columns.set_start_child(scroll)
    columns.set_resize_start_child(True)
    columns.set_resize_end_child(True)
    right = box()
    right.set_margin_start(24)
    columns.set_end_child(right)
    self.content.append(columns)
    def section(title, detail, parent=sections):
      group = box(spacing=4)
      group.set_vexpand(False)
      heading = label(title)
      heading.add_css_class("review-heading")
      heading.set_selectable(False)
      group.append(heading)
      if detail:
        group.append(label(detail, True))
      parent.append(group)
      return group

    def preview(parent, title, value):
      action = button(title, lambda: self.preview_document(title, value))
      action.add_css_class("flat")
      action.set_tooltip_text("Ouvrir le document en lecture seule")
      row = box(False, 8)
      row.append(Gtk.Image.new_from_icon_name("document-open-symbolic"))
      text_label = label(title)
      text_label.set_selectable(False)
      text_label.set_hexpand(True)
      row.append(text_label)
      action.set_child(row)
      parent.append(action)

    technical = section("Rapport technique", "Inclus · application, système et pile du crash")
    preview(technical, "Consulter le rapport technique", json.dumps(payload["report"], indent=2, ensure_ascii=False))
    analysis = payload["analysis"]
    ai = section("Analyse IA", "Incluse" if analysis else "Non jointe")
    if analysis:
      if analysis["anonymization"] == "failed":
        ai.append(label("Anonymisation échouée — vous avez autorisé le partage de cette version."))
      preview(ai, "Consulter l’analyse IA", analysis["content"])
    attachments = payload["attachments"]
    size = sum(len(document["content"].encode()) for document in attachments)
    files = section("Pièces jointes", f"{len(attachments)} fichier{'s' if len(attachments) != 1 else ''} · {size / 1024:.1f} Kio" if attachments else "Aucune")
    for document in attachments:
      preview(files, document["name"] + f" · {len(document['content'].encode()) / 1024:.1f} Kio",
        document["purpose"] + ("\nAnonymisation échouée — partage autorisé explicitement." if document["anonymization"] == "failed" else "")
        + "\n\n" + document["content"])
    context = section("Ajouter du contexte", "Facultatif · étapes pour reproduire le crash", right)
    context.add_css_class("review-context")
    extra = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, editable=not bool(frozen),
      top_margin=10, bottom_margin=10, left_margin=10, right_margin=10)
    extra.get_buffer().set_text(payload["additional"])
    extra_scroll = Gtk.ScrolledWindow(min_content_height=180)
    extra_scroll.set_child(extra)
    context.append(extra_scroll)
    self.extra = extra.get_buffer()
    toolbar = box(False)
    counter = label("", True)
    counter.set_hexpand(True)
    toolbar.append(counter)
    context.append(toolbar)
    def count_extra(buffer):
      size = len(buffer.get_text(*buffer.get_bounds(), True).encode())
      counter.set_text(f"{size / 1024:.1f} / 64 Kio" if size else "Ajoutez du contexte si vous le souhaitez.")
    count_extra(self.extra)
    def save_extra(buffer):
      try:
        value = text(buffer.get_text(*buffer.get_bounds(), True), 65536)
        self.draft.data["additional"] = value
        self.draft.save()
      except Exception as error:
        self.status.set_text(str(error))
    if not frozen:
      self.extra.connect("changed", save_extra)
      self.extra.connect("changed", count_extra)
      anonymize = button("Anonymiser la sélection", lambda: self.safe(self.redact_extra))
      anonymize.set_sensitive(False)
      self.extra.connect("mark-set", lambda buffer, *_: anonymize.set_sensitive(bool(buffer.get_selection_bounds())))
      toolbar.append(anonymize)
    else:
      context.append(label("Envoi déjà tenté : cette version est figée pour permettre une nouvelle tentative sans doublon.", True))
    self.content.append(label("Privé · équipe Monarch · 90 jours maximum. Core et originaux exclus.", True))
    if not frozen:
      self.footer.append(button("Modifier les documents", self.documents))
    spacer = box()
    spacer.set_hexpand(True)
    self.footer.append(spacer)
    next_step = button("Continuer", self.confirm, True)
    next_step.set_tooltip_text("Vérifier la destination avant de confirmer l’envoi.")
    self.footer.append(next_step)

  def preview_document(self, title, value):
    if getattr(self, "preview_window", None):
      self.preview_window.destroy()
    dialog = Gtk.Window(application=self.get_application(), transient_for=self, modal=True,
      destroy_with_parent=True, title=title, default_width=820, default_height=540)
    self.preview_window = dialog
    dialog.add_css_class("crash-report")
    content = box(spacing=12)
    for edge in ("top", "bottom", "start", "end"):
      getattr(content, "set_margin_" + edge)(16)
    heading = label(title)
    heading.add_css_class("title-3")
    heading.set_selectable(False)
    content.append(heading)
    content.append(label("Lecture seule · version qui sera transmise", True))
    content.append(self.reader(value))
    close = button("Fermer", dialog.destroy)
    close.set_halign(Gtk.Align.END)
    content.append(close)
    dialog.set_child(content)
    keys = Gtk.EventControllerKey()
    def on_key(_, key, code, state):
      if key == Gdk.KEY_Escape:
        dialog.destroy()
        return True
      return False
    keys.connect("key-pressed", on_key)
    dialog.add_controller(keys)
    dialog.present()

  def redact_extra(self):
    selection = self.extra.get_selection_bounds()
    if not selection:
      raise ValueError("Sélectionnez un passage dans les informations additionnelles.")
    start, end = selection
    self.extra.delete(start, end)
    self.extra.insert(start, "[REDACTED]")

  def confirm(self):
    try:
      if self.draft.data["frozen"] is None:
        self.draft.data["additional"] = text(self.extra.get_text(*self.extra.get_bounds(), True), 65536)
        self.draft.save()
        self.draft.payload()
    except Exception as error:
      self.status.set_text(str(error))
      return
    self.run(self.draft.service, self.destination)

  def destination(self, service):
    self.page("3 · Confirmer l’envoi")
    endpoint = self.draft.endpoint()
    self.content.append(label("Destination : " + endpoint))
    self.content.append(label("Conservation annoncée : " + str(service["retentionDays"]) + " jours."))
    self.content.append(label("Vous confirmez l’envoi des versions que vous venez de vérifier. Après réception, les copies locales de travail seront supprimées."))
    self.footer.append(button("Revenir au rapport", self.review))
    self.footer.append(button("Confirmer l’envoi", lambda: self.run(lambda: self.draft.send(endpoint), self.sent), True))

  def sent(self, receipt=None):
    if receipt:
      self.receipt = receipt
    self.page("Rapport envoyé")
    self.content.append(label(self.receipt["reference"]))
    self.content.append(label(self.receipt["url"], True))
    self.content.append(label("Accès réservé à l’équipe Monarch. Les copies locales du brouillon ont été supprimées."))
    self.content.append(label("Vous pouvez ouvrir un brouillon d’issue publique sur monarch-os/monarch. Il contiendra le lien privé, sans recopier l’analyse ni les pièces."))
    self.footer.append(button("Créer une issue GitHub", lambda: Gio.AppInfo.launch_default_for_uri(issue_url(self.receipt), None), True))
    self.footer.append(button("Copier le lien", lambda: Gdk.Display.get_default().get_clipboard().set(self.receipt["url"])))
    self.footer.append(button("Terminer", self.destroy))


def main():
  if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--analyze"):
    raise SystemExit("Usage: monarch crash report <id> [--analyze]")
  os.umask(0o077)
  root = os.environ.get("MONARCH_PATH", "/usr/share/monarch")
  draft = Draft(root, sys.argv[1])
  lockpath = draft.folder.parent / (draft.folder.name + ".lock")
  lockpath.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
  with lockpath.open("w") as lock:
    try:
      fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
      raise SystemExit("Ce rapport est déjà ouvert dans une autre fenêtre.")
    app = Gtk.Application(application_id="org.monarch.CrashReport", flags=Gio.ApplicationFlags.NON_UNIQUE)
    app.connect("activate", lambda application: Window(application, draft, len(sys.argv) == 3).present())
    app.run([])


if __name__ == "__main__":
  main()
