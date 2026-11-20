#!/usr/bin/env python3
"""Checks a kernel's xe.ko against the code the two modules hook, before they get published.

check-xe.py <xe.ko> <xevmafix.c> <xehdrfix.c> [Module.symvers]

- xevmafix: the byte signatures in xevmafix.c (the module compares the same bytes at load time and refuses on a
  mismatch) must match xe_vma_ops_alloc / xe_vma_ops_fini at their offsets. Signatures avoid relocated bytes, so the
  unlinked .ko holds the same bytes as the loaded code.
  When they do not match, the kernel may have the fix itself: newer xe drivers (7.2.15 on) allocate the per-tile
  rebind array with kvmalloc and free it with kvfree (xe_pt_job_ops_alloc / xe_pt_job_ops_put). Then xevmafix is
  not needed for that kernel.
- xehdrfix: every probed symbol must exist (in xe.ko, or exported per Module.symvers).
Exits 1 on any mismatch, 3 when xevmafix is not needed (the kernel allocates with kvmalloc) and xehdrfix matches,
0 when both modules match.
"""
import re
import struct
import subprocess
import sys


def relocations(path):
    """{function: set of relocated symbols} from objdump -dr."""
    out = subprocess.run(['objdump', '-dr', '--no-show-raw-insn', path], capture_output=True, text=True, check=True).stdout
    funcs, cur = {}, None
    for line in out.splitlines():
        m = re.match(r'^[0-9a-f]+ <([^>]+)>:$', line)
        if m:
            cur = funcs.setdefault(m[1], set())
            continue
        m = re.search(r'\sR_X86_64_\w+\s+([\w.]+)', line)
        if m and cur is not None:
            cur.add(m[1])
    return funcs


def reaches(funcs, function, wanted):
    """True when function, or a function of the same object it calls directly, relocates a symbol starting with
    one of wanted."""
    seen = {function} | {s for s in funcs.get(function, ()) if s in funcs}
    return any(s.startswith(wanted) for f in seen for s in funcs.get(f, ()))


def vma_ops_use_kvmalloc(path):
    funcs = relocations(path)
    return (reaches(funcs, 'xe_vma_ops_alloc', ('__kvmalloc_node', 'kvmalloc'))
            and reaches(funcs, 'xe_vma_ops_fini', ('kvfree',)))


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
    vma_ok = True
    found = 0
    for name, function, offset, sig in signatures(vmafix):
        found += 1
        if function not in symbols:
            print(f'xevmafix: {function} missing from xe.ko')
            vma_ok = False
            continue
        start, size = symbols[function]
        got = data[start + offset:start + offset + len(sig)]
        if offset + len(sig) > size or got != sig:
            print(f'xevmafix: {name} differs at {function}+{offset:#x}: expected {sig.hex(" ")}, got {got.hex(" ")}')
            vma_ok = False
        else:
            print(f'xevmafix: {name} matches at {function}+{offset:#x}')
    if found < 3:
        print(f'xevmafix: only {found} signatures parsed from {vmafix}')
        ok = False
    vma_not_needed = False
    if not vma_ok:
        if 'xe_vma_ops_alloc' in symbols and 'xe_vma_ops_fini' in symbols and vma_ops_use_kvmalloc(xe):
            print('xevmafix: not needed - xe_vma_ops_alloc allocates with kvmalloc and xe_vma_ops_fini frees with kvfree')
            vma_not_needed = True
        else:
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
    sys.exit(1 if not ok else 3 if vma_not_needed else 0)


if __name__ == '__main__':
    main()
