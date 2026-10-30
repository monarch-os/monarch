import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import subprocess
import tempfile
import uuid
from urllib.parse import urlencode

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "i18n"))
from i18n import Translator

translator = Translator()
tr = translator.text

FILE_LIMIT = 1024 * 1024
TOTAL_LIMIT = 5 * FILE_LIMIT
TEXT_LIMIT = 65536
ID_PATTERN = r"[a-f0-9]{32}:[0-9]{1,10}:[0-9]{1,20}"


def text(value, maximum=FILE_LIMIT):
  if not isinstance(value, str) or len(value.encode("utf-8")) > maximum:
    raise ValueError(tr("crashReport.textTooLarge"))
  if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", value):
    raise ValueError(tr("crashReport.textOnly"))
  return value


def replace_span(value, spans, start, end, replacement, original=None):
  delta = len(replacement) - (end - start)
  kept = []
  for span in spans:
    if span["end"] <= start:
      kept.append(dict(span))
    elif span["start"] >= end:
      kept.append(dict(span, start=span["start"] + delta, end=span["end"] + delta))
  if original is not None:
    kept.append({"start": start, "end": start + len(replacement), "original": original})
  return value[:start] + replacement + value[end:], sorted(kept, key=lambda span: span["start"])


def filtered(value, redactions=None):
  value = text(value)
  spans = []
  patterns = [
    r"-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----",
    r"(?i)\b(?:authorization|cookie|password|passwd|secret|token|api[_-]?key)\s*[:=]\s*[^\n]+",
    r"/(?:home|Users|tmp|root|run/user)/[^\s\"'<>]+",
    r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
    r"https?://[^\s\"'<>]+",
    r"\b(?:\d{1,3}\.){3}\d{1,3}\b",
  ]
  for pattern in patterns:
    if redactions is None:
      value = re.sub(pattern, "[REDACTED]", value)
      continue
    pieces, updated = [], []
    cursor, delta, index = 0, 0, 0
    for match in re.finditer(pattern, value):
      pieces.extend((value[cursor:match.start()], "[REDACTED]"))
      while index < len(spans) and spans[index]["end"] <= match.start():
        span = spans[index]
        updated.append(dict(span, start=span["start"] + delta, end=span["end"] + delta))
        index += 1
      nested = []
      while index < len(spans) and spans[index]["start"] < match.end():
        span = spans[index]
        if match.start() <= span["start"] and span["end"] <= match.end():
          nested.append(span)
        index += 1
      original = match.group()
      for span in reversed(nested):
        a, b = span["start"] - match.start(), span["end"] - match.start()
        original = original[:a] + span["original"] + original[b:]
      start = match.start() + delta
      updated.append({"start": start, "end": start + 10, "original": original})
      delta += 10 - len(match.group())
      cursor = match.end()
    pieces.append(value[cursor:])
    for span in spans[index:]:
      updated.append(dict(span, start=span["start"] + delta, end=span["end"] + delta))
    value, spans = "".join(pieces), updated
  if redactions is not None:
    redactions.extend(spans)
  return value


def digest(value):
  return hashlib.sha256(value.encode("utf-8")).hexdigest()


def atomic(path, value):
  path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
  fd, temp = tempfile.mkstemp(dir=path.parent, prefix=".draft-")
  try:
    with os.fdopen(fd, "w") as stream:
      json.dump(value, stream, ensure_ascii=False)
    os.replace(temp, path)
  finally:
    if os.path.exists(temp):
      os.unlink(temp)


def command(argv, timeout=20, **kwargs):
  result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, **kwargs)
  if result.returncode:
    raise ValueError(result.stderr.strip()[:500] or tr("crashReport.commandFailed"))
  return result.stdout


class Draft:
  def __init__(self, root, crash_id, state=None):
    if not re.fullmatch(ID_PATTERN, crash_id):
      raise ValueError(tr("crashReport.invalidId"))
    self.root = Path(root)
    self.id = crash_id
    base = Path(state or os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    self.folder = base / "monarch/crashes/drafts" / crash_id.replace(":", "-")
    self.file = self.folder / "draft.json"
    self.receipt_file = base / "monarch/crashes/receipts" / (crash_id.replace(":", "-") + ".json")
    self.data = None

  def load(self):
    if self.file.exists():
      self.data = json.loads(self.file.read_text())
      return
    env = dict(os.environ, MONARCH_PATH=str(self.root))
    report = json.loads(command([str(self.root / "bin/monarch-crash-history"), "report", self.id, "--json"], env=env))
    self.data = {"report": report, "documents": [], "analysis": None, "additional": "", "warnings": [],
      "submission": str(uuid.uuid4()), "frozen": None, "endpoint": None}
    try:
      self.collect_journal()
    except (ValueError, subprocess.TimeoutExpired) as error:
      self.data["warnings"].append(tr("crashReport.collectionIncomplete", error))
    self.save()

  def save(self):
    atomic(self.file, self.data)

  def mutable(self):
    if self.data["frozen"] is not None:
      raise ValueError(tr("crashReport.frozen"))

  def add_document(self, name, purpose, original, anonymization="filtered", content=None):
    self.mutable()
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\.txt", name) or len(name) > 100:
      raise ValueError(tr("crashReport.invalidName"))
    if len(self.data["documents"]) >= 50:
      raise ValueError(tr("crashReport.tooManyFiles"))
    if any(d["name"] == name for d in self.data["documents"]):
      raise ValueError(tr("crashReport.duplicateName"))
    original = text(original)
    self.data["documents"].append({"name": name, "purpose": filtered(text(purpose, 300)),
      "original": original, "content": filtered(original) if content is None else text(content),
      "anonymization": anonymization, "override": False, "approved": None, "decision": "pending"})

  def collect_journal(self):
    boot, pid, timestamp = self.id.split(":")
    fields = "_BOOT_ID,COREDUMP_PID,COREDUMP_TIMESTAMP,COREDUMP_UID,COREDUMP_EXE,COREDUMP_PACKAGE_JSON,COREDUMP_PACKAGE_NAME,COREDUMP_PACKAGE_VERSION,COREDUMP_TRUNCATED,_KERNEL_RELEASE,MESSAGE"
    output = command(["journalctl", "--no-pager", "--all", "-o", "json", "-n", "1",
      "--output-fields=" + fields, "MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1",
      "_BOOT_ID=" + boot, "COREDUMP_PID=" + pid, "COREDUMP_TIMESTAMP=" + timestamp,
      "COREDUMP_UID=" + str(os.getuid())])
    if not output.strip():
      return
    entry = json.loads(output)
    if any(str(entry.get(k)) != v for k, v in [("_BOOT_ID", boot), ("COREDUMP_PID", pid), ("COREDUMP_TIMESTAMP", timestamp), ("COREDUMP_UID", str(os.getuid()))]):
      raise ValueError(tr("crashReport.journalMismatch"))
    message = entry.pop("MESSAGE", "")
    lines = [line for line in message.splitlines() if re.match(r"\s*(#\d+\s|Stack trace|Module |ELF object binary architecture:)", line)] if isinstance(message, str) else []
    if lines:
      self.add_document("journal-piles.txt", tr("crashReport.stackPurpose"), "\n".join(lines))
    for key in ["_BOOT_ID", "COREDUMP_PID", "COREDUMP_TIMESTAMP", "COREDUMP_UID"]:
      entry.pop(key, None)
    self.add_document("contexte-crash.txt", tr("crashReport.metadataPurpose"), json.dumps(entry, ensure_ascii=False, indent=2))

  def edit(self, document, content):
    self.mutable()
    document["content"] = text(content, TEXT_LIMIT if document is self.data["analysis"] else FILE_LIMIT)
    document["approved"] = None
    document["decision"] = "pending"
    self.save()

  def approve(self, document, include, override=False):
    self.mutable()
    if include and document["anonymization"] == "failed" and not override:
      raise ValueError(tr("crashReport.overrideRequired"))
    document["decision"] = "included" if include else "excluded"
    document["override"] = bool(override)
    document["approved"] = digest(document["content"]) if include else None
    self.save()

  def payload(self):
    def approved(document):
      if document["decision"] != "included":
        return False
      if document["approved"] != digest(document["content"]):
        raise ValueError(tr("crashReport.approvalExpired"))
      if document["anonymization"] == "failed" and not document["override"]:
        raise ValueError(tr("crashReport.overrideRequired"))
      return True
    files = [{key: d[key] for key in ("name", "purpose", "content", "anonymization", "override")}
      for d in self.data["documents"] if approved(d)]
    if sum(len(d["content"].encode()) for d in files) > TOTAL_LIMIT:
      raise ValueError(tr("crashReport.attachmentsTooLarge"))
    analysis = self.data["analysis"]
    return {"schema": 2, "report": copy.deepcopy(self.data["report"]),
      "analysis": {k: analysis[k] for k in ("content", "anonymization", "override")} if analysis and approved(analysis) else None,
      "additional": text(self.data["additional"], TEXT_LIMIT), "attachments": files}

  def endpoint(self):
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "monarch/crash-reporting.json"
    if not config.exists():
      config = self.root / "default/monarch/crash-reporting.json"
    url = os.environ.get("MONARCH_CRASH_ENDPOINT", json.loads(config.read_text())["endpoint"])
    if not re.fullmatch(r"https://[a-zA-Z0-9][a-zA-Z0-9.-]*(?::[0-9]{1,5})?", url):
      if not (os.environ.get("MONARCH_CRASH_ALLOW_LOCAL") == "1" and re.fullmatch(r"http://127\.0\.0\.1:[0-9]{1,5}", url)):
        raise ValueError(tr("crashReport.invalidEndpoint"))
    return url

  def request(self, path, payload=None):
    args = ["curl", "--disable", "--no-location", "--silent", "--show-error", "--fail",
      "--proto", "=https,http" if os.environ.get("MONARCH_CRASH_ALLOW_LOCAL") == "1" else "=https",
      "--connect-timeout", "5", "--max-time", "60", "--max-filesize", "8192"]
    if payload is not None:
      args += ["--header", "Content-Type: application/json", "--header", "Idempotency-Key: " + self.data["submission"], "--data-binary", "@-"]
    args.append(self.endpoint() + path)
    return json.loads(command(args, timeout=65, input=json.dumps(payload, ensure_ascii=False) if payload is not None else None))

  def service(self):
    result = self.request("/v2/status")
    if result.get("schema") != 2 or not result.get("enabled") or result.get("maxFileBytes") != FILE_LIMIT or result.get("maxAttachmentBytes") != TOTAL_LIMIT:
      raise ValueError(tr("crashReport.unavailable"))
    days = result.get("retentionDays")
    if type(days) is not int or not 1 <= days <= 90:
      raise ValueError(tr("crashReport.invalidRetention"))
    return result

  def send(self, confirmed_endpoint):
    if self.endpoint() != confirmed_endpoint:
      raise ValueError(tr("crashReport.endpointChanged"))
    if self.data["endpoint"] not in (None, confirmed_endpoint):
      raise ValueError(tr("crashReport.endpointConflict"))
    if self.data["frozen"] is None:
      self.data["frozen"] = self.payload()
      self.data["endpoint"] = confirmed_endpoint
      self.save()
    receipt = self.request("/v2/reports", self.data["frozen"])
    expected = confirmed_endpoint + "/admin/reports/" + digest(self.data["submission"])
    if receipt.get("url") != expected or not re.fullmatch(r"MCR-[A-F0-9]{16}", receipt.get("reference", "")):
      raise ValueError(tr("crashReport.invalidReceipt"))
    receipt["application"] = self.data["report"]["crash"]["application"]
    receipt["signal"] = self.data["report"]["crash"]["signal"]
    atomic(self.receipt_file, receipt)
    try:
      self.discard()
    except OSError as error:
      receipt["cleanupError"] = str(error)
    return receipt

  def discard(self):
    try:
      shutil.rmtree(self.folder)
    except FileNotFoundError:
      if self.folder.exists():
        raise

  def agent_job(self, deep=False):
    self.mutable()
    job = self.folder / ("agent-" + uuid.uuid4().hex)
    job.mkdir(parents=True, mode=0o700)
    inputs = {"report": self.data["report"], "documents": [
      {"name": d["name"], "content": filtered(d["content"])} for d in self.data["documents"]]}
    atomic(job / "input.json", inputs)
    skill = self.root / "default/agents/skills/crash-report/SKILL.md"
    matches = " ".join(k + "=" + v for k, v in zip(("_BOOT_ID", "COREDUMP_PID", "COREDUMP_TIMESTAMP"), self.id.split(":")))
    scope = tr("crashReport.deepPrompt", matches, os.getuid()) if deep else tr("crashReport.limitedPrompt")
    prompt = tr("crashReport.agentPrompt", skill, job, scope)
    env = dict(os.environ, MONARCH_PATH=str(self.root), PATH=str(self.root / "bin") + ":" + os.environ["PATH"])
    subprocess.Popen([str(self.root / "bin/monarch-agent"), "--prompt", prompt], cwd=job, env=env,
      stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return job

  def import_agent(self, job):
    self.mutable()
    path = job / "result.json"
    if path.is_symlink() or path.stat().st_size > 64 * FILE_LIMIT:
      raise ValueError(tr("crashReport.invalidAgentResult"))
    result = json.loads(path.read_text())
    documents = result.get("documents", [])
    if not isinstance(documents, list) or len(documents) > 20:
      raise ValueError(tr("crashReport.tooManyAgentFiles"))
    if sum(len(text(d["content"]).encode()) for d in documents) > TOTAL_LIMIT:
      raise ValueError(tr("crashReport.agentFilesTooLarge"))
    if sum(len(text(d.get("original", d["content"])).encode()) for d in documents) > TOTAL_LIMIT:
      raise ValueError(tr("crashReport.agentOriginalsTooLarge"))
    snapshot = copy.deepcopy(self.data)
    try:
      for doc in documents:
        state = "reviewed" if doc.get("anonymized") is True else "failed"
        name = doc["name"]
        if not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\.txt", name) or len(name) > 100:
          raise ValueError(tr("crashReport.invalidName"))
        names = {document["name"] for document in self.data["documents"]}
        suffix = 2
        while name in names:
          ending = f"-{suffix}.txt"
          name = doc["name"][:-4][:100 - len(ending)] + ending
          suffix += 1
        self.add_document(name, doc["purpose"], doc.get("original", doc["content"]), state,
          content=filtered(doc["content"]))
      summary = text(result["analysis"], TEXT_LIMIT)
      self.data["analysis"] = {"original": summary, "content": filtered(summary),
        "anonymization": "reviewed" if result.get("anonymized") is True else "failed",
        "override": False, "approved": None, "decision": "pending"}
      self.save()
    except Exception:
      self.data = snapshot
      raise
    shutil.rmtree(job)


def issue_url(receipt):
  body = tr("crashReport.issueBody", receipt["application"], receipt["signal"], receipt["url"])
  return "https://github.com/monarch-os/monarch/issues/new?" + urlencode({"title": "[Crash] " + receipt["application"] + " — " + receipt["signal"], "body": body})
