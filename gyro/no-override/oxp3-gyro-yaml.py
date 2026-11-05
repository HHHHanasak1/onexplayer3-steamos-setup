import re
import sys

MARK = re.compile(r"^(\s*)name: .*bmi260.*$")
OWN_KEYS = ("sample_rate:", "mount_matrix:", "x:", "y:", "z:")


def find_mark(lines):
    hits = [i for i, line in enumerate(lines) if MARK.match(line)]
    if len(hits) != 1:
        sys.exit(f"expected one IIO name line mentioning bmi260, found {len(hits)}")
    return hits[0]


def strip_block(lines, mark):
    indent = len(MARK.match(lines[mark]).group(1))
    end = mark + 1
    while end < len(lines):
        stripped = lines[end].strip()
        deeper = len(lines[end]) - len(lines[end].lstrip()) >= indent
        if stripped and deeper and stripped.startswith(OWN_KEYS):
            end += 1
            continue
        break
    return lines[:mark + 1] + lines[end:]


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("ensure", "remove"):
        sys.exit("usage: oxp3-gyro-yaml.py ensure <yaml> <block> | remove <yaml>")
    path = sys.argv[2]
    with open(path) as f:
        original = f.read()
    lines = original.splitlines()
    mark = find_mark(lines)
    lines = strip_block(lines, mark)
    if sys.argv[1] == "ensure":
        with open(sys.argv[3]) as f:
            block = f.read().rstrip("\n").splitlines()
        lines = lines[:mark + 1] + block + lines[mark + 1:]
    updated = "\n".join(lines) + "\n"
    if updated == original:
        return
    with open(path, "w") as f:
        f.write(updated)
    print(f"oxp3-gyro: updated {path}")


main()
