# xe/PTL eDP: BT.2020 VSC SDP dropped by the panel after some HDR modesets, fixed by writing the header dword again while the DIP is enabled

**Target:** drm/xe (gitlab.freedesktop.org/drm/xe/kernel)

**Setup:** same device as the Panel Replay report:
- ONEXPLAYER 3, Panther Lake Arc B390 `8086:b080`, kernel 7.2.7-valve2-2-neptune-72, DMC v2.20
- panel Samsung SDC AMS881KB01-0
- gamescope switches to PQ HDR (BT.2020 colorimetry in the VSC SDP) while an HDR game runs

This one happens with PSR and Panel Replay **off** (`i915_edp_psr_debug` = 0x1, which BIOS 5.11+ owners of this device need anyway because of xe#8924).

**Symptom:** after some switches to HDR the panel is black. Two cases:
- the first HDR modeset after Panel Replay had been active in that boot (4 of 4 tries, the following ones 4 of 4 fine)
- the HDR modeset on resume from suspend

**Registers on transcoder A**
- `VIDEO_DIP_CTL` has the VSC DIP enabled. The VSC SDP contents (0x60320 onwards) are correct and the same in the good and the bad case: header, BT.2020, 10 bpc.
- The only stable difference is in 0x6024c / 0x60250:

| case | 0x6024c | 0x60250 |
|---|---|---|
| good | 0x00 | 0x9d |
| first HDR modeset after PR was active | 0xff | 0x00 |
| after resume | 0x00 | 0x00 |

We guessed from older platforms that these hold the SDP header ECC. We could not confirm their meaning on Xe3.

**Fix:** writing the VSC header dword (`HSW_TVIDEO_DIP_VSC_DATA(0)`) again with the same value while the DIP is enabled brings the picture back at once and turns 0x60250 back to 0x9d. Writing it while the DIP is disabled, toggling the DIP enable, or clearing DPCD 0x1B0 does not help. `hsw_write_infoframe()` writes the data while the DIP is disabled and enables it afterwards. Doing one extra write of dword 0 after the enable (only for `DP_SDP_VSC`) fixes both cases in our patched xe build. The ftrace call order is the same in good and bad runs.

**Workaround in use:** a kretprobe on `hsw_write_infoframe()` in a small out-of-tree module writes the header dword again once the VSC DIP is enabled: https://github.com/HHHHanasak1/onexplayer3-steamos-setup/tree/main/xehdrfix

We can provide register dumps and test builds.

**Filed:** https://gitlab.freedesktop.org/drm/xe/kernel/-/work_items/9693
