import re
import sys


def format_ports(source, color=False):
    rows = []
    for line in source.splitlines():
        fields = line.split(None, 6)
        if len(fields) < 6 or fields[0] not in ("tcp", "udp"):
            continue
        address, separator, port = fields[4].rpartition(":")
        if not separator or not port.isdecimal():
            continue
        processes = re.findall(r'"((?:\\.|[^"\\])*)",pid=(\d+)', fields[6] if len(fields) > 6 else "")
        processes = list(dict.fromkeys(processes))
        rows.append((fields[0].upper(), str(int(port)), address,
                     ", ".join(name for name, pid in processes) or "—",
                     ", ".join(pid for name, pid in processes) or "—"))
    rows.sort(key=lambda row: (int(row[1]), row[0], row[2], row[3], row[4]))
    headers = ("PROTO", "PORT", "LOCAL ADDRESS", "PROCESS", "PID")
    widths = [max(len(row[index]) for row in [headers, *rows]) for index in range(len(headers))]
    lines = []
    for index, row in enumerate([headers, *rows]):
        cells = [cell.ljust(widths[column]) if column < len(row) - 1 else cell
                 for column, cell in enumerate(row)]
        if color:
            if index == 0:
                cells = [f"\033[2m{cell}\033[0m" for cell in cells]
            else:
                code = "36" if row[0] == "TCP" else "33"
                cells[0] = f"\033[{code}m{cells[0]}\033[0m"
                cells[1] = f"\033[1m{cells[1]}\033[0m"
        lines.append("  ".join(cells))
    if not rows:
        lines.append("No listening TCP or UDP sockets.")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    sys.stdout.write(format_ports(sys.stdin.read(), color="--color" in sys.argv[1:]))
