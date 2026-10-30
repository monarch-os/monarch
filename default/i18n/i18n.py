import json
import os
import re
import sys
from pathlib import Path

UI_STRINGS = (
    "menu.root", "menu.loading", "menu.parseFailed", "menu.stateFailed",
    "menu.initialFailed", "menu.installed", "menu.search", "menu.searchIn", "menu.result", "menu.results",
    "menu.empty", "menu.searchPlaceholder", "menu.confirmHint", "menu.navigateHint", "menu.openHint",
    "menu.cancelHint", "menu.backHint", "menu.input", "menu.select", "menu.routeErrorTitle",
)


def normalize(value):
    return "fr" if re.fullmatch(r"fr(?:[_.-].*)?", value, re.IGNORECASE) else "en"


def language():
    candidate = os.environ.get("MONARCH_LANGUAGE", "")
    if not candidate:
        config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        try:
            candidate = (config / "monarch/language").read_text(encoding="utf-8").splitlines()[0]
        except UnicodeError:
            candidate = "en"
        except (OSError, IndexError):
            pass
    if not candidate or candidate == "auto":
        candidate = next((os.environ[key] for key in ("LC_ALL", "LC_MESSAGES", "LANG")
                          if os.environ.get(key)), "en")
    return normalize(candidate)


class Translator:
    def __init__(self):
        self.language = language()
        self.english = self.load("en")
        self.catalog = self.load(self.language) if self.language != "en" else self.english

    @staticmethod
    def load(language):
        try:
            catalog = json.loads(Path(__file__).with_name(language + ".json").read_text(encoding="utf-8"))
            return catalog if isinstance(catalog, dict) else {}
        except (OSError, ValueError):
            return {}

    @staticmethod
    def entry(catalog, category, key):
        entries = catalog.get(category, {})
        value = entries.get(key) if isinstance(entries, dict) else None
        return value if isinstance(value, str) and value and "\0" not in value else None

    def get(self, category, key, fallback=None):
        fallback = self.entry(self.english, category, key) or (key if fallback is None else fallback)
        value = self.entry(self.catalog, category, key)
        if value is None:
            return fallback
        if category == "strings":
            tokens = r"%[1-9][0-9]*|%s"
            if sorted(re.findall(tokens, value)) != sorted(re.findall(tokens, fallback)):
                return fallback
        return value

    def text(self, key, *args):
        text = self.get("strings", key)
        return re.sub(r"%([1-9][0-9]*)", lambda match: str(args[int(match[1]) - 1])
                      if int(match[1]) <= len(args) else match[0], text)

    def ui(self):
        return {key: self.text(key) for key in UI_STRINGS}


if __name__ == "__main__":
    translator = Translator()
    if len(sys.argv) >= 3 and sys.argv[1] in ("--text", "--message"):
        sys.stdout.write(translator.text(sys.argv[2], *sys.argv[3:]))
        if sys.argv[1] == "--message":
            sys.stdout.write("\n")
    elif sys.argv[1:] == ["--shell"]:
        for category in translator.english.keys() | translator.catalog.keys():
            keys = set()
            for catalog in (translator.english, translator.catalog):
                entries = catalog.get(category, {})
                if isinstance(entries, dict):
                    keys.update(entries)
            for key in sorted(keys):
                if isinstance(key, str) and "\0" not in key:
                    fallback = key if category == "strings" else ""
                    value = translator.get(category, key, fallback)
                    if value:
                        sys.stdout.write(f"{category}:{key}\0{value}\0")
    elif sys.argv[1:] == ["--ui"]:
        json.dump(translator.ui(), sys.stdout, ensure_ascii=False)
    elif len(sys.argv) == 3 and sys.argv[1] == "--ui":
        prefix = sys.argv[2] + "."
        json.dump({key: translator.text(key) for key in translator.english.get("strings", {})
                   if key.startswith(prefix)}, sys.stdout, ensure_ascii=False)
    elif sys.argv[1:] == ["--commands"]:
        payload = json.load(sys.stdin)
        for command in payload["commands"]:
            command["summary"] = translator.get("commands", command["binary"], command["summary"])
        json.dump(payload, sys.stdout, ensure_ascii=False)
    elif len(sys.argv) == 3 and sys.argv[1] == "--provider":
        payload = json.load(sys.stdin)
        if sys.argv[2] == "power-profiles":
            keys = {"balanced": "powerProfile.balanced", "performance": "powerProfile.performance",
                    "power-saver": "powerProfile.powerSaver"}
            for row in payload:
                key = keys.get(row["value"])
                if key:
                    row["label"] = translator.text(key)
        json.dump(payload, sys.stdout, ensure_ascii=False)
    else:
        raise SystemExit(2)
