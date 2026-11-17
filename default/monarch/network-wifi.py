import json
import os
import stat
import subprocess
import sys
import tempfile
import uuid

from gi.repository import Gio, GLib


SERVICE = "org.freedesktop.NetworkManager"
ROOT = "/org/freedesktop/NetworkManager"
SETTINGS = ROOT + "/Settings"
CONNECTION = SERVICE + ".Settings.Connection"


def variant_settings(value):
    result = {}
    for i in range(value.n_children()):
        entry = value.get_child_value(i)
        group = entry.get_child_value(1)
        result[entry.get_child_value(0).unpack()] = {
            group.get_child_value(j).get_child_value(0).unpack():
            group.get_child_value(j).get_child_value(1).get_variant()
            for j in range(group.n_children())
        }
    return result


def security(ap):
    flags = ap.get("WpaFlags", 0) | ap.get("RsnFlags", 0)
    if flags & (0x200 | 0x2000):
        return "802.1X"
    if flags & 0x100:
        return "WPA2"
    if flags & 0x400:
        return "WPA3"
    if flags & (0x800 | 0x1000):
        return "OWE"
    return "WEP" if ap.get("Flags", 0) & 1 else "open"


def display_ssid(raw):
    return "".join(f"\\x{ord(char):02x}" if ord(char) < 32 or ord(char) == 127 else char
                   for char in raw.decode("utf-8", "replace"))


def compatible(settings, ap, iface):
    wireless = settings.get("802-11-wireless", {})
    connection = settings.get("connection", {})
    if connection.get("type") != "802-11-wireless":
        return False
    if bytes(wireless.get("ssid", [])) != bytes(ap.get("Ssid", [])):
        return False
    if connection.get("interface-name", iface) != iface:
        return False
    bssid = wireless.get("bssid")
    if bssid and bytes(bssid).hex() != ap["HwAddress"].replace(":", "").lower():
        return False
    band = wireless.get("band", "")
    if band:
        frequency = ap.get("Frequency", 0)
        bounds = {"bg": (2400, 2500), "a": (4900, 5925), "6GHz": (5925, 7125)}.get(band)
        if bounds is None or not bounds[0] <= frequency < bounds[1]:
            return False
    key = settings.get("802-11-wireless-security", {}).get("key-mgmt", "")
    return key in {
        "open": ("",), "OWE": ("owe",), "WEP": ("none",),
        "WPA2": ("wpa-psk", "sae"), "WPA3": ("sae", "wpa-psk"),
        "802.1X": ("wpa-eap", "wpa-eap-suite-b-192", "ieee8021x"),
    }[security(ap)]


def network_rows(devices, profiles):
    rows = {}
    for device in devices:
        for ap in device["aps"]:
            raw = bytes(ap.get("Ssid", []))
            if not raw or ap.get("Mode", 2) != 2:
                continue
            kind = security(ap)
            key = device["iface"] + ":" + raw.hex() + ":" + kind
            connected = ap["path"] == device["active_ap"] and device["state"] == 100
            matches = [p for p in profiles if compatible(p, ap, device["iface"])]
            matches.sort(key=lambda p: (
                p["connection"]["uuid"] != device["uuid"],
                -p["connection"].get("timestamp", 0), p["connection"]["uuid"]))
            profile = matches[0] if matches else {}
            row = {
                "key": key, "ssid": display_ssid(raw), "ssid_hex": raw.hex(),
                "security": kind, "signal": ap.get("Strength", 0), "connected": connected,
                "saved": bool(profile), "uuid": profile.get("connection", {}).get("uuid", ""),
                "device": device["iface"], "bssid": ap["HwAddress"],
                "connecting": device["state"] in range(40, 100) and (
                    ap["path"] == device["active_ap"] or
                    bool(profile) and profile["connection"]["uuid"] == device["uuid"]),
            }
            previous = rows.get(key)
            if previous is None or connected or (not previous["connected"] and
                    (row["saved"], row["signal"]) > (previous["saved"], previous["signal"])):
                rows[key] = row
    return sorted(rows.values(), key=lambda r: (not r["connected"], not r["saved"], -r["signal"], r["key"]))


class NetworkManager:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def call(self, path, interface, method, args=None):
        return self.bus.call_sync(SERVICE, path, interface, method, args, None,
                                  Gio.DBusCallFlags.NONE, 5000, None)

    def props(self, path, interface):
        return self.call(path, "org.freedesktop.DBus.Properties", "GetAll",
                         GLib.Variant("(s)", (interface,))).unpack()[0]

    def profile_paths(self):
        return self.call(SETTINGS, SERVICE + ".Settings", "ListConnections").unpack()[0]

    def settings(self, path):
        return self.call(path, CONNECTION, "GetSettings").get_child_value(0)

    def profile(self, wanted):
        for path in self.profile_paths():
            settings = self.settings(path)
            if settings.unpack().get("connection", {}).get("uuid") == wanted:
                return path, settings
        raise ValueError("The saved profile no longer exists. Refresh the network list.")

    def snapshot(self, rescan=False):
        general = self.props(ROOT, SERVICE)
        profiles = [self.settings(path).unpack() for path in self.profile_paths()]
        devices = []
        for path in general["Devices"]:
            props = self.props(path, SERVICE + ".Device")
            if props.get("DeviceType") != 2 or not props.get("Managed"):
                continue
            iface = props["Interface"]
            if rescan:
                command(["nmcli", "--wait", "10", "device", "wifi", "rescan", "ifname", iface])
            wireless = self.props(path, SERVICE + ".Device.Wireless")
            active = props.get("ActiveConnection", "/")
            active_uuid = self.props(active, SERVICE + ".Connection.Active").get("Uuid", "") if active != "/" else ""
            aps = []
            for ap_path in wireless.get("AccessPoints", []):
                try:
                    ap = self.props(ap_path, SERVICE + ".AccessPoint")
                except GLib.Error:
                    continue  # An AP may disappear between the two D-Bus reads.
                aps.append(dict(ap, path=ap_path))
            devices.append({"iface": iface, "state": props["State"], "uuid": active_uuid,
                            "active_ap": wireless.get("ActiveAccessPoint", "/"), "aps": aps})
        return {"enabled": general.get("WirelessEnabled", False) and general.get("WirelessHardwareEnabled", False),
                "present": bool(devices), "networks": network_rows(devices, profiles)}

    def disconnect(self, iface, wanted):
        active = self.props(ROOT, SERVICE)["ActiveConnections"]
        for path in active:
            props = self.props(path, SERVICE + ".Connection.Active")
            if props["Uuid"] == wanted and any(
                    self.props(dev, SERVICE + ".Device")["Interface"] == iface for dev in props["Devices"]):
                self.call(ROOT, SERVICE, "DeactivateConnection", GLib.Variant("(o)", (path,)))
                return
        raise ValueError("The connection changed; refresh before disconnecting.")

    def join(self, request):
        rows = self.snapshot()["networks"]
        row = next((r for r in rows if r["key"] == request.get("key") and r["bssid"] == request.get("bssid")), None)
        if row is None:
            raise ValueError("This access point is no longer available. Refresh and try again.")
        wanted = request.get("uuid", "")
        if row["uuid"] != wanted:
            raise ValueError("The saved profile changed. Refresh and try again.")
        if row["security"] == "WEP":
            raise ValueError("Configure legacy WEP networks in NetworkManager settings.")
        password = request.get("password", "")
        if not isinstance(password, str) or "\0" in password:
            raise ValueError("Invalid password.")
        if wanted:
            path, original = self.profile(wanted)
            settings = variant_settings(original)
        else:
            wanted = str(uuid.uuid4())
            settings = {
                "connection": {"id": GLib.Variant("s", row["ssid"]), "uuid": GLib.Variant("s", wanted),
                               "type": GLib.Variant("s", "802-11-wireless")},
                "802-11-wireless": {"ssid": GLib.Variant("ay", bytes.fromhex(row["ssid_hex"])),
                                    "mode": GLib.Variant("s", "infrastructure")},
                "ipv4": {"method": GLib.Variant("s", "auto")},
                "ipv6": {"method": GLib.Variant("s", "auto")},
            }
        if row["security"] == "802.1X":
            eap = settings.setdefault("802-1x", {})
            ca, domain, identity = (request.get(k, "") for k in ("ca", "domain", "identity"))
            if ca:
                if not os.path.isabs(ca) or not os.path.isfile(ca):
                    raise ValueError("Select a readable CA certificate using an absolute path.")
                eap["ca-cert"] = GLib.Variant("ay", ("file://" + ca + "\0").encode())
            if domain:
                eap["domain-suffix-match"] = GLib.Variant("s", domain)
            if identity:
                eap["identity"] = GLib.Variant("s", identity)
            if not request.get("uuid"):
                if not os.path.isabs(ca) or not os.path.isfile(ca) or not domain or not identity:
                    raise ValueError("Enterprise Wi-Fi requires identity, CA certificate path and authentication server domain.")
                eap.update({"eap": GLib.Variant("as", ["peap"]), "phase2-auth": GLib.Variant("s", "mschapv2"),
                            "identity": GLib.Variant("s", identity), "ca-cert": GLib.Variant("ay", ("file://" + ca + "\0").encode()),
                            "domain-suffix-match": GLib.Variant("s", domain)})
                settings["802-11-wireless-security"] = {"key-mgmt": GLib.Variant("s", "wpa-eap")}
            trust = {k: v.unpack() for k, v in eap.items()}
            if not (trust.get("ca-cert") or trust.get("system-ca-certs")) or not (
                    trust.get("domain-suffix-match") or trust.get("domain-match")):
                raise ValueError("Enterprise Wi-Fi requires a trusted CA and authentication server domain.")
            if password:
                eap.update({"password": GLib.Variant("s", password), "password-flags": GLib.Variant("u", 0)})
        elif row["security"] != "open":
            sec = settings.setdefault("802-11-wireless-security", {})
            if not request.get("uuid"):
                sec["key-mgmt"] = GLib.Variant("s", {"OWE": "owe", "WPA2": "wpa-psk", "WPA3": "sae"}[row["security"]])
            if password:
                sec.update({"psk": GLib.Variant("s", password), "psk-flags": GLib.Variant("u", 0)})
        if not request.get("uuid"):
            if row["security"] not in ("open", "OWE") and not password:
                raise ValueError("Enter a password.")
            self.call(SETTINGS, SERVICE + ".Settings", "AddConnection", GLib.Variant("(a{sa{sv}})", (settings,)))
        elif password:
            # GetSettings excludes secrets. Merge them before replacing settings,
            # preserving EAP client keys and other credentials on existing profiles.
            group = "802-1x" if row["security"] == "802.1X" else "802-11-wireless-security"
            secrets = self.call(path, CONNECTION, "GetSecrets", GLib.Variant("(s)", (group,))).get_child_value(0)
            for name, values in variant_settings(secrets).items():
                for key, value in values.items():
                    settings.setdefault(name, {}).setdefault(key, value)
            self.call(path, CONNECTION, "Update", GLib.Variant("(a{sa{sv}})", (settings,)))
        try:
            command(["nmcli", "--wait", "25", "connection", "up", "uuid", wanted,
                     "ifname", row["device"], "ap", row["bssid"]])
        except (ValueError, subprocess.TimeoutExpired):
            # nmcli's wait timeout does not cancel NM's activation. Only cancel
            # this still-pending UUID, never a replacement or an established link.
            for active in self.props(ROOT, SERVICE)["ActiveConnections"]:
                props = self.props(active, SERVICE + ".Connection.Active")
                if props.get("Uuid") == wanted and props.get("State") == 1 and any(
                        self.props(dev, SERVICE + ".Device")["Interface"] == row["device"] for dev in props["Devices"]):
                    self.call(ROOT, SERVICE, "DeactivateConnection", GLib.Variant("(o)", (active,)))
            raise


def command(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=30, env=dict(os.environ, LC_ALL="C"))
    if result.returncode:
        raise ValueError(result.stderr.strip() or "NetworkManager operation failed.")


def read_request(path):
    directory = os.path.dirname(path)
    parent = os.lstat(directory)
    if (not os.path.basename(directory).startswith("monarch-wifi-") or
            not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid() or stat.S_IMODE(parent.st_mode) != 0o700):
        raise ValueError("Invalid private request directory.")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 16384:
            raise ValueError("Invalid credential request.")
        with os.fdopen(fd, "r", encoding="utf-8") as stream:
            fd = -1
            request = json.load(stream)
        if not isinstance(request, dict):
            raise ValueError("Invalid credential request.")
        return request
    finally:
        if fd >= 0:
            os.close(fd)
        os.unlink(path)
        os.rmdir(directory)


def discard(directory):
    info = os.lstat(directory)
    if (not os.path.basename(directory).startswith("monarch-wifi-") or not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError("Invalid private request directory.")
    try:
        os.unlink(os.path.join(directory, "request.json"))
    except FileNotFoundError:
        pass
    os.rmdir(directory)


def main(args):
    if args == ["connectivity"]:
        state = NetworkManager().props(ROOT, SERVICE)
        print({0: "unknown", 1: "none", 2: "portal", 3: "limited", 4: "full"}.get(
            state.get("Connectivity", 0), "unknown") if state.get("ConnectivityCheckEnabled") else "unknown")
        return
    if args == ["prepare"]:
        print(tempfile.mkdtemp(prefix="monarch-wifi-", dir=os.environ.get("XDG_RUNTIME_DIR")))
        return
    if len(args) == 2 and args[0] == "discard":
        if os.path.lexists(args[1]):
            discard(args[1])
        return
    if args and args[0] == "connect":
        if len(args) != 3 or args[2] not in ("saved", "password-stdin"):
            raise ValueError("Usage: monarch-wifi-join <ssid> [--password-stdin]")
        nm = NetworkManager()
        rows = [r for r in nm.snapshot()["networks"] if r["ssid"] == args[1]]
        if not rows:
            raise ValueError("This network is not in range.")
        if len({r["uuid"] for r in rows}) > 1 or len({r["security"] for r in rows}) > 1:
            raise ValueError("Several networks match; select the intended network in the panel.")
        request = dict(rows[0])
        if args[2] == "password-stdin":
            request["password"] = sys.stdin.read(4097).removesuffix("\n")
            if len(request["password"]) > 4096:
                raise ValueError("Password too long.")
        nm.join(request)
        return
    if len(args) == 2 and args[0] == "join":
        request = read_request(args[1])
        NetworkManager().join(request)
    elif args in (["list"], ["list", "--rescan"]):
        print(json.dumps(NetworkManager().snapshot(len(args) == 2)))
    elif len(args) == 2 and args[0] == "forget":
        nm = NetworkManager()
        path, settings = nm.profile(args[1])
        if settings.unpack().get("connection", {}).get("type") != "802-11-wireless":
            raise ValueError("This is not a Wi-Fi profile.")
        nm.call(path, CONNECTION, "Delete")
    elif len(args) == 3 and args[0] == "disconnect":
        NetworkManager().disconnect(args[1], args[2])
    else:
        raise ValueError("Usage: monarch-wifi-panel prepare|list [--rescan]|join <request>|forget <uuid>|disconnect <interface> <uuid>")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except GLib.Error as error:
        # D-Bus errors can quote rejected settings, including a submitted secret.
        name = Gio.DBusError.get_remote_error(error) or "D-Bus request failed"
        print("NetworkManager: " + name, file=sys.stderr)
        sys.exit(1)
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print(str(error) if isinstance(error, ValueError) else "Network operation failed or timed out.", file=sys.stderr)
        sys.exit(1)
