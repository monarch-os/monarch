# Shell converters

These helpers work in Bash and Zsh. Give exactly one text argument, or omit it
to read stdin. An explicitly empty argument is empty input, not a request to
read stdin. Multiple arguments are rejected rather than joined implicitly.
There are no option flags: `urlencode -n` encodes the literal text `-n`.

All helpers preserve input newlines and add none of their own. Use `printf %s`
instead of `echo` when a trailing newline is unwanted. Pipe binary data through
stdin: shell arguments and command substitutions cannot preserve arbitrary bytes.
Each call buffers its input; these helpers are for payloads, not large files.

## Available helpers

- `b64url`, `b64urld`: URL-safe Base64 with `-` and `_`. Encoding omits padding;
  decoding accepts correctly padded or unpadded input and ASCII whitespace.
  Invalid alphabets, lengths and padding fail.
- `urlencode`, `urldecode`: byte-preserving percent encoding. Encoding leaves only
  RFC 3986 unreserved characters unchanged. Spaces become `%20`; literal `+`
  stays `+` when decoding, not a space. Malformed percent escapes fail. These
  helpers operate on URL components, not complete URLs or HTML form bodies.
- `toHex`, `fromHex`: lowercase hexadecimal encoding and decoding. Hex decoding
  accepts ASCII whitespace, but not `0x` prefixes or `\xNN` notation.
- `utf16le`, `utf16to8`: strict UTF-8 ↔ UTF-16LE conversion. Encoding emits no
  byte-order mark. Decoding treats a leading byte-order mark as a character;
  it does not strip it. Invalid input fails rather than replacing characters.
- `nthash`: lowercase MD4 of the UTF-16LE representation of UTF-8 text, using
  OpenSSL's legacy provider. This is a legacy password hash for interoperability,
  not a recommendation for password storage. Keep real passwords out of shell
  history and command arguments; supply them through stdin.

Invalid input produces a nonzero exit status and a diagnostic on stderr, without
partial output. Python 3 is required; `nthash` also requires OpenSSL with MD4.
Existing `b64e` and `b64d` aliases keep their original GNU Base64 behavior.

## Examples

```bash
b64url 'hello?'
printf %s 'aGVsbG8_' | b64urld
urlencode 'a+b / café'
urldecode 'a%2Bb%20%2F%20caf%C3%A9'
printf '\000\377\n' | toHex | fromHex | xxd
printf %s 'Password1' | nthash
printf %s 'hello 🌍' | utf16le | utf16to8
```
