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
from model import Draft, command, issue_url, text


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
    self.history = []
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
      self.offer()

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
      .crash-report button.flat {{ background: transparent; border-color: transparent; }}
      .crash-report button.document-active {{ background: {colors['mSurfaceVariant']}; border-color: {colors['mPrimary']}; }}
      .crash-report textview text {{ background: {colors['mSurfaceVariant']}; color: {colors['mOnSurface']}; }}
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
    self.page("Documents du rapport")
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
    toolbar.append(button("Masquer la sélection", lambda: self.safe(self.redact)))
    toolbar.append(button("Annuler", lambda: self.safe(self.undo)))
    toolbar.append(button("Original local", self.original))
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
    scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True)
    scroll.set_child(self.editor)
    right.append(scroll)
    self.override = Gtk.CheckButton(label="Inclure malgré l’échec de l’anonymisation")
    self.override.set_visible(False)
    right.append(self.override)
    right.append(label("Passages violets : masqués. Seul [REDACTED] sera transmis. Le filtrage peut manquer des informations sensibles.", True))
    self.footer.append(button("Exclure le reste", self.exclude_rest))
    self.footer.append(button("Continuer", lambda: self.safe(self.next_review), True))
    self.refresh_list()
    if self.items:
      self.select_document(self.items[0])
    else:
      self.doc_title.set_text("Aucune pièce proposée")
      self.editor.set_sensitive(False)

  def refresh_list(self):
    while self.list.get_first_child():
      self.list.remove(self.list.get_first_child())
    for doc in self.items:
      row = box(False, 4)
      check = Gtk.CheckButton()
      check.set_tooltip_text("Inclure la version affichée")
      check.set_active(doc["decision"] == "included")
      check.connect("toggled", lambda widget, d=doc: self.toggle(d, widget.get_active()))
      row.append(check)
      title = doc.get("name", "Analyse IA")
      state = {"pending": "À valider", "included": "Inclus", "excluded": "Exclu"}[doc["decision"]]
      item = button(title + "\n" + state, lambda d=doc: self.select_document(d))
      item.add_css_class("flat")
      item.get_child().set_xalign(0)
      if self.current is doc:
        item.add_css_class("document-active")
      item.set_hexpand(True)
      row.append(item)
      self.list.append(row)

  def select_document(self, doc):
    self.current = doc
    self.history = []
    self.changing = True
    self.buffer.set_text(doc["content"])
    self.changing = False
    self.highlight()
    self.doc_title.set_text(doc.get("name", "Analyse IA"))
    size = len(doc["content"].encode()) / 1024
    self.doc_purpose.set_text(doc.get("purpose", "Observations, hypothèses et limites proposées par l’agent.") + f" · {size:.1f} Kio")
    self.override.set_visible(doc["anonymization"] == "failed")
    self.override.set_active(False)
    self.status.set_text("Cochez ce document pour valider la version affichée.")
    self.refresh_list()

  def toggle(self, doc, include):
    if include and self.current is not doc:
      self.select_document(doc)
      self.refresh_list()
      self.status.set_text("Examinez ce document puis cochez-le pour valider cette version.")
      return
    self.safe(lambda: self.draft.approve(doc, include, self.override.get_active()))
    self.refresh_list()

  def highlight(self):
    start, end = self.buffer.get_bounds()
    self.buffer.remove_tag(self.tag, start, end)
    value = self.buffer.get_text(start, end, True)
    offset = 0
    while (offset := value.find("[REDACTED]", offset)) >= 0:
      self.buffer.apply_tag(self.tag, self.buffer.get_iter_at_offset(offset), self.buffer.get_iter_at_offset(offset + 10))
      offset += 10

  def on_edit(self, *_):
    if self.changing or self.current is None:
      return
    value = self.buffer.get_text(*self.buffer.get_bounds(), True)
    try:
      self.draft.edit(self.current, value)
      self.status.set_text("Document modifié : sa validation doit être renouvelée.")
    except Exception as error:
      self.status.set_text(str(error))
      self.changing = True
      self.buffer.set_text(self.current["content"])
      self.changing = False
    self.highlight()
    self.refresh_list()

  def redact(self):
    bounds = self.buffer.get_selection_bounds()
    if not bounds:
      raise ValueError("Sélectionnez un passage dans le document.")
    self.history.append(self.current["content"])
    self.changing = True
    start, end = bounds
    self.buffer.delete(start, end)
    self.buffer.insert(start, "[REDACTED]")
    self.changing = False
    self.on_edit()

  def undo(self):
    if self.history:
      self.buffer.set_text(self.history.pop())

  def original(self):
    if not self.current:
      return
    dialog = Gtk.Window(transient_for=self, modal=True, title="Original local — non transmis", default_width=680, default_height=400)
    dialog.set_child(self.reader(self.current["original"]))
    dialog.present()

  def exclude_rest(self):
    def action():
      for doc in self.items:
        if doc["decision"] == "pending":
          self.draft.approve(doc, False)
      self.review()
    self.safe(action)

  def next_review(self):
    for doc in self.items:
      if doc["decision"] == "pending":
        self.select_document(doc)
        raise ValueError("Validez ce document ou utilisez « Exclure le reste ».")
    self.review()

  def review(self):
    self.page("Vérifier avant d’envoyer")
    self.content.append(label("Rapport et pièces réservés à l’équipe Monarch via Cloudflare. Conservation maximale : 90 jours.", True))
    frozen = self.draft.data["frozen"]
    try:
      payload = frozen or self.draft.payload()
    except Exception as error:
      self.status.set_text(str(error))
      self.footer.append(button("Revenir aux documents", self.documents))
      return
    sections = box()
    scroll = Gtk.ScrolledWindow(vexpand=True)
    scroll.set_child(sections)
    self.content.append(scroll)
    values = [("Rapport de base", json.dumps(payload["report"], indent=2, ensure_ascii=False)),
      ("Analyse IA", payload["analysis"]["content"] if payload["analysis"] else "Non transmise."),
      ("Fichiers à transmettre", "\n\n".join(d["name"] + "\n" + d["purpose"]
        + ("\nAnonymisation échouée — partage autorisé explicitement" if d["anonymization"] == "failed" else "")
        + "\n" + d["content"] for d in payload["attachments"]) or "Aucun fichier sélectionné.")]
    if payload["analysis"] and payload["analysis"]["anonymization"] == "failed":
      sections.append(label("Analyse IA : partage autorisé malgré l’échec de l’anonymisation.", True))
    for title, value in values:
      expander = Gtk.Expander(label=title)
      expander.set_child(self.reader(value))
      sections.append(expander)
    sections.append(label("Informations additionnelles"))
    extra = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, editable=not bool(frozen))
    extra.get_buffer().set_text(payload["additional"])
    extra_scroll = Gtk.ScrolledWindow(min_content_height=100)
    extra_scroll.set_child(extra)
    sections.append(extra_scroll)
    self.extra = extra.get_buffer()
    def save_extra(buffer):
      try:
        value = text(buffer.get_text(*buffer.get_bounds(), True), 65536)
        self.draft.data["additional"] = value
        self.draft.save()
      except Exception as error:
        self.status.set_text(str(error))
    if not frozen:
      self.extra.connect("changed", save_extra)
      sections.append(button("Masquer la sélection", lambda: self.safe(self.redact_extra)))
    self.content.append(label("Relisez le contenu : le filtrage ne garantit pas l’absence d’informations sensibles. Les originaux locaux et le core brut sont exclus.", True))
    if not frozen:
      self.footer.append(button("Documents", self.documents))
    self.footer.append(button("Vérifier la destination", self.confirm, True))

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
    self.page("Confirmer l’envoi à Monarch")
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
