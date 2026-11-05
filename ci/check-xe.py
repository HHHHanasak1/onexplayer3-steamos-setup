#!/usr/bin/env python3
"""Checks a kernel's xe.ko against the code the two modules hook, before they get published.

check-xe.py <xe.ko> <xevmafix.c> <xehdrfix.c> [Module.symvers]

- xevmafix: the byte signatures in xevmafix.c (the module compares the same bytes at load time and refuses on a
  mismatch) must match xe_vma_ops_alloc / xe_vma_ops_fini at their offsets. Signatures avoid relocated bytes, so the
  unlinked .ko holds the same bytes as the loaded code.
- xehdrfix: every probed symbol must exist (in xe.ko, or exported per Module.symvers).
Exits 1 on any mismatch.
"""
import re
import struct
import sys


def elf_symbols(path):
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        sys.exit(f'{path}: not a 64-bit little-endian ELF')
    shoff, = struct.unpack_from('<Q', data, 0x28)
    shentsize, shnum = struct.unpack_from('<HH', data, 0x3a)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize) for i in range(shnum)]
    symbols = {}
    for sh in sections:
        if sh[1] != 2:  # SHT_SYMTAB
            continue
        strtab = sections[sh[6]]
        for off in range(sh[4], sh[4] + sh[5], 24):
            name, info, _other, shndx, value, size = struct.unpack_from('<IBBHQQ', data, off)
            if (info & 0xf) != 2 or shndx == 0 or shndx >= len(sections):  # STT_FUNC, defined
                continue
            end = data.index(b'\0', strtab[4] + name)
            symbols[data[strtab[4] + name:end].decode()] = (sections[shndx][4] + value, size)
    return data, symbols


def signatures(source):
    text = open(source).read()
    offsets = {m[1].lower(): int(m[2], 0) for m in re.finditer(r'#define (\w+)_SIGNATURE_OFFSET\s+(0x[0-9a-fA-F]+|\d+)', text)}
    for m in re.finditer(r'static const u8 (\w+)_signature\[\]\s*=\s*\{(.*?)\};', text, re.S):
        name = m[1]
        body = re.sub(r'/\*.*?\*/|//[^\n]*', '', m[2], flags=re.S)
        sig = bytes(int(b, 0) for b in re.findall(r'0x[0-9a-fA-F]+', body))
        function = {'alloc': 'xe_vma_ops_alloc', 'fini': 'xe_vma_ops_fini'}[name.split('_')[0]]
        yield name, function, offsets[name], sig


def main():
    xe, vmafix, hdrfix = sys.argv[1:4]
    symvers = sys.argv[4] if len(sys.argv) > 4 else None
    data, symbols = elf_symbols(xe)
    ok = True
    found = 0
    for name, function, offset, sig in signatures(vmafix):
        found += 1
        if function not in symbols:
            print(f'xevmafix: {function} missing from xe.ko')
            ok = False
            continue
        start, size = symbols[function]
        got = data[start + offset:start + offset + len(sig)]
        if offset + len(sig) > size or got != sig:
            print(f'xevmafix: {name} differs at {function}+{offset:#x}: expected {sig.hex(" ")}, got {got.hex(" ")}')
            ok = False
        else:
            print(f'xevmafix: {name} matches at {function}+{offset:#x}')
    if found < 3:
        print(f'xevmafix: only {found} signatures parsed from {vmafix}')
        ok = False
    exported = set()
    if symvers:
        exported = {line.split('\t')[1] for line in open(symvers) if '\t' in line}
    for sym in re.findall(r'symbol_name\s*=\s*"(\w+)"', open(hdrfix).read()):
        if sym in symbols or sym in exported:
            print(f'xehdrfix: {sym} present')
        else:
            print(f'xehdrfix: {sym} missing')
            ok = False
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
