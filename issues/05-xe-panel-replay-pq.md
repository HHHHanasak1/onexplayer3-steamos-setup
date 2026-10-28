# xe/PTL eDP Panel Replay with PQ HDR: panel freezes (MSA colorimetry bit) and shows new frames at 30 Hz (FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE)

**Target:** drm/xe (gitlab.freedesktop.org/drm/xe/kernel)

**Setup**
- ONE-NETBOOK ONEXPLAYER 3, Panther Lake, Arc B390 `8086:b080` rev 04, BIOS 5.09
- Kernel 7.2.7-valve2-2-neptune-72 (SteamOS, xe with the i915 display code), DMC `xe3lpd_dmc.bin` v2.20 (same with v2.36)
- eDP panel Samsung SDC AMS881KB01-0 (EDID model 17153), HBR3 x2, 144 Hz, VRR range 30-144
- Sink: Panel Replay with SU and Early Transport (DPCD 0xb0-0xb3 = `07 20 80 07`), AUX-less ALPM. The driver runs Panel Replay SU + ET with AS SDP
- gamescope sends PQ HDR (BT.2020 colorimetry + HDR metadata) while an HDR game runs. SDR and gamescope's gamma-2.2 HDR path are fine

Both problems below show up only with Panel Replay active. With `i915_edp_psr_debug` = 0x1 neither happens. To test, we built xe with a module parameter for each change and always entered Panel Replay through a normal full modeset (starting an HDR game). Toggling PSR through debugfs at runtime gives misleading results here (see the note at the end).

## 1. Panel keeps its stored frame with BT.2020 (MSA MISC1 bit 6)

For BT.2020 `intel_ddi_set_dp_msa()` sets `DP_MSA_MISC_COLOR_VSC_SDP` (`TRANS_MSA_MISC_A` = 0x4041). With Panel Replay active the panel then stops taking new frames. Sink status 0x2022 = 0x0a ("active, display from RFB") and the screen stays black, or frozen on the last SDR frame.

Clearing only that bit right after `intel_ddi_set_dp_msa()` (0x4041 → 0x0041) fixes it. The picture and colours are correct, so the panel reads the colorimetry from the VSC SDP anyway. With the bit still set, turning off `PIPE_MISC_HDR_MODE_PRECISION` or the PR CRC verification does not help. With PSR/PR off the bit made no visible difference in our test.

## 2. New frames at 30 Hz with FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE

With 1 fixed, PQ often looks very stuttery while gamescope and the game report steady 120-144 fps.

Measurement: a phone filmed the panel at 120 fps while a virtual mouse panned the camera at a constant speed in Cyberpunk 2077.
- In the bad state the image moved only on every 4th camera frame: about 27 Hz, 33 px jumps, some gaps of 8-20 frames.
- After a suspend/resume it moved on every camera frame (6.9 px steps, at least 117 Hz).

The source side is the same in both states:
- vblank timestamps 6.945 ms, no skips
- `PSR2_SU_STATUS` SU block counts per frame during the pan
- the display MMIO range 0x40000-0xA0000
- the sink DPCD

Link training writes `DP_DOWNSPREAD_CTRL` (0x107) = 0xc0 (`MSA_TIMING_PAR_IGNORE_EN | FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE`). The AS SDP is sent (DIP enabled) with header `09 02 22 00` (type 0x22, rev 2, length 9) and fixed-vtotal mode with vtotal 1320, which matches 144 Hz.

| 0x107 at link training | result |
|---|---|
| 0xc0 (stock) | about 30 Hz |
| 0x40 (no MSA ignore) | about 30 Hz |
| 0x00 | smooth |
| 0x80 (no FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE) | smooth on every modeset, relaunch and resume |

Reverse checks: going back from 0x00 to 0x40 gave about 30 Hz again. On the stock module 0xc0 stutters and 0x80 is smooth.

Writing 0x107 at runtime has no effect. The sink seems to latch it at link training. So the panel appears to time its refresh from RFB on its own (VRR minimum 30 Hz) instead of following the AS SDP or the SU updates.

Open points:
- With stock 0xc0, PQ HDR modesets give 30 Hz every time, but a suspend/resume always gives full rate until the next modeset. Power-cycling the panel through PPS (screen off, `PP_STATUS` = 0 for 4 s) does not reset it. We have not found what resume does differently.
- In SDR / gamma-2.2 mode a normal full modeset with PR re-entry is fine. Re-enabling PR through debugfs (`psr_debug` 0x1 → 0) gives the 30 Hz state there too. We have not tested whether 0x80 fixes that case.

We don't know whether this is a panel quirk or how the sink should treat the bit. A per-panel quirk (or not setting `FIXED_VTOTAL_AS_SDP_EN_IN_PR_ACTIVE` while VRR is not enabled) would fix it for this device.

## Workaround in use

A small out-of-tree module with kprobes on 7.2.7-valve2-2 clears both bits:
- MSA bit 6 after `intel_ddi_set_dp_msa()`
- bit 6 of the 0x107 write in `drm_dp_dpcd_write()` on AUX A

PQ HDR now works with Panel Replay on: no black or frozen screen, full frame rate, through game launches, relaunches and suspend/resume. Source: https://github.com/HHHHanasak1/onexplayer3-steamos-setup/tree/main/xehdrfix

We can provide register dumps, DPCD dumps, the camera clips and the analysis script.

**Filed:** https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/9692
