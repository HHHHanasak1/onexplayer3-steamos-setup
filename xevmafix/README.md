# xevmafix: games survive waking from sleep

Step 15 of the fix pack. Without it, FF7 Rebirth (and probably any big game) freezes about 2 seconds after the OXP3 wakes from sleep and says it's out of memory. It isn't. It had 11-16 GB free every time.

## What's wrong

On Panther Lake xe moves every GPU buffer out of the GPU's view on suspend. On wake the first submit has to rebind every mapping at once and `xe_vma_ops_alloc()` asks `kmalloc` for one 384-byte entry per mapping in a single block. FF7R has about 33,500 mappings which means 12.9 MB. `kmalloc` tops out at 4 MB which means it can never succeed. Mesa keeps retrying and gives up with `intel: the execbuf ioctl keeps returning ENOMEM`.

Proof from kretprobes after resume on kernel 7.2.7:
- `xe_vma_ops_alloc` returned -ENOMEM 63 out of 63 times
- nothing else in the bind path failed (BO validate, TTM populate, page-table prepare)
- it happened 6 out of 6 times, even on a 25 second sleep and with stock SteamOS Mesa

## What the module does

It swaps that one allocation for `kvmalloc` (and the matching free for `kvfree`), which falls back to vmalloc when the block is too big. The array is only used by the CPU and doesn't need to be contiguous. Intel's drm-xe-next already does the same thing.

It does that with two kprobes, on `xe_vma_ops_alloc` and `xe_vma_ops_fini`. Before it touches anything it compares the code at both spots byte for byte against the kernel it was built for and refuses to load if they differ. It can't be unloaded which means turning it off takes a reboot.

After the fix: zero ENOMEM across every sleep since, including real wakes with FF7R open. On one boot it handled 2,337 oversized rebinds, the biggest 30,753 entries (11.8 MB).

## Building

The `.ko` only loads on the exact kernel it was built for. `build.sh` builds it on the device in an Arch container that uses the SteamOS package repositories and their `linux-neptune-72-headers`:

```
mkdir -p ~/xevmafix-build && cp xevmafix.c Makefile ~/xevmafix-build/ && ./build.sh
```

It prints the kernel the module is for and its sha256. Those two go into `XEVMA_FOR` and `XEVMA_SHA256` in the script and the `.ko` goes into the release archive. A rebuild of the shipped 7.2.7 module gives the same machine code as the tested one.

If a new kernel changes those two functions, the byte check refuses to load and the offsets in `xevmafix.c` need a look.

## Upstream

- Kernel patch sent to intel-xe: "drm/xe: Use kvmalloc for the VMA ops page-table update array" (Fixes `2e524668c440`, Cc stable)
- SteamOS: https://github.com/ValveSoftware/SteamOS/issues/2962

Once a SteamOS kernel ships the fix, this step can go.

The module is GPL-2.0 (`MODULE_LICENSE("GPL")`), since it's a Linux kernel module.
