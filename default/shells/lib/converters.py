import base64
import binascii
import os
import re
import subprocess
import sys
from urllib.parse import quote_from_bytes, unquote_to_bytes


def decode_base64url(data):
    data = b"".join(data.split())
    if not re.fullmatch(rb"[A-Za-z0-9_-]*={0,2}", data):
        raise ValueError("invalid Base64URL alphabet or padding")
    unpadded = data.rstrip(b"=")
    padding = -len(unpadded) % 4
    if padding == 3 or (data != unpadded and len(data) != len(unpadded) + padding):
        raise ValueError("invalid Base64URL length or padding")
    return base64.b64decode(unpadded + b"=" * padding, altchars=b"-_", validate=True)


def decode_url(data):
    if re.search(rb"%(?![0-9a-fA-F]{2})", data):
        raise ValueError("invalid percent escape")
    return unquote_to_bytes(data)


def utf16le(data):
    return data.decode("utf-8").encode("utf-16le")


def nt_hash(data):
    result = subprocess.run(
        ["openssl", "dgst", "-md4", "-provider", "legacy", "-binary"],
        input=utf16le(data), capture_output=True,
    )
    if result.returncode or len(result.stdout) != 16:
        raise ValueError("NT hashing requires OpenSSL's legacy MD4 provider")
    return result.stdout.hex().encode("ascii")


CONVERTERS = {
    "b64url": lambda data: base64.urlsafe_b64encode(data).rstrip(b"="),
    "b64urld": decode_base64url,
    "urlencode": lambda data: quote_from_bytes(data, safe="").encode("ascii"),
    "urldecode": decode_url,
    "toHex": binascii.hexlify,
    "fromHex": lambda data: binascii.unhexlify(b"".join(data.split())),
    "utf16le": utf16le,
    "utf16to8": lambda data: data.decode("utf-16le").encode("utf-8"),
    "nthash": nt_hash,
}


def main():
    if len(sys.argv) not in (2, 3) or sys.argv[1] not in CONVERTERS:
        print("Usage: <converter> [text] (otherwise reads stdin)", file=sys.stderr)
        return 2
    name = sys.argv[1]
    try:
        data = os.fsencode(sys.argv[2]) if len(sys.argv) == 3 else sys.stdin.buffer.read()
        converted = CONVERTERS[name](data)
    except (ValueError, OSError) as error:
        print(f"{name}: {error}", file=sys.stderr)
        return 1
    sys.stdout.buffer.write(converted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
