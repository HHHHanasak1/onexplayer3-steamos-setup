import struct
import subprocess
import sys

OLD_ID = b"BMI0160".ljust(16, b"\0")
NEW_ID = b"10EC5280".ljust(16, b"\0")
SIG_MAGIC = b"~Module signature appended~\n"
SIG_INFO_LEN = 12


def read_module(path):
    if path.endswith(".zst"):
        return subprocess.run(["zstd", "-dcq", path], check=True, capture_output=True).stdout
    if path.endswith(".xz"):
        return subprocess.run(["xz", "-dc", path], check=True, capture_output=True).stdout
    with open(path, "rb") as f:
        return f.read()


def strip_signature(data):
    if not data.endswith(SIG_MAGIC):
        return data
    info = data[-len(SIG_MAGIC) - SIG_INFO_LEN:-len(SIG_MAGIC)]
    sig_len = struct.unpack(">I", info[8:12])[0]
    return data[:-(len(SIG_MAGIC) + SIG_INFO_LEN + sig_len)]


def patch(data):
    if data[:4] != b"\x7fELF":
        sys.exit("not an ELF module")
    if data.count(NEW_ID) == 1 and data.count(OLD_ID) == 0:
        return data
    found = data.count(OLD_ID)
    if found != 1:
        sys.exit(f"expected exactly one BMI0160 ACPI id entry, found {found}")
    return data.replace(OLD_ID, NEW_ID)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: oxp3-gyro-patch.py <bmi270_i2c.ko[.zst]> <out.ko>")
    data = patch(strip_signature(read_module(sys.argv[1])))
    with open(sys.argv[2], "wb") as f:
        f.write(data)


main()
