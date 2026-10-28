# xehdrfix: PQ HDR on the OLED with Panel Replay

Step 16 of the fix pack. Without it, real HDR (PQ: BT.2020 with SMPTE ST 2084) doesn't work on the OXP3's Samsung AMS881KB01-0 OLED, so the gamescope lua falls back to the gamma-2.2 path. The lua checks for this module at every game mode start and uses PQ only while it's loaded.

## What's wrong

xe gets three things wrong for this panel when an HDR game switches it to PQ.

1. **Black or frozen panel (Panel Replay).** For BT.2020 xe sets MSA MISC1 bit 6 ("colorimetry is in the VSC SDP", `TRANS_MSA_MISC` 0x4041). With Panel Replay active the panel then stops taking new frames and keeps showing its stored frame (`display from RFB`). Clearing only that bit fixes it. The panel reads the colorimetry from the VSC SDP either way.
2. **New frames at only 30 Hz (Panel Replay).** At link training xe sets `FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE` in `DP_DOWNSPREAD_CTRL` (DPCD 0x107 = 0xc0). The panel then often runs on its own timing while Panel Replay is active and shows a new frame only at its VRR minimum, 30 Hz. The game and gamescope keep running at 120-144 fps, so the frame times look normal and it just looks badly stuttery. It stays like that until the next wake from sleep. With the bit cleared (0x107 = 0x80) it's smooth every time.
3. **Black panel after some switches to HDR (Panel Replay off too).** The VSC SDP header that `hsw_write_infoframe()` writes while the DIP is disabled sometimes keeps a bad ECC: on the first HDR switch after Panel Replay was active, and after waking from sleep. The panel drops the SDP and stays black. Writing the header dword again once the DIP is enabled makes the hardware compute the ECC again.

How 2 was measured: a phone filmed the panel at 120 fps while a virtual mouse turned the camera in Cyberpunk 2077 at a constant speed. In the bad state the picture moved only every 4th camera frame (about 27 Hz, 33 px jumps). After waking from sleep it moved on every frame (6.9 px steps). The source side was the same in both states: 144 Hz vblanks, the same selective-update blocks per frame, the same display registers and DPCD.

## What the module does

Three probes, all limited to the eDP panel:

- a kretprobe on `intel_ddi_set_dp_msa` clears MSA bit 6 when transcoder A drives DDI A
- a kretprobe on `hsw_write_infoframe` writes the VSC SDP header dword again once the VSC DIP is enabled
- a kprobe on `drm_dp_dpcd_write` clears bit 6 of a DPCD 0x107 write on `AUX A` (`intel_dp_link_training_set_mode()` is inlined in the SteamOS xe, so a probe on it never fires). xe sets that bit only for eDP with Panel Replay. The source still sends the AS SDP

`/sys/module/xehdrfix/parameters/counters` counts the three (`--check` prints them). Panel Replay and the rest of the driver stay as they are.

## Building

The `.ko` only loads on the exact kernel it was built for. `build.sh` builds it on the device in an Arch container that uses the SteamOS package repositories and their `linux-neptune-72-headers`:

```
mkdir -p ~/xehdrfix-build && cp xehdrfix.c Makefile ~/xehdrfix-build/ && ./build.sh
```

It prints the kernel the module is for and its sha256. Those two go into `XEHDR_FOR` and `XEHDR_SHA256` in the script and the `.ko` goes into the release archive.

## Upstream

Reported to drm/xe:
- [xe#9692](https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/9692): Panel Replay with PQ (MSA colorimetry bit, `FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE`)
- [xe#9693](https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/9693): VSC SDP dropped after some HDR modesets

Once a SteamOS kernel ships fixes for these, this step can go.

The module is GPL-2.0 (`MODULE_LICENSE("GPL")`), since it's a Linux kernel module.
