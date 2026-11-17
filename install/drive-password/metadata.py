#!/usr/bin/python3

import hashlib
import json
import os
import re
import struct
import sys


def inspect_header(path, expected_uuid):
    # cryptsetup lib/luks1/luks.h: network byte order, 208-byte prefix, eight 48-byte slots.
    fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    try:
        header = os.pread(fd, 1024, 0)
    finally:
        os.close(fd)
    if len(header) != 1024 or header[:6] != b"LUKS\xba\xbe":
        raise ValueError("Incomplete or invalid LUKS header")
    version = struct.unpack_from(">H", header, 6)[0]
    if version == 2:
        return {"version": 2}
    if version != 1:
        raise ValueError("Unsupported LUKS header version")

    uuid = header[168:208].split(b"\0", 1)[0].decode("ascii")
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", uuid) or uuid != expected_uuid:
        raise ValueError("LUKS1 UUID does not match the selected drive")
    for start in (8, 40, 72):
        field = header[start:start + 32]
        if b"\0" not in field or not field.split(b"\0", 1)[0]:
            raise ValueError("Invalid LUKS1 cipher/hash field")
    payload, key_bytes = struct.unpack_from(">II", header, 104)
    if key_bytes == 0 or struct.unpack_from(">I", header, 164)[0] == 0:
        raise ValueError("Invalid LUKS1 key size or digest iterations")
    area_sectors = (key_bytes * 4000 + 511) // 512
    if area_sectors * 512 > 0x1000000:
        raise ValueError("LUKS1 key area exceeds the supported cryptsetup bound")

    slots, areas = {}, []
    common = hashlib.sha256(header[:208]).hexdigest()
    for number in range(8):
        entry = header[208 + number * 48:256 + number * 48]
        active, iterations, salt, offset, stripes = struct.unpack(">II32sII", entry)
        if active not in (0x0000DEAD, 0x00AC71F3):
            raise ValueError("Invalid LUKS1 slot activation marker")
        if stripes != 4000 or offset * 512 < 1024:
            raise ValueError("Invalid LUKS1 key area")
        if payload and offset + area_sectors > payload:
            raise ValueError("LUKS1 key area crosses the data boundary")
        areas.append((offset, offset + area_sectors))
        if active == 0x00AC71F3:
            if iterations == 0:
                raise ValueError("Invalid LUKS1 slot iterations")
            slots[str(number)] = {
                "type": "luks1",
                "header": common,
                "entry": hashlib.sha256(entry).hexdigest(),
            }
    areas.sort()
    if any(left[1] > right[0] for left, right in zip(areas, areas[1:])):
        raise ValueError("Overlapping LUKS1 key areas")
    if not slots:
        raise ValueError("LUKS1 has no active key slot")
    return {"version": 1, "slots": slots}


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Expected a header path and UUID")
        print(json.dumps(inspect_header(sys.argv[1], sys.argv[2]), sort_keys=True))
    except (OSError, ValueError, UnicodeError, struct.error) as error:
        print(f"Could not inspect LUKS metadata: {error}", file=sys.stderr)
        sys.exit(1)
