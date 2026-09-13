import os
import re
import stat
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit


MAX_PAGE_BYTES = 524288
HTML_SPACE = " \t\n\r\f"


def clean_url(value):
  return bool(value) and not any(
    char.isspace() or ord(char) < 32 or 127 <= ord(char) <= 159
    for char in value
  )


def http_url(value):
  if not clean_url(value):
    return False
  try:
    parts = urlsplit(value)
    authority = parts.netloc.rsplit("@", 1)[-1]
    if authority.startswith("[") and not re.fullmatch(r"\[[^\[\]]+\](?::[0-9]+)?", authority):
      return False
    return (
      parts.scheme.lower() in ("http", "https")
      and bool(parts.netloc)
      and bool(parts.hostname)
      and "\\" not in parts.netloc
      and not parts.netloc.endswith(":")
      and (parts.port is None or 0 <= parts.port <= 65535)
    )
  except ValueError:
    return False


def resolve_url(base, value):
  value = value.strip(HTML_SPACE)
  if not clean_url(value):
    return None
  try:
    parts = urlsplit(value)
    if parts.scheme:
      return value if http_url(value) else None
    if value.startswith("//") and not parts.netloc:
      return None
    resolved = urljoin(base, value)
    return resolved if http_url(resolved) else None
  except ValueError:
    return None


def icon_size(value):
  largest = 0
  for token in value.split():
    match = re.fullmatch(r"([0-9]{1,9})[xX]([0-9]{1,9})", token)
    if match:
      largest = max(largest, int(match[1]) * int(match[2]))
  return largest


class IconLinks(HTMLParser):
  def __init__(self, page_url):
    super().__init__(convert_charrefs=True)
    self.page_url = page_url
    self.base_url = None
    self.links = []

  def handle_starttag(self, tag, attrs):
    attributes = {}
    for name, value in attrs:
      attributes.setdefault(name, value or "")
    href = attributes.get("href", "")
    if tag == "base" and self.base_url is None:
      self.base_url = resolve_url(self.page_url, href)
    elif tag == "link" and href:
      rel = set(attributes.get("rel", "").lower().split())
      if rel & {"apple-touch-icon", "apple-touch-icon-precomposed"}:
        priority = 0
      elif "icon" in rel:
        priority = 1
      else:
        return
      self.links.append((priority, -icon_size(attributes.get("sizes", "")), href))

  def urls(self):
    seen = set()
    for _, _, href in sorted(self.links, key=lambda link: link[:2]):
      resolved = resolve_url(self.base_url or self.page_url, href)
      if resolved is not None and resolved not in seen:
        seen.add(resolved)
        yield resolved
        if len(seen) == 3:
          return


def main():
  if len(sys.argv) != 3:
    print("Usage: webapp-icon-links.py PAGE_FILE EFFECTIVE_PAGE_URL", file=sys.stderr)
    return 2
  if not http_url(sys.argv[2]):
    print("Invalid effective page URL", file=sys.stderr)
    return 1
  try:
    if not stat.S_ISREG(os.stat(sys.argv[1]).st_mode):
      raise ValueError("Page must be a regular file")
    with open(sys.argv[1], "rb") as page:
      if os.fstat(page.fileno()).st_size > MAX_PAGE_BYTES:
        raise ValueError("Page exceeds 512 KiB")
      content = page.read(MAX_PAGE_BYTES)
      if os.fstat(page.fileno()).st_size > MAX_PAGE_BYTES:
        raise ValueError("Page exceeds 512 KiB")
    parser = IconLinks(sys.argv[2])
    parser.feed(content.decode("utf-8", errors="replace"))
    parser.close()
    for url in parser.urls():
      print(url)
  except (OSError, ValueError, AssertionError) as error:
    print(f"Cannot parse page: {error}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  sys.exit(main())
