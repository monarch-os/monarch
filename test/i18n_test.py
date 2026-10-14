import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("monarch_i18n", ROOT / "default/i18n/i18n.py")
I18N = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(I18N)


class InternationalizationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.config = self.home / "config"
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
                    "MONARCH_PATH": str(ROOT), "LANG": "en_US.UTF-8"}
        for key in ("MONARCH_LANGUAGE", "LC_ALL", "LC_MESSAGES"):
            self.env.pop(key, None)

    def run_command(self, binary, *args, env=None, success=True, data=None):
        result = subprocess.run([str(ROOT / "bin" / binary), *args], env=env or self.env,
                                text=True, input=data, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def preference(self, value):
        path = self.config / "monarch/language"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def catalog_runtime(self):
        runtime = self.home / "runtime"
        shutil.copytree(ROOT / "default/i18n", runtime / "default/i18n")
        return runtime

    def test_language_precedence_and_python_bash_parity(self):
        cases = [
            ({}, None, "en"),
            ({"LANG": "fr_FR.UTF-8"}, None, "fr"),
            ({"LANG": "fr_CA.UTF-8", "LC_MESSAGES": "en_US.UTF-8"}, None, "en"),
            ({"LANG": "en_US.UTF-8", "LC_MESSAGES": "fr_FR.UTF-8"}, None, "fr"),
            ({"LC_ALL": "C", "LANG": "fr_FR.UTF-8"}, None, "en"),
            ({"LANG": "fr_FR.UTF-8"}, "en", "en"),
            ({"LANG": "en_US.UTF-8"}, "fr", "fr"),
            ({"LANG": "fr_FR.UTF-8"}, "auto", "fr"),
            ({"LANG": "fr_FR.UTF-8"}, "../../evil", "en"),
            ({"LANG": "fr_FR.UTF-8"}, "", "fr"),
            ({"MONARCH_LANGUAGE": "en", "LANG": "fr_FR.UTF-8"}, "fr", "en"),
            ({"MONARCH_LANGUAGE": "fr"}, "en", "fr"),
            ({"MONARCH_LANGUAGE": "auto", "LANG": "fr_FR.UTF-8"}, "en", "fr"),
            ({"LANG": "de_DE.UTF-8"}, None, "en"),
        ]
        for changes, preference, expected in cases:
            with self.subTest(changes=changes, preference=preference):
                path = self.config / "monarch/language"
                if preference is None:
                    path.unlink(missing_ok=True)
                else:
                    self.preference(preference)
                env = {**self.env, **changes}
                self.assertEqual(self.run_command("monarch-language", env=env).stdout, expected + "\n")
                result = subprocess.run(["python3", "-B", "-c",
                                         "import i18n; print(i18n.language())"],
                                        cwd=ROOT / "default/i18n", env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, expected + "\n")

    def test_persistent_selection_is_private_atomic_and_does_not_change_locale(self):
        self.run_command("monarch-language", "fr")
        path = self.config / "monarch/language"
        self.assertEqual(path.read_text(), "fr\n")
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.run_command("monarch-language").stdout, "fr\n")
        self.assertIn("Centre de commandes Monarch", self.run_command("monarch", "--help").stdout)
        self.run_command("monarch-language", "auto")
        self.assertEqual(self.run_command("monarch-language", "--preference").stdout, "auto\n")
        self.assertEqual(self.run_command("monarch-language").stdout, "en\n")
        self.assertFalse(list(path.parent.glob(".language.*")))
        self.assertEqual(self.env["LANG"], "en_US.UTF-8")
        self.assertFalse((self.config / "noctalia").exists())
        self.assertEqual(self.run_command("monarch-language", "--list").stdout, "auto\nen\nfr\n")
        before = path.read_bytes()
        for args in [("../../outside",), ("fr", "extra"), ("--list", "extra")]:
            self.run_command("monarch-language", *args, success=False)
            self.assertEqual(path.read_bytes(), before)

    def test_xdg_fallback_and_invalid_preference(self):
        env = {k: v for k, v in self.env.items() if k != "XDG_CONFIG_HOME"}
        self.run_command("monarch-language", "fr", env=env)
        self.assertEqual((self.home / ".config/monarch/language").read_text(), "fr\n")
        path = self.preference("fr\nen")
        self.assertEqual(self.run_command("monarch-language").stdout, "fr\n")
        path.write_bytes(b"\xff")
        self.assertEqual(self.run_command("monarch-language").stdout, "en\n")

    def test_help_is_translated_but_routes_arguments_and_json_are_stable(self):
        en = {**self.env, "MONARCH_LANGUAGE": "en"}
        fr = {**self.env, "MONARCH_LANGUAGE": "fr"}
        help_text = self.run_command("monarch", "screenshot", "--help", env=fr).stdout
        self.assertIn("Faire une capture d’écran", help_text)
        self.assertIn("Utilisation :", help_text)
        self.assertIn("monarch capture screenshot", help_text)
        self.assertIn("[--editor=<name>]", help_text)
        for args in [("commands", "--all", "--json"), ("screenshot", "--help", "--json")]:
            self.assertEqual(self.run_command("monarch", *args, env=en).stdout,
                             self.run_command("monarch", *args, env=fr).stdout)
        error = self.run_command("monarch", "does-not-exist", env=fr, success=False)
        self.assertIn("Commande Monarch inconnue", error.stderr)
        self.assertEqual(error.returncode, 127)
        self.assertIn("Commandes Install", self.run_command("monarch", "install", "--help", env=fr).stdout)

    def test_placeholders_preserve_literal_values_without_resubstitution(self):
        fr = {**self.env, "MONARCH_LANGUAGE": "fr"}
        result = self.run_command("monarch-i18n", "cli.invalidMetadata", "%2", 'a&b\\c "%1"', env=fr)
        self.assertEqual(result.stdout, 'Métadonnées invalides dans %2 : a&b\\c "%1"')
        runtime = self.catalog_runtime()
        english_path = runtime / "default/i18n/en.json"
        english = json.loads(english_path.read_text())
        english["strings"]["fixture.placeholders"] = "Unknown %1 %10 %2"
        english_path.write_text(json.dumps(english))
        result = self.run_command("monarch-i18n", "fixture.placeholders", *map(str, range(1, 11)),
                                  env={**fr, "MONARCH_PATH": str(runtime)})
        self.assertEqual(result.stdout, "Unknown 1 10 2")
        self.assertEqual(self.run_command("monarch-i18n", "unknown.key", env=fr).stdout, "unknown.key")

    def test_command_picker_translates_descriptions_without_changing_commands(self):
        helpers = json.dumps([{"route": "custom-helper", "summary": "Shell alias", "definition": "printf hello"}])
        rows = {}
        for language in ("en", "fr"):
            output = self.run_command("monarch-cmd-picker", "--list", "--shell-commands",
                                      env={**self.env, "MONARCH_LANGUAGE": language}, data=helpers).stdout
            rows[language] = {fields[0]: fields for fields in
                              (line.split("\t") for line in output.splitlines())}
        self.assertEqual(set(rows["en"]), set(rows["fr"]))
        for route in rows["en"]:
            self.assertEqual(rows["en"][route][2:4], rows["fr"][route][2:4])
        self.assertEqual(rows["fr"]["monarch capture screenshot"][1], "Faire une capture d’écran")
        self.assertEqual(rows["fr"]["custom-helper"][1], "Raccourci shell défini par l’utilisateur")
        self.assertEqual(rows["fr"]["custom-helper"][3], "printf hello")

    def test_missing_or_invalid_catalog_falls_back_to_english(self):
        runtime = self.catalog_runtime() / "default/i18n"
        (runtime / "fr.json").unlink()
        command = ["bash", "-c", 'source "$1/i18n.sh"; monarch_t "cli.usage"', "bash", str(runtime)]
        env = {**self.env, "MONARCH_LANGUAGE": "fr"}
        for content in (None, "{invalid", '[]', '{"strings":{"cli.usage":false}}',
                        '{"strings":{"cli.usage":""}}'):
            if content is not None:
                (runtime / "fr.json").write_text(content)
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "Usage:")
        (runtime / "fr.json").write_text('{"strings":{"cli.invalidMetadata":"Erreur %1"}}')
        command[2] = 'source "$1/i18n.sh"; monarch_t "cli.invalidMetadata" a b'
        self.assertEqual(subprocess.check_output(command, env=env, text=True), "Invalid metadata in a: b")
        (runtime / "en.json").unlink()
        command[2] = 'source "$1/i18n.sh"; monarch_t "cli.usage"'
        self.assertEqual(subprocess.check_output(command, env=env, text=True), "cli.usage")

    def test_stable_keys_survive_english_wording_changes(self):
        runtime = self.catalog_runtime()
        english_path = runtime / "default/i18n/en.json"
        english = json.loads(english_path.read_text())
        english["strings"]["update.cancelled"] = "The update was cancelled."
        english["menu"]["apps.label"] = "Launch applications"
        english_path.write_text(json.dumps(english))
        for language, expected in (("en", "The update was cancelled."), ("fr", "Mise à jour annulée")):
            self.assertEqual(self.run_command("monarch-i18n", "update.cancelled",
                             env={**self.env, "MONARCH_PATH": str(runtime), "MONARCH_LANGUAGE": language}).stdout,
                             expected)
        (runtime / "default/monarch").mkdir()
        shutil.copy(ROOT / "default/monarch/monarch-menu.jsonc", runtime / "default/monarch")
        translated = json.loads(self.run_command("monarch-menu", "--tree",
                                env={**self.env, "MONARCH_PATH": str(runtime), "MONARCH_LANGUAGE": "fr"}).stdout)
        self.assertEqual(translated[0]["label"], "Applications")
        self.assertIn("Launch applications", translated[0]["searchText"])

    def test_menu_translates_before_user_overlays_and_keeps_actions(self):
        en = {**self.env, "MONARCH_LANGUAGE": "en"}
        fr = {**self.env, "MONARCH_LANGUAGE": "fr"}
        tree_en = json.loads(self.run_command("monarch-menu", "--tree", env=en).stdout)
        tree_fr = json.loads(self.run_command("monarch-menu", "--tree", env=fr).stdout)
        self.assertEqual([row["id"] for row in tree_en], [row["id"] for row in tree_fr])
        for original, translated in zip(tree_en, tree_fr):
            for key in ("action", "target", "provider", "aliases", "when", "checked", "disabled"):
                self.assertEqual(original.get(key), translated.get(key))
        self.assertEqual(tree_fr[0]["label"], "Applications")
        capture = next(row for row in tree_fr if row["id"] == "trigger.capture.screenshot")
        self.assertIn("Screenshot", capture["searchText"])
        self.assertIn("Capture d’écran", capture["searchText"])
        extension = self.home / ".config/monarch/extensions/monarch-menu.jsonc"
        extension.parent.mkdir(parents=True)
        extension.write_text(json.dumps({"apps": {"label": "My custom name"}, "custom": {"label": "Settings", "action": "true"}}))
        overlay = json.loads(self.run_command("monarch-menu", "--tree", env=fr).stdout)
        self.assertEqual(overlay[0]["label"], "My custom name")
        self.assertEqual(overlay[-1]["label"], "Settings")
        payload = json.loads(self.run_command("monarch-menu", "--initial-state", "root", env=fr).stdout)
        self.assertEqual(payload["strings"]["menu.root"], "Aller")
        self.assertEqual(payload["strings"]["menu.results"], "%1 résultats")
        go = next(row for row in tree_fr if row["id"] == "install.development.go")
        self.assertEqual(go["label"], "Go")
        self.assertEqual(self.run_command("monarch-menu", "--resolve", "style", env=fr).stdout, "style\n")
        self.assertIsInstance(json.loads(self.run_command("monarch-menu", "--initial", "root", env=fr).stdout), list)

    def test_direct_dispatch_and_machine_catalog_do_not_launch_translation_processes(self):
        runtime = self.home / "runtime"
        (runtime / "bin").mkdir(parents=True)
        (runtime / "bin/monarch").symlink_to(ROOT / "bin/monarch")
        command = runtime / "bin/monarch-fixture"
        command.write_text('#!/bin/bash\n# monarch:summary=Fixture\nprintf \'{"ok":true}\\n\'\n')
        command.chmod(0o755)
        tools = self.home / "tools"
        tools.mkdir()
        python = tools / "python"
        python.write_text('#!/bin/bash\nprintf called > "$HOME/python-called"\nexit 1\n')
        python.chmod(0o755)
        env = {**self.env, "MONARCH_LANGUAGE": "fr", "PATH": str(tools) + ":" + os.environ["PATH"]}
        for args in [("fixture",), ("commands", "--json")]:
            result = subprocess.run([str(runtime / "bin/monarch"), *args], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["ok"])
            self.assertFalse((self.home / "python-called").exists())

    def test_catalog_has_unique_keys_valid_placeholders_and_full_command_coverage(self):
        def unique_pairs(pairs):
            result = {}
            for key, value in pairs:
                self.assertNotIn(key, result, f"Duplicate catalog key: {key}")
                result[key] = value
            return result

        catalog = json.loads((ROOT / "default/i18n/fr.json").read_text(), object_pairs_hook=unique_pairs)
        english = json.loads((ROOT / "default/i18n/en.json").read_text(), object_pairs_hook=unique_pairs)
        self.assertEqual(set(catalog["strings"]), set(english["strings"]))
        for category, entries in catalog.items():
            self.assertIsInstance(entries, dict)
            for key, value in entries.items():
                self.assertIsInstance(value, str)
                self.assertTrue(value)
                self.assertNotIn("\0", key + value)
                if category == "strings":
                    self.assertRegex(key, r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$")
                    tokens = r"%[1-9][0-9]*|%s"
                    self.assertEqual(sorted(re.findall(tokens, english["strings"][key])), sorted(re.findall(tokens, value)), key)
        commands = json.loads(self.run_command("monarch", "commands", "--all", "--json").stdout)["commands"]
        self.assertEqual(set(catalog["commands"]), {command["binary"] for command in commands})
        self.assertTrue(set(I18N.UI_STRINGS) <= set(catalog["strings"]))
        menu = json.loads(self.run_command("monarch-menu", "--tree",
                          env={**self.env, "MONARCH_LANGUAGE": "en"}).stdout)
        fields = {row["id"] + "." + field for row in menu
                  for field in ("label", "title", "description", "disabledLabel") if field in row}
        self.assertTrue(set(catalog["menu"]) <= fields)
        self.assertEqual(set(english["menu"]), fields)
        raw = (ROOT / "default/monarch/monarch-menu.jsonc").read_text()
        raw = re.sub(r"^\s*//.*$", "", raw, flags=re.MULTILINE)
        shipped = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
        for entry_id, row in shipped.items():
            self.assertIn(entry_id + ".label", english["menu"])
            self.assertFalse(set(row) & {"label", "title", "description", "disabledLabel"}, entry_id)
        for path in (ROOT / "bin").glob("monarch*"):
            if "monarch_i18n_load" in path.read_text():
                self.assertIn("source ", path.read_text(), f"{path.name}: cache requires helper")
            for key in re.findall(r"(?:monarch_(?:t|message)|monarch-i18n(?:\s+--newline)?)\s+['\"]([^'\"]+)['\"]", path.read_text()):
                if "$" in key:
                    continue
                self.assertIn(key, english["strings"], f"{path.name}: unknown message key {key}")

    def test_menu_catalog_fallback_and_field_overlays(self):
        runtime = self.catalog_runtime()
        (runtime / "default/monarch").mkdir()
        shutil.copy(ROOT / "default/monarch/monarch-menu.jsonc", runtime / "default/monarch")
        french_path = runtime / "default/i18n/fr.json"
        french = json.loads(french_path.read_text())
        french["menu"]["apps.label"] = ""
        french["menu"]["trigger.title"] = False
        french_path.write_text(json.dumps(french))
        extension = self.home / ".config/monarch/extensions/monarch-menu.jsonc"
        extension.parent.mkdir(parents=True)
        extension.write_text(json.dumps({"trigger": {"description": "My description"},
                                         "custom": {"action": "true"}}))
        env = {**self.env, "MONARCH_PATH": str(runtime), "MONARCH_LANGUAGE": "fr"}
        tree = json.loads(self.run_command("monarch-menu", "--tree", env=env).stdout)
        rows = {row["id"]: row for row in tree}
        self.assertEqual(rows["apps"]["label"], "Apps")
        self.assertEqual(rows["trigger"]["label"], "Actions")
        self.assertEqual(rows["trigger"]["title"], "Actions")
        self.assertEqual(rows["trigger"]["description"], "My description")
        self.assertNotIn("label", rows["custom"])
        french_path.unlink()
        english = json.loads(self.run_command("monarch-menu", "--tree", env=env).stdout)
        self.assertEqual(english[0]["label"], "Apps")
        self.assertEqual(next(row for row in english if row["id"] == "setup")["label"], "Settings")

    def test_provider_translates_labels_by_value_without_changing_identity(self):
        payload = [{"label": "balanced", "value": "balanced", "current": True},
                   {"label": "power-saver", "value": "power-saver", "current": False}]
        env = {**self.env, "MONARCH_LANGUAGE": "fr"}
        for provider in ("power-profiles", "fonts"):
            result = subprocess.run(["python3", str(ROOT / "default/i18n/i18n.py"), "--provider", provider],
                                    input=json.dumps(payload), env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            translated = json.loads(result.stdout)
            for original, row in zip(payload, translated):
                self.assertEqual(row["value"], original["value"])
                self.assertEqual(row["current"], original["current"])
            self.assertEqual(translated[0]["label"], "équilibré" if provider == "power-profiles" else "balanced")

    def test_standalone_and_cached_helper_have_identical_output(self):
        for language in ("en", "fr"):
            env = {**self.env, "MONARCH_LANGUAGE": language}
            for key, values in (("cli.invalidMetadata", ("%2", "a&b\\c")),
                                ("picker.preview", ()), ("unknown.key", ())):
                standalone = self.run_command("monarch-i18n", key, *values, env=env).stdout
                helper = self.run_command("monarch-i18n", "--helper", env=env).stdout.strip()
                cached = subprocess.check_output(
                    ["bash", "-c", 'source "$1"; shift; monarch_t "$@"', "bash", helper, key, *values],
                    env=env, text=True)
                self.assertEqual(standalone, cached)
                self.assertEqual(self.run_command("monarch-i18n", "--newline", key, *values, env=env).stdout,
                                 standalone + "\n")
        for args in ((), ("--newline",), ("--helper", "extra"), ("--root", "extra")):
            self.assertEqual(self.run_command("monarch-i18n", *args, success=False).returncode, 2)

    def test_runtime_resolution_supports_symlinks_and_helper_caches_once(self):
        link = self.home / "linked-i18n"
        link.symlink_to(ROOT / "bin/monarch-i18n")
        env = {key: value for key, value in self.env.items() if key != "MONARCH_PATH"}
        self.assertEqual(subprocess.check_output([str(link), "--root"], env=env, text=True).strip(), str(ROOT))
        self.assertEqual(subprocess.check_output([str(link), "--helper"], env=env, text=True).strip(),
                         str(ROOT / "default/i18n/i18n.sh"))
        env["MONARCH_PATH"] = str(self.home / "missing-runtime")
        self.assertEqual(subprocess.check_output([str(link), "--root"], env=env, text=True).strip(), str(ROOT))
        tools = self.home / "tools"
        tools.mkdir()
        python = tools / "python"
        python.write_text('#!/bin/bash\nprintf "called\\n" >> "$HOME/catalog-loads"\nexec ' +
                          shutil.which("python") + ' "$@"\n')
        python.chmod(0o755)
        env = {**self.env, "PATH": str(tools) + ":" + os.environ["PATH"], "MONARCH_LANGUAGE": "fr"}
        subprocess.run([str(link), "--helper"], env=env, check=True, capture_output=True)
        self.assertFalse((self.home / "catalog-loads").exists())
        result = subprocess.check_output(["bash", "-c",
            'source "$1"; monarch_i18n_load; monarch_t update.cancelled; monarch_t update.cancelled',
            "bash", str(ROOT / "default/i18n/i18n.sh")], env=env, text=True)
        self.assertEqual(result, "Mise à jour annulée" * 2)
        self.assertEqual((self.home / "catalog-loads").read_text().splitlines(), ["called"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
