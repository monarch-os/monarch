import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("wifi", Path(__file__).resolve().parents[2] / "default/monarch/network-wifi.py")
wifi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wifi)
V = wifi.GLib.Variant


def profile(key="wpa-psk", ssid=b"Cafe"):
    return {"connection": {"id": "Renamed profile 1", "uuid": "saved", "type": "802-11-wireless"},
            "802-11-wireless": {"ssid": list(ssid)}, "802-11-wireless-security": {"key-mgmt": key}}


def ap(path, flags, strength):
    return {"path": path, "Ssid": list(b"Cafe"), "RsnFlags": flags, "Strength": strength, "HwAddress": path}


def devices(aps, active="secure", active_uuid="saved"):
    return [{"iface": "wlan0", "uuid": active_uuid, "state": 100, "active_ap": active, "aps": aps}]


class FakeNM(wifi.NetworkManager):
    def __init__(self, settings=None):
        self.writes = []
        self.rows = wifi.network_rows(devices([ap("secure", 0x100, 40)]), [profile()])
        self.original = settings or {"connection": {"uuid": V("s", "saved"), "type": V("s", "802-11-wireless")},
                                     "802-11-wireless": {"ssid": V("ay", b"Cafe"), "band": V("s", "a")},
                                     "802-11-wireless-security": {"key-mgmt": V("s", "wpa-psk")},
                                     "ipv4": {"method": V("s", "manual"), "route-metric": V("x", 50)}}

    def snapshot(self, rescan=False):
        return {"networks": self.rows}

    def profile(self, wanted):
        return "/profile", V("a{sa{sv}}", self.original)

    def call(self, path, interface, method, args=None):
        if method == "GetSecrets":
            return V("(a{sa{sv}})", ({},))
        self.writes.append((method, args.unpack()))
        return V("()", ())


class WifiTests(unittest.TestCase):
    def test_identity_and_active_bss(self):
        rows = wifi.network_rows(devices([ap("open", 0, 90), ap("secure", 0x100, 40), ap("strong", 0x100, 80)]), [profile()])
        self.assertEqual(len(rows), 2)
        connected = next(r for r in rows if r["connected"])
        self.assertEqual((connected["security"], connected["signal"], connected["uuid"]), ("WPA2", 40, "saved"))
        self.assertFalse(next(r for r in rows if r["security"] == "open")["saved"])

    def test_ssid_bytes_and_interface_constraint(self):
        candidate = ap("secure", 0x100, 40)
        candidate["Ssid"] = list(" Café:5G ".encode())
        stored = profile(ssid=" Café:5G ".encode())
        self.assertTrue(wifi.compatible(stored, candidate, "wlan0"))
        stored["connection"]["interface-name"] = "wlan1"
        self.assertFalse(wifi.compatible(stored, candidate, "wlan0"))

    def test_repair_preserves_uuid_and_settings_without_secret_in_process(self):
        nm = FakeNM()
        request = dict(nm.rows[0], password="fixture secret ' ; $()\nend")
        with patch.object(wifi, "command") as command:
            nm.join(request)
        self.assertNotIn(request["password"], repr(command.call_args))
        method, args = nm.writes[0]
        self.assertEqual(method, "Update")
        saved = args[0]
        self.assertEqual(saved["ipv4"]["route-metric"], 50)
        self.assertEqual(saved["802-11-wireless"]["band"], "a")
        self.assertEqual(saved["connection"]["uuid"], "saved")
        self.assertEqual(saved["802-11-wireless-security"]["psk"], request["password"])
        self.assertEqual(saved["802-11-wireless-security"]["psk-flags"], 0)

    def test_bare_rejoin_never_rewrites_profile(self):
        nm = FakeNM()
        with patch.object(wifi, "command"):
            nm.join(nm.rows[0])
        self.assertEqual(nm.writes, [])

    def test_stale_target_rejected_before_write(self):
        nm = FakeNM()
        request = dict(nm.rows[0], bssid="old-ap", password="fixture")
        with patch.object(wifi, "command") as command, self.assertRaises(ValueError):
            nm.join(request)
        command.assert_not_called()
        self.assertEqual(nm.writes, [])

    def test_new_profile_appearing_before_retry_is_not_duplicated(self):
        nm = FakeNM()
        request = dict(nm.rows[0], uuid="", password="fixture")
        with patch.object(wifi, "command") as command, self.assertRaisesRegex(ValueError, "profile changed"):
            nm.join(request)
        command.assert_not_called()
        self.assertEqual(nm.writes, [])

    def test_enterprise_requires_ca_and_domain(self):
        nm = FakeNM()
        nm.rows[0].update(uuid="", security="802.1X")
        with patch.object(wifi, "command") as command, self.assertRaisesRegex(ValueError, "CA certificate"):
            nm.join(dict(nm.rows[0], password="fixture", identity="user"))
        command.assert_not_called()
        self.assertEqual(nm.writes, [])

    def test_enterprise_sets_server_validation(self):
        nm = FakeNM()
        nm.rows[0].update(uuid="", security="802.1X")
        with tempfile.NamedTemporaryFile() as ca, patch.object(wifi, "command"):
            nm.join(dict(nm.rows[0], password="fixture", identity="user", ca=ca.name, domain="auth.example.org"))
        method, args = nm.writes[0]
        self.assertEqual(method, "AddConnection")
        self.assertEqual(args[0]["802-1x"]["domain-suffix-match"], "auth.example.org")
        self.assertTrue(bytes(args[0]["802-1x"]["ca-cert"]).startswith(b"file:///"))

    def test_private_request_is_consumed_before_activation(self):
        directory = tempfile.mkdtemp(prefix="monarch-wifi-")
        path = Path(directory) / "request.json"
        path.write_text(json.dumps({"password": "fixture"}))
        self.assertEqual(wifi.read_request(str(path)), {"password": "fixture"})
        self.assertFalse(Path(directory).exists())

    def test_symlink_request_is_refused(self):
        with tempfile.TemporaryDirectory(prefix="monarch-wifi-") as directory:
            path = Path(directory) / "request.json"
            path.symlink_to("/etc/passwd")
            with self.assertRaises(OSError):
                wifi.read_request(str(path))

    def test_stale_disconnect_never_deactivates_another_uuid(self):
        nm = FakeNM()
        nm.props = lambda path, _: ({"ActiveConnections": ["/active"]} if path == wifi.ROOT else
                                    {"Uuid": "new-uuid", "Devices": ["/wlan0"]})
        with self.assertRaisesRegex(ValueError, "connection changed"):
            nm.disconnect("wlan0", "old-uuid")
        self.assertEqual(nm.writes, [])


if __name__ == "__main__":
    unittest.main()
