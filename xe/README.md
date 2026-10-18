# Xe: private reservation lock during buffer destruction

[`xe-private-reservation.patch`](xe-private-reservation.patch) corrects a lock/unlock mismatch in `xe_ttm_bo_release_notify()`. It is a source patch for a manual, kernel-specific rebuild. The fix-pack installer is unchanged.

## Bug and affected builds

For imported dma-bufs, `base.resv` can point to an external reservation while `base._resv` holds the private fence copy used during destruction. The affected callback locks `base.resv`, modifies `_resv`, then unlocks `_resv`. This can leave the external reservation locked and TTM cleanup workers blocked.

The mismatch was confirmed in source and stock-module disassembly for these exact Valve builds:

| Kernel release | Source commit |
|---|---|
| `7.2.4-valve1-1-neptune-72-g5ab4af5e2eb9` | [`5ab4af5e2eb942863190be262cc48b134b7cd6d6`](https://github.com/evlaV/linux-integration/tree/5ab4af5e2eb942863190be262cc48b134b7cd6d6) |
| `7.2.7-valve2-1-neptune-72-g31504582a073` | [`31504582a07316ae0e8a8fb3b8fdc39d94842816`](https://github.com/evlaV/linux-integration/tree/31504582a07316ae0e8a8fb3b8fdc39d94842816) |

The patch locks the private reservation and returns if trylock fails:

```c
if (WARN_ON(!dma_resv_trylock(&ttm_bo->base._resv)))
	return;
```

[Thomas Hellström's review](https://lists.openwall.net/linux-kernel/2026/07/07/1436) identifies the incorrect external lock. The [upstream private-fence fix](https://github.com/torvalds/linux/commit/fe3ccd24138fd391ae8e32289d492c85f67770fc) explains why destruction uses `_resv`.

## Verification

Before the correction, stock `7.2.7-valve2` showed ten blocked TTM delayed-delete workers, including:

```text
Workqueue: ttm ttm_bo_delayed_delete [ttm]
 __ww_mutex_lock.constprop.0+0x7d2/0xd10
 ttm_bo_delayed_delete+0x40/0x90 [ttm]
```

Both exact source commits accept the patch. Rebuilt-module disassembly confirms matching private-reservation lock/unlock and the return on lock failure.

After installing and rebooting `7.2.7-valve2`, all 15 postboot checks passed, including the loaded module identity/checksum, initramfs checksum, DMC v2.20, `enable_dsb=0`, and read-only protection. Three Wayland, three X11 and one nested Gamescope Vulkan cube runs completed successfully, each rendering 120 frames on Intel PTL. No blocked TTM cleanup workers or TTM hang messages were observed after those runs. The earlier patched `7.2.4-valve1` build also passed Wayland/X11/nested Gamescope rendering checks.

## Manual rebuild

Use the exact source commit and matching signed `linux-neptune-72-headers` package from the [SteamOS mirror](https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/). Verify package signatures against the SteamOS keyrings, match `.config` to `/proc/config.gz`, and use the package's `.BUILDINFO` tool versions: GCC `16.1.1 20260625`, binutils `2.46.1`, make `4.4.1`, pahole `1.31`.

Apply with `git apply --check` followed by `git apply`. An external-module build needs matching Xe/i915 source directories available through the prepared header tree for trace/shared-display includes. Compare module ABI metadata with stock and inspect the corrected function. Keep the original packaged module intact and run `depmod` for the target release after installing a version-specific override.

## Boot integration, recovery and updates

For early Xe loading, rebuild and inspect the initramfs with the replacement module, dependencies, `options xe enable_dsb=0`, and `/usr/lib/firmware/updates/i915/xe3lpd_dmc.bin.zst` containing DMC v2.20. Root-filesystem copies alone do not cover early loading.

Keep a verified stock-driver kernel/initramfs and boot entry. Rollback uses that entry, removes the custom override/early-load configuration, then reruns `depmod` and rebuilds the normal image. Re-evaluate source after each SteamOS update and rebuild only if the correction remains necessary; module binaries are specific to their kernel release.

The patch modifies MIT-licensed `xe_bo.c` under the same license.
