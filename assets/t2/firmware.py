#!/usr/bin/python3

# SPDX-License-Identifier: MIT
# Derived from t2linux/wiki docs/tools/firmware.sh.
# Copyright (C) 2024 Aditya Garg, Orlando Chamberlain, Sharpened Blade

from __future__ import annotations

import argparse
import hashlib
import io
import os
import re
import tarfile
import time
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import PurePosixPath


WIFI_FOLDERS = {
    "C-4355__s-C1",
    "C-4364__s-B2",
    "C-4364__s-B3",
    "C-4377__s-B3",
}
WIFI_EXTENSIONS = {
    "trx": "bin",
    "txt": "txt",
    "clmb": "clm_blob",
    "txcb": "txcap_blob",
}
WIFI_DIMENSIONS = ["C", "s", "P", "M", "V", "m", "A"]
BLUETOOTH_VENDORS = {"MUR": "m", "USI": "u", "GEN": None}
MAX_MEMBER_SIZE = 128 * 1024 * 1024
MAX_ARCHIVE_SIZE = 2 * 1024 * 1024 * 1024
MAX_TOTAL_SIZE = 4 * 1024 * 1024 * 1024
MAX_MEMBERS = 100_000


@dataclass(frozen=True)
class FirmwareFile:
    name: str
    data: bytes

    @property
    def digest(self) -> str:
        return hashlib.sha256(self.data).hexdigest()


@dataclass
class FirmwareNode:
    current: FirmwareFile | None = None
    children: dict[str, "FirmwareNode"] = field(default_factory=dict)

    def signature(self):
        return (
            self.current.digest if self.current else None,
            tuple((key, child.signature()) for key, child in self.children.items()),
        )


def archive_files(path: str) -> dict[str, bytes]:
    if os.path.getsize(path) > MAX_ARCHIVE_SIZE:
        raise ValueError("firmware archive is too large")

    files: dict[str, bytes] = {}
    total_size = 0
    with tarfile.open(path, "r:*") as archive:
        for index, member in enumerate(archive, start=1):
            if index > MAX_MEMBERS:
                raise ValueError("firmware archive contains too many entries")
            if not member.isfile():
                continue
            if member.size > MAX_MEMBER_SIZE:
                raise ValueError(f"firmware member is too large: {member.name}")
            total_size += member.size
            if total_size > MAX_TOTAL_SIZE:
                raise ValueError("firmware archive expands beyond the size limit")
            name = member.name.removeprefix("./")
            parts = PurePosixPath(name).parts
            if not parts or name.startswith("/") or ".." in parts:
                raise ValueError(f"unsafe firmware path: {member.name}")
            source = archive.extractfile(member)
            if source is None:
                raise ValueError(f"could not read firmware member: {member.name}")
            files[name] = source.read()
    return files


def clean_nvram(data: bytes) -> bytes:
    lines = []
    for line in data.decode("ascii").splitlines():
        if not line:
            continue
        key, value = line.split("=", 1)
        lines.append(f"{key.strip()}={value}\n")
    return "".join(lines).encode("ascii")


def parse_wifi(files: dict[str, bytes]) -> list[FirmwareFile]:
    root = FirmwareNode()
    for path, data in sorted(files.items()):
        parts = PurePosixPath(path).parts
        if len(parts) < 3 or parts[0] != "wifi" or parts[1] not in WIFI_FOLDERS:
            continue
        if "perf" in parts or "assert" in parts:
            continue

        filename = parts[-1]
        if "." not in filename:
            continue
        stem, extension = filename.rsplit(".", 1)
        if extension not in WIFI_EXTENSIONS:
            continue
        if extension != "txt":
            stem = f"P-{stem}"

        identifier_path = "/".join((*parts[1:-1], stem))
        properties: dict[str, str] = {}
        for token in identifier_path.replace("/", "_").split("_"):
            if not token:
                continue
            key, value = token.split("-", 1)
            if key == "P" and "-" in value:
                platform, antenna = value.split("-", 1)
                properties["P"] = platform
                properties["A"] = antenna
            else:
                properties[key] = value

        identity = [extension]
        for dimension in WIFI_DIMENSIONS:
            value = properties.pop(dimension, None)
            if value is not None:
                identity.append(value)
        if properties:
            raise ValueError(f"unsupported Wi-Fi firmware properties in {path}")

        node = root
        for key in identity:
            node = node.children.setdefault(key, FirmwareNode())
        payload = clean_nvram(data) if extension == "txt" else data
        node.current = FirmwareFile(path, payload)

    prune_wifi(root)
    output: list[FirmwareFile] = []
    walk_wifi(root, [], output)
    return output


def prune_wifi(node: FirmwareNode, depth: int = 0) -> None:
    for child in node.children.values():
        prune_wifi(child, depth + 1)

    if node.current is None and node.children and depth > 3:
        children = list(node.children.values())
        if all(child.signature() == children[0].signature() for child in children):
            node.current = children[0].current

    if node.current and node.children and all(
        child.current and child.current.digest == node.current.digest
        for child in node.children.values()
    ):
        node.children = {}


def walk_wifi(node: FirmwareNode, identity: list[str], output: list[FirmwareFile]) -> None:
    if node.current:
        if len(identity) < 3:
            raise ValueError(f"incomplete Wi-Fi firmware identity: {node.current.name}")
        extension, chip, revision, *rest = identity
        suffix = f",{'-'.join(rest)}" if rest else ""
        name = (
            f"brcmfmac{chip}{revision.lower()}-pcie.apple{suffix}."
            f"{WIFI_EXTENSIONS[extension]}"
        )
        output.append(FirmwareFile(name, node.current.data))
    for key, child in node.children.items():
        walk_wifi(child, [*identity, key], output)


def parse_bluetooth_name(stem: str):
    tokens = stem.split("_")
    match = re.fullmatch(r"bcm(43[0-9]{2})([a-z][0-9])", tokens[0].lower())
    if not match or "PCIE" not in tokens:
        return None
    chip, stepping = match.groups()
    offset = tokens.index("PCIE")
    if offset + 1 >= len(tokens):
        return None
    board_offset = offset + 2 if tokens[offset + 1] == "macOS" else offset + 1
    if board_offset >= len(tokens):
        return None
    board = tokens[board_offset].removesuffix("ES2").lower()
    vendors = {value for key, value in BLUETOOTH_VENDORS.items() if key in tokens}
    if len(vendors) != 1:
        return None
    return chip, stepping, board, vendors.pop()


def parse_bluetooth(files: dict[str, bytes]) -> list[FirmwareFile]:
    pairs: dict[tuple[str, str, str, str | None], list[FirmwareFile | None]] = defaultdict(
        lambda: [None, None]
    )
    for path, data in sorted(files.items()):
        parts = PurePosixPath(path).parts
        if len(parts) != 2 or parts[0] != "bluetooth":
            continue
        stem, extension = PurePosixPath(path).stem, PurePosixPath(path).suffix
        if "_DEV" in stem or extension not in {".bin", ".ptb"}:
            continue
        identity = parse_bluetooth_name(stem)
        if identity is None:
            continue
        pairs[identity][0 if extension == ".bin" else 1] = FirmwareFile(path, data)

    output: list[FirmwareFile] = []
    for (chip, stepping, board, vendor), (binary, parameters) in pairs.items():
        base = f"brcmbt{chip}{stepping}-apple,{board}"
        if vendor:
            base += f"-{vendor}"
        if binary:
            output.append(FirmwareFile(f"{base}.bin", binary.data))
        if parameters:
            output.append(FirmwareFile(f"{base}.ptb", parameters.data))
    return output


def verify(path: str) -> None:
    files = archive_files(path)
    wifi = parse_wifi(files)
    if not wifi:
        raise ValueError("archive contains no supported T2 Wi-Fi firmware")
    print(f"{len(wifi)} Wi-Fi and {len(parse_bluetooth(files))} Bluetooth files")


def collect_firmware(source: str) -> list[FirmwareFile]:
    files = archive_files(source)
    firmware = sorted((*parse_wifi(files), *parse_bluetooth(files)), key=lambda item: item.name)
    if not any(item.name.startswith("brcmfmac") for item in firmware):
        raise ValueError("archive contains no supported T2 Wi-Fi firmware")
    return firmware


def add_payload(
    archive: tarfile.TarFile,
    firmware: list[FirmwareFile],
    prefix: str = "",
) -> None:
    known: dict[str, str] = {}
    for item in firmware:
        name = f"{prefix}{item.name}"
        metadata = tarfile.TarInfo(name)
        metadata.mode = 0o644
        metadata.uid = metadata.gid = 0
        metadata.uname = metadata.gname = "root"
        if item.digest in known:
            metadata.type = tarfile.LNKTYPE
            metadata.linkname = known[item.digest]
            archive.addfile(metadata)
        else:
            metadata.size = len(item.data)
            archive.addfile(metadata, io.BytesIO(item.data))
            known[item.digest] = name


def normalize(source: str, destination: str) -> None:
    firmware = collect_firmware(source)

    with tarfile.open(destination, "w") as archive:
        add_payload(archive, firmware)
    print(f"wrote {len(firmware)} firmware files")


def package(source: str, destination: str) -> None:
    firmware = collect_firmware(source)
    installed_size = sum(len(item.data) for item in firmware)
    pkginfo = f"""pkgname = apple-bcm-firmware-local
pkgbase = apple-bcm-firmware-local
pkgver = 1-1
pkgdesc = Locally extracted Apple Broadcom firmware for T2 Macs
url = https://wiki.t2linux.org/guides/wifi-bluetooth/
builddate = {int(time.time())}
packager = Monarch local firmware extractor
size = {installed_size}
arch = any
license = LicenseRef-unknown
provides = apple-bcm-firmware
conflict = apple-bcm-firmware
""".encode()

    with tarfile.open(destination, "w:gz") as archive:
        metadata = tarfile.TarInfo(".PKGINFO")
        metadata.mode = 0o644
        metadata.uid = metadata.gid = 0
        metadata.uname = metadata.gname = "root"
        metadata.size = len(pkginfo)
        archive.addfile(metadata, io.BytesIO(pkginfo))
        add_payload(archive, firmware, "usr/lib/firmware/brcm/")
    print(f"built {destination}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("archive")
    normalize_parser = subparsers.add_parser("normalize")
    normalize_parser.add_argument("archive")
    normalize_parser.add_argument("output")
    package_parser = subparsers.add_parser("package")
    package_parser.add_argument("archive")
    package_parser.add_argument("output")
    args = parser.parse_args()

    if args.command == "verify":
        verify(args.archive)
    elif args.command == "normalize":
        normalize(args.archive, args.output)
    else:
        package(args.archive, args.output)


if __name__ == "__main__":
    main()
