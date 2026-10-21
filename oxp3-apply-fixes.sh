#!/bin/bash
# oxp3-steamos-fixes - ONEXPLAYER 3 (Intel Panther Lake) SteamOS fix pack
# Version: 20261018-2     License: MIT (see LICENSE)     Author: HANA & Claude
# Tested on: SteamOS 3.10 main build 20260827.1000, kernel 7.2.0-valve1-1-neptune-72, OXP3 BIOS 5.09,
#            panel Samsung SDC AMS881KB01-0, SSD Predator GM7 1TB (Biwin/Maxio 1dee:1602)
# v1.1.0: gamescope HDR lua now also registers real 30-144Hz dynamic_modegen (this panel has genuine
#         continuous VRR; the v1.0.1 lua declared dynamic_refresh_rates but never shipped the
#         matching dynamic_modegen function, so no extra Hz options ever actually appeared in the
#         Steam Performance panel's per-game refresh-rate selector).
# 20261018-2: new optional step 14, SimpleDeckyTDP-Intel (contributed by kas5852, PR #24): a SimpleDeckyTDP fork whose
#         CPU Boost is Off / Smart / Full per game. A normal run asks once; the zip comes with the release archive; an
#         installed SimpleDeckyTDP is replaced only after the user confirms.
# 20261018: new step 13, OLED panel fix for BIOS 5.11 and later (contributed by kas5852, PR #15). Content-driven HDR
#         in the gamescope lua (kas5852, PR #22): SDR games keep the panel in SDR and scan out directly. The overlay's CPU
#         power is now the CPU cores only (RAPL PP0): the package counter it showed before includes the GPU, which the
#         overlay lists separately, so CPU + GPU looked like more than the TDP. A new SoC item after CPU and GPU (levels 2-4)
#         shows the whole-package power, which is what the TDP limits.
# 20261016: new step 10, CPU and GPU power/temperature in the performance overlay: a root service publishes coarse
#         (0.5 s, 10 mJ) world-readable copies of the package and PP1 energy counters, and a patched mangoapp (binary in the
#         release archive, sha256 pinned, falls back to the stock one) reads GPU power from PP1 and the GPU temperature
#         from the package sensor. This replaces the opt-in udev rule of 20261015, which made the raw counter world-readable.
#         New step 11, DMC v2.20 pin: SteamOS 20261015.1000 ships DMC v2.36, which caps VRR at 70-80 fps (issue #1).
#         New step 12, speaker route check: after a boot or resume the jack detection can leave PipeWire on the
#         Headphones profile with the speakers switched off; a user unit selects the Speaker profile when the jack is empty.
#         Sysfs overlays (battery clamp, RAPL copies) are detached lazily, so restarts no longer stack mounts.
# 20261015: new step 9, split-lock flood (contributed by kas5852, PR #16). Panther Lake traps user-space split locks and
#         Steam causes them continuously; steamos-manager logs every one and steamos-log-submitter queues one report file
#         per hit (seen: 119,091 files / 479 MB on BIOS 5.09, 361,102 on 5.12), which also pushed everything else out of the
#         50 MB journal. split_lock_detect=off on the kernel command line stops the traps; apply deletes the queued
#         split-lock reports (only those).
# 20261014: kernel 7.2.7 (SteamOS 20261013.1000) ships a hid-oxp with native ONEXPLAYER 3 support (three RGB LED zones,
#         suspend/resume handling) whose default paddle keys are KEY_F15/KEY_F16 instead of KEY_F16/KEY_F17. The paddles
#         reach InputPlumber through the MCU vendor frames either way, so any two distinct F13-F24 keys now count as correct
#         and apply no longer overrides the driver's default.
# v1.6.1: step 0 works offline: after a SteamOS update the Wi-Fi firmware is gone again, but the linux-firmware-intel package
#         cached in ~/.cache/oxp3-fix (in /home, survives updates) is now used without any network connection.
# v1.6.0: new step 8, TDP sync. The firmware leaves the MSR package PL1 (intel-rapl:0) at 25 W while TDP tools and the
#         firmware only set the MMIO package PL1; the GPU obeys the MSR PL1, so it was throttled ("pl1") at ~33 W even with
#         a 50 W TDP. A small root service copies the MMIO PL1 into the MSR PL1 whenever they differ.
# v1.5.1: the release is one archive, oxp3-fix.tar.gz (extract it in ~ to get ~/oxp3-fix). The gyro step takes the patched
#         InputPlumber from the archive next to the script and only downloads the archive when that copy is missing.
# v1.5.0: new OPTIONAL, EXPERIMENTAL step 7, gyroscope (--gyro, or answer y when asked). The BMI260 IMU is invisible to the kernel
#         (its ACPI node is named 10EC5280, which the bmi160 driver claims and fails on), so an ACPI table override renames it
#         and the bmi270 driver binds. A patched InputPlumber 0.78.0 (gyro/ in the repo, prebuilt binary from the GitHub release,
#         sha256 checked, falls back to the stock binary if it cannot run) feeds the Steam Deck virtual controller with corrected
#         axes and a drift-relaxing response curve. Needs BIOS 5.09 and stock InputPlumber 0.78.x, otherwise it is skipped.
#         --no-gyro removes it again; --revert removes it too. Nothing changes unless you opt in.
# v1.4.0: new step 6, battery percentage clamp. After a full charge the gauge reports energy_now above its own
#         energy_full (92.2 vs 89.9 Wh), the ACPI battery driver then reports capacity 103 and Steam (through its bundled
#         SDL3) and the performance overlay (energy_now/energy_full) show 101-104 %. A small root service bind-mounts
#         corrected "capacity" and "energy_full" files over the sysfs attributes (refreshed once a minute).
# v1.3.1: step 0 fixed. SteamOS ships its own linux-firmware-neptune package, which satisfies "linux-firmware" for
#         pacman but lacks the BE201 (Wi-Fi 7, CNVi 8086:e440) files iwlwifi-sc-a0-fm-c0-c10x and the matching Bluetooth
#         intel/ibt-00a0-0291-*, so the old "already installed" test skipped the fix and every OS update brings the
#         problem back. Now the step looks at the driver state (iwlwifi bound but no wireless interface / Bluetooth
#         firmware load failure), downloads the repo's linux-firmware-intel package once (cached in ~/.cache/oxp3-fix)
#         and extracts only the missing firmware families into /usr/lib/firmware (never overwriting existing files,
#         no package replacement). Wi-Fi comes up immediately (driver reload); Bluetooth after the reboot.
# v1.3.0: new step 0 at the very start of apply: Wi-Fi firmware. Unlocks the read-only root filesystem, initializes the
#         pacman keyring and installs linux-firmware (needs some other network connection for the download,
#         e.g. USB Ethernet or USB tethering). Skip it with --no-wifi.
# v1.2.0: back paddles (M1/M2) - verified working on stock hid-oxp (kernel 7.2.4-valve1): the driver maps
#         M1/M2 to KEY_F16/KEY_F17 and cycles the MCU report mode at boot, the MCU then emits vendor frames
#         B2 3F 01 01 1F 80 22|23 02 01 69|6A .. [01|02] which InputPlumber's oxp_hid decodes as Left/RightPaddle1.
#         On OXP3 physical LEFT = 0x22 = LeftPaddle1, so the L/R swap inherited from the oxp8 map was REMOVED.
#         New: state/--check report the paddle driver state; apply re-asserts gamepad_mode=xinput + F16/F17 via
#         the hid-oxp sysfs (driver pages 1-2 only, never raw hidraw); new --mcu-restore (DANGEROUS, explicit, confirmed)
#         rewrites MCU button-table page 3 (Home 0x24 + factory-default 0x21/0x25-0x2B) to recover a Home/Xbox
#         key that went silent after a foreign tool overwrote the MCU table.
OXP3_FIXES_VERSION="20261018-2"
TESTED_STEAMOS_BUILD="20260827.1000"
TESTED_KERNEL_PREFIX="7.2.0-valve1"
# ============================================================================
# ONEXPLAYER 3 fix re-applier  (SteamOS 3.10, Intel Panther Lake, xe)
# Purpose:
#   SteamOS updates may overwrite /etc changes. This script re-applies all six fixes (idempotent),
#   preceded by step 0 which gets Wi-Fi working on a fresh install, plus the optional experimental gyro step 7:
#     0) Wi-Fi firmware - unlock the root filesystem, initialize the pacman keyring, install linux-firmware (--no-wifi skips)
#     1) kernel param nvme.noacpi=1 (only for the Predator GM7 / 1dee:1602 SSD) - NVMe not resuming from s2idle
#     2) xe enable_dsb=0 - silence the per-frame xe DSB error flood under gamescope
#     3) gamescope known-display lua - HDR via the gamma2.2 path (native BT.2020/PQ output blanks the
#        panel), plus registers the panel's real 30-144Hz continuous VRR so the Steam Performance
#        panel's per-game refresh-rate selector actually has more than one option
#     4) volume-key fix service - the EC drops key releases; an evdev proxy synthesises them
#     5) InputPlumber composite device + capability map - Home/Console/Keyboard keys, back paddles as L4/R4, single virtual gamepad
#        (paddles rely on the in-kernel hid-oxp driver; this script only re-asserts its sysfs state, it never writes the MCU directly)
#     6) battery percentage clamp service - the gauge over-reports right after a full charge (103 %); a root service
#        overlays corrected capacity / energy_full sysfs values so Steam and the performance overlay stay at <= 100 %
#     7) [EXPERIMENTAL, opt-in] gyroscope - ACPI override so the kernel sees the BMI260 + patched InputPlumber (Steam Deck gyro)
#     8) TDP sync service - the MSR package PL1 (obeyed by the GPU) follows the MMIO PL1 that TDP tools set
#     9) kernel param split_lock_detect=off - stops the split-lock report flood (journal + steamos-log-submitter queue)
#    10) CPU and GPU power/temperature in the performance overlay - a root service publishes coarse (0.5 s, 10 mJ) world-
#        readable copies of the package and GPU (PP1) energy counters, which the kernel keeps root-only (CVE-2020-8694), and
#        a patched mangoapp (mangoapp/ in the repo, binary in the release archive) reads GPU power from PP1 and the GPU
#        temperature from the package sensor, because the integrated xe GPU has no hwmon device
#    11) display firmware DMC v2.20 - newer DMC releases (v2.36 in upstream linux-firmware, which SteamOS ships from
#        20261015.1000 on) cap the frame rate at 70-80 fps with VRR; v2.20 goes into /usr/lib/firmware/updates
#    12) speakers silent after boot or resume - the jack detection briefly reports headphones and PipeWire keeps the
#        Headphones profile; a user unit re-selects the Speaker profile when the jack is empty (only on that mismatch)
#    13) OLED stays on with BIOS 5.11 and later (contributed by kas5852, PR #15) - LOBF and PSR/Panel Replay off at boot
#        through xe debugfs (oxp3-panel-fix.service); only for the AMS881KB01 panel on BIOS 5.11+, --force-panel overrides
#    14) [optional, asked once in a normal run] SimpleDeckyTDP-Intel (kas5852, PR #24), a SimpleDeckyTDP fork with an
#        Off / Smart / Full CPU boost; the zip comes with the release archive; replacing an installed SimpleDeckyTDP
#        is only done after the user confirms it
#    15) games crash with "out of memory" after waking from sleep - on resume the xe driver rebinds every GPU mapping
#        in one array that big games push past the 4 MB kmalloc limit. A small kernel module (xevmafix/ in the repo,
#        oxp3-xevmafix.service) lets that array fall back to vmalloc. The .ko is built for one kernel and is skipped on any other
# Usage:
#   ./oxp3-apply-fixes.sh                apply (asks sudo password, prints the plan and confirms)
#   ./oxp3-apply-fixes.sh --check        check only, changes nothing, needs no sudo (covers every fix, gyro included when enabled)
#   ./oxp3-apply-fixes.sh --revert       undo every fix incl. gyro (then reboot)
#   ./oxp3-apply-fixes.sh --mcu-restore  [DANGEROUS] raw-writes MCU button-table page 3 (Home/Xbox) to factory values, asks to confirm.
#                                        Use ONLY if Home/Xbox are already dead. A wrong write can kill chassis keys for good and
#                                        cannot be read back or verified. Normal users must NOT run this. No other option writes the MCU.
#   flags: --yes no confirmation prompt | --force skip the device/OS guards | --force-nvme apply nvme.noacpi=1 on any SSD
#          --no-wifi skip step 0 (Wi-Fi firmware) | --force-panel apply step 13 on any BIOS
#          --sdtdp install SimpleDeckyTDP-Intel without asking (step 14) | --no-sdtdp remove it and stop asking
#          --gyro enable the experimental gyro step (remembered; later runs and OS-update re-runs keep it)
#          --no-gyro switch the gyro step off and remove its files (remembered)
# Idempotent: safe to run repeatedly.
# ============================================================================
set -euo pipefail

MODE="apply"; FORCE=0; FORCE_NVME=0; FORCE_PANEL=0; ASSUME_YES=0; SKIP_WIFI=0; GYRO_REQ=""; SDTDP_REQ=""
for a in "$@"; do
    case "$a" in
        --check) MODE="--check" ;;
        --revert) MODE="--revert" ;;
        --mcu-restore) MODE="--mcu-restore" ;;  # DANGEROUS: restore MCU button page 3 (Home/Xbox)
        --force) FORCE=1 ;;            # skip DMI + OS guards
        --force-nvme) FORCE_NVME=1 ;;  # apply nvme.noacpi=1 regardless of SSD model
        --force-panel) FORCE_PANEL=1 ;;
        --yes|-y) ASSUME_YES=1 ;;      # no confirmation prompt
        --no-wifi) SKIP_WIFI=1 ;;      # skip step 0 (Wi-Fi firmware)
        --gyro) GYRO_REQ=1 ;;          # enable the experimental gyro step (remembered)
        --no-gyro) GYRO_REQ=0 ;;       # disable it and remove its files (remembered)
        --sdtdp) SDTDP_REQ=1 ;;
        --no-sdtdp) SDTDP_REQ=0 ;;
        -h|--help) sed -n '2,/^set -euo pipefail/p' "$0" | grep -E '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a  (valid: --check | --revert | --mcu-restore | --force | --force-nvme | --force-panel | --no-wifi | --gyro | --no-gyro | --sdtdp | --no-sdtdp | --yes)"; exit 2 ;;
    esac
done
# target user's home (real user when run via sudo)
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
    USER_HOME="$HOME"
fi
[ -n "$USER_HOME" ] || USER_HOME="$HOME"
GRUB_D_FILE=/etc/default/grub.d/oxp3-nvme.cfg
SPLITLOCK_FILE=/etc/default/grub.d/oxp3-splitlock.cfg
SLS_TRACE_DIR=/var/lib/steamos-log-submitter/pending/trace
MODPROBE_FILE=/etc/modprobe.d/xe-oxp3.conf
LUA_DIR="$USER_HOME/.config/gamescope/scripts"
LUA_HDR="$LUA_DIR/98-oxp3-oled-hdr.lua"
LUA_NOHDR="$LUA_DIR/99-oxp3-nohdr.lua"
LUA_NOHDR_BAK="$USER_HOME/oxp3-nohdr.lua.disabled"
EFI_GRUB_CFG=/efi/EFI/steamos/grub.cfg
VOLKEY_PY="$USER_HOME/oxp3-fix/oxp3-volkey-fix.py"          # in /home, survives updates
VOLKEY_UNIT=/etc/systemd/system/oxp3-volkey-fix.service
BATT_SH="$USER_HOME/oxp3-fix/oxp3-battery-clamp.sh"          # in /home, survives updates
BATT_UNIT=/etc/systemd/system/oxp3-battery-clamp.service
TDP_SH="$USER_HOME/oxp3-fix/oxp3-tdp-sync.sh"                # in /home, survives updates
TDP_UNIT=/etc/systemd/system/oxp3-tdp-sync.service
PANEL_SH="$USER_HOME/oxp3-fix/oxp3-panel-fix.sh"
PANEL_UNIT=/etc/systemd/system/oxp3-panel-fix.service
PANEL_BIOS_MIN="5.11"
RAPL_PY="$USER_HOME/oxp3-fix/oxp3-rapl-overlay.py"          # in /home, survives updates
RAPL_UNIT=/etc/systemd/system/oxp3-rapl-overlay.service
MANGO_BIN="$USER_HOME/oxp3-fix/mangoapp-oxp3"               # patched mangoapp (source: mangoapp/ in the repo)
MANGO_LAUNCH="$USER_HOME/oxp3-fix/oxp3-mangoapp-launch.sh"   # starts MANGO_BIN, or the stock mangoapp when it cannot run
MANGO_DROPIN=/etc/systemd/user/gamescope-mangoapp.service.d/oxp3-mangoapp.conf
MANGO_FOR="0.8.3.rc1.r24.g33c2c7dd"                         # the SteamOS mangohud package the patch was built from
MANGO_SHA256="c79ca83722d0bc4dfb3f91388b2bbc012bfe8a30191df8c7996879a1a8d6645f"
XEVMA_KO="$USER_HOME/oxp3-fix/xevmafix.ko"
XEVMA_UNIT=/etc/systemd/system/oxp3-xevmafix.service
XEVMA_FOR="7.2.7-valve2-1-neptune-72-g31504582a073"
XEVMA_SHA256="b17d7bac071ded96da4f85fa6bf1bd52fa75bd0a10067fb33f7f8edd529a3599"
DMC_NAME=i915/xe3lpd_dmc.bin                                 # the Panther Lake display controller firmware
DMC_OVERRIDE=/usr/lib/firmware/updates/$DMC_NAME.zst         # firmware/updates takes precedence over the packaged file
DMC_SHA256="150eaa60a776e489f69e6f334d4c12216c0d686f3a53ac2228d0a6ce48f8add9"   # v2.20 (.zst) from linux-firmware-neptune 20260910
AUDIO_SH="$USER_HOME/oxp3-fix/oxp3-audio-route.sh"          # in /home, survives updates
AUDIO_UNIT="$USER_HOME/.config/systemd/user/oxp3-audio-route.service"   # user unit, in /home too
AUDIO_RESUME_UNIT=/etc/systemd/system/oxp3-audio-resume.service  # runs the user unit again after every resume
AUDIO_USER="$(stat -c %U "$USER_HOME" 2>/dev/null || id -un)"
IP_YAML=/etc/inputplumber/devices.d/50-onexplayer_3.yaml
IP_CAPMAP=/etc/inputplumber/capability_maps.d/onexplayer_type3.yaml   # id oxp3: Home key -> Guide   # InputPlumber 0.78 override dir is devices.d
# experimental gyro (step 7)
GYRO_DIR="$USER_HOME/oxp3-fix"                               # in /home, survives updates
GYRO_BIN="$GYRO_DIR/inputplumber-oxp3-gyro"                  # patched InputPlumber 0.78.0 (source: gyro/ in the repo)
GYRO_LAUNCH="$GYRO_DIR/oxp3-inputplumber-launch.sh"          # starts GYRO_BIN, or the stock binary if GYRO_BIN cannot run
GYRO_ON_FILE="$GYRO_DIR/gyro.enabled"                        # the user opted in
GYRO_OFF_FILE="$GYRO_DIR/gyro.declined"                      # the user said no (do not ask again)
GYRO_DROPIN=/etc/systemd/system/inputplumber.service.d/oxp3-gyro-fork.conf
GYRO_CONF=/etc/inputplumber/oxp3-gyro-steer.conf             # tuning, hot-reloaded every 2 s, never overwritten once it exists
ACPI_IMG=/boot/acpi_override.img
GRUB_IMU_FILE=/etc/default/grub.d/oxp3-imu.cfg
GYRO_BIOS="5.09"                                             # the ACPI override is a patched copy of this BIOS's SSDT26
GYRO_IP_SERIES="0.78"                                        # the patched build is InputPlumber 0.78.0
GYRO_BIN_SHA256="1107d95c34863c7865cac64183673135098d77265a32763c22fc7efbc1893aa3"
PKG_URL="https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/download/20261018-2/oxp3-fix.tar.gz"
GYRO_PKG_URL="$PKG_URL"   # release archive holding the binary
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"                  # the extracted release archive, if the script came from it
ACPI_IMG_SHA256="0e9b716e65978ac7365fda6fddf476a18b352a2d1ed98f4f30c8d3f8558b2113"
ACPI_IMG_OLD_SHA256="2d1a0a88e4cfe694cd4edc9b0d0a5e28f7f3f5bb9ccdcf7cbf1d5d01a02d42ad"   # earlier build of the same table (long cpio member name)
DECKY_PLUGINS="$USER_HOME/homebrew/plugins"
SDTDP_PLUGIN="$DECKY_PLUGINS/SimpleDeckyTDP-Intel"
SDTDP_UPSTREAM="$DECKY_PLUGINS/SimpleDeckyTDP"
SDTDP_VERSION="1.0.7+oxp3.1"
SDTDP_ZIP_NAME="simpledeckytdp-intel.zip"                   # in the release archive, from github.com/kas5852/SimpleDeckyTDP-Intel
SDTDP_SHA256="1e0b955905ca0447a63503bc814f4cff2c60f43d9721f2f29cceb7368c15ecc5"
SDTDP_README="https://github.com/kas5852/SimpleDeckyTDP-Intel#readme"
SDTDP_ON_FILE="$GYRO_DIR/sdtdp.enabled"
SDTDP_OFF_FILE="$GYRO_DIR/sdtdp.declined"

# ---- desired contents ------------------------------------------
GRUB_D_CONTENT=$(cat <<'EOT'
# nvme.noacpi=1: Predator GM7 fails to resume from s2idle via ACPI simple-suspend. Revert: rm this file, run update-grub
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} nvme.noacpi=1"
EOT
)

SPLITLOCK_CONTENT=$(cat <<'EOT'
# split_lock_detect=off: Steam's split locks were trapped and reported tens of times a second (journal flood, report files
# queued by steamos-log-submitter). SteamOS does not slow split locks down anyway (kernel.split_lock_mitigate=0).
# Revert: rm this file, run update-grub, reboot
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} split_lock_detect=off"
EOT
)

MODPROBE_CONTENT=$(cat <<'EOT'
# OXP3 (ONEXPLAYER 3, Panther Lake / xe) final config, 2026-09-06.
# enable_dsb=0: stops the per-frame "[CRTC:152:pipe A] DSB 0 poll error" flood seen whenever gamescope drives the eDP panel.
# Not related to the suspend fix (that is nvme.noacpi=1 in /etc/default/grub.d/oxp3-nvme.cfg). xe is not in the initramfs; takes effect on next boot.
# Revert: sudo rm /etc/modprobe.d/xe-oxp3.conf && reboot
options xe enable_dsb=0
EOT
)

LUA_HDR_CONTENT=$(cat <<'EOT'
-- ONEXPLAYER 3 Samsung SDC AMS881KB01-0 OLED: treat like Steam Deck OLED / OXP F1 OLED:
-- keep the panel in its native gamma-2.2 mode and let gamescope do HDR tone-mapping internally (no BT.2020/PQ VSC SDP is sent).
-- This panel has real continuous VRR from 30-144Hz (confirmed by user + two real kernel-reported
-- native modes at 60Hz and 144Hz via `modetest -c`: same pixel clock 380160kHz, same hsync/vsync
-- width, only vertical front porch differs). Both real data points fit a simple formula exactly
-- (vtotal = clock_hz / (htotal * refresh), front_porch = vtotal - vdisp - 64), so the table below
-- was generated from that formula rather than measured per-Hz -- verified to reproduce the two real
-- driver-reported modes (56 @144Hz, 1904 @60Hz) exactly before being trusted for the rest of the range.
-- Revert: delete this file and relogin game mode (HDR + extra refresh rates off). Installed by oxp3-apply-fixes.sh.
local oxp3_oled_colorimetry = {   -- from EDID
    r = { x = 0.6835, y = 0.3154 },
    g = { x = 0.2402, y = 0.7138 },
    b = { x = 0.1396, y = 0.0439 },
    w = { x = 0.3134, y = 0.3291 },
}
local oxp3_oled_refresh_rates = {
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
        45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
        75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
        90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104,
        105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
        135, 136, 137, 138, 139, 140, 141, 142, 143, 144,
}
gamescope.config.known_displays.oxp3_sdc_oled = {
    pretty_name = "ONEXPLAYER 3 SDC AMS881KB01-0 OLED",
    dynamic_refresh_rates = oxp3_oled_refresh_rates,
    dynamic_modegen = function(base_mode, refresh)
        debug("Generating mode "..refresh.."Hz for ONEXPLAYER 3 SDC OLED")
        local vfps = {
        [30] = 5072, [31] = 4868, [32] = 4676, [33] = 4496, [34] = 4327, [35] = 4167,
        [36] = 4016, [37] = 3873, [38] = 3738, [39] = 3610, [40] = 3488, [41] = 3372,
        [42] = 3262, [43] = 3156, [44] = 3056, [45] = 2960, [46] = 2868, [47] = 2780,
        [48] = 2696, [49] = 2615, [50] = 2538, [51] = 2463, [52] = 2391, [53] = 2322,
        [54] = 2256, [55] = 2192, [56] = 2130, [57] = 2071, [58] = 2013, [59] = 1958,
        [60] = 1904, [61] = 1852, [62] = 1802, [63] = 1753, [64] = 1706, [65] = 1660,
        [66] = 1616, [67] = 1573, [68] = 1531, [69] = 1491, [70] = 1451, [71] = 1413,
        [72] = 1376, [73] = 1340, [74] = 1305, [75] = 1270, [76] = 1237, [77] = 1205,
        [78] = 1173, [79] = 1142, [80] = 1112, [81] = 1083, [82] = 1054, [83] = 1026,
        [84] = 999, [85] = 972, [86] = 946, [87] = 921, [88] = 896, [89] = 872,
        [90] = 848, [91] = 825, [92] = 802, [93] = 780, [94] = 758, [95] = 737,
        [96] = 716, [97] = 696, [98] = 676, [99] = 656, [100] = 637, [101] = 618,
        [102] = 600, [103] = 581, [104] = 564, [105] = 546, [106] = 529, [107] = 512,
        [108] = 496, [109] = 480, [110] = 464, [111] = 448, [112] = 433, [113] = 418,
        [114] = 403, [115] = 389, [116] = 375, [117] = 361, [118] = 347, [119] = 333,
        [120] = 320, [121] = 307, [122] = 294, [123] = 281, [124] = 269, [125] = 257,
        [126] = 245, [127] = 233, [128] = 221, [129] = 209, [130] = 198, [131] = 187,
        [132] = 176, [133] = 165, [134] = 155, [135] = 144, [136] = 134, [137] = 123,
        [138] = 113, [139] = 103, [140] = 94, [141] = 84, [142] = 75, [143] = 65,
        [144] = 56,
        }
        local vfp = vfps[refresh]
        if vfp == nil then
            warn("Couldn't do refresh "..refresh.." on ONEXPLAYER 3 SDC OLED")
            return base_mode
        end
        local mode = base_mode
        gamescope.modegen.adjust_front_porch(mode, vfp)
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        return mode
    end,
    hdr = {
        supported = true,
        force_enabled = true,
        content_driven = true,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 1100,
        max_frame_average_luminance = 475,
        min_content_light_level = 0.0005,
    },
    colorimetry = oxp3_oled_colorimetry,
    matches = function(display)
        if display.vendor == "SDC" and display.model ~= nil and string.find(display.model, "AMS881KB01", 1, true) ~= nil then
            return 6000
        end
        return -1
    end,
}
debug("oxp3: registered OXP3 SDC OLED with gamma22 HDR + 30-144Hz dynamic refresh (Deck-OLED style)")
EOT
)

VOLKEY_PY_CONTENT=$(cat <<'EOT'
#!/usr/bin/python3
"""
OXP3 volume-key fix for the ONEXPLAYER 3

Problem:
  The EC drops key-release (break) scancodes for KEY_VOLUMEUP/KEY_VOLUMEDOWN, so the kernel
  keeps the key "held" (value=2 repeats) and Steam/X keep stepping the volume.

Approach:
  Grab the raw device, create a mirroring uinput device (no EV_REP), forward everything unchanged
  except the two volume keys: every make (value 1 or 2) becomes an immediate press+release pulse;
  the raw release events are dropped.

Usage:  oxp3-volkey-fix.py [--device /dev/input/eventN] [--verbose]
  By default the device is found by name "AT Translated Set 2 keyboard"; if it disappears the script waits and reconnects.
"""
import argparse
import os
import sys
import time

import evdev
from evdev import InputDevice, UInput, ecodes as e

SRC_NAME = "AT Translated Set 2 keyboard"
FIXED_KEYS = {e.KEY_VOLUMEUP, e.KEY_VOLUMEDOWN}
VDEV_NAME = "OXP3 EC keys (volkey fix)"


def log(msg):
    print(msg, flush=True)


def _on_term(signum, frame):
    raise SystemExit(0)   # unwinds through run_once's finally: ungrab + close


import signal
signal.signal(signal.SIGTERM, _on_term)
signal.signal(signal.SIGINT, _on_term)


def find_device(path_hint=None):
    if path_hint:
        return InputDevice(path_hint)
    for p in sorted(evdev.list_devices()):
        d = InputDevice(p)
        if d.name == SRC_NAME and d.name != VDEV_NAME:
            return d
        d.close()
    return None


def run_once(path_hint, verbose):
    dev = find_device(path_hint)
    if dev is None:
        return False
    log(f"source: {dev.path} '{dev.name}' (bus {dev.info.bustype:#x} vendor {dev.info.vendor:#x} product {dev.info.product:#x})")
    # Mirror capabilities except EV_SYN/EV_FF/EV_REP (no EV_REP => the kernel will not autorepeat our virtual keys).
    ui = UInput.from_device(dev, name=VDEV_NAME, vendor=0x1d50, product=0x0003, version=1,
                            filtered_types=(e.EV_SYN, e.EV_FF, e.EV_REP))
    log(f"virtual: {ui.device.path} '{VDEV_NAME}'")
    time.sleep(0.3)          # let udev/libinput/gamescope pick the new device up before we steal the old one
    dev.grab()
    log("grabbed source device; forwarding")
    pulses = 0
    dropped = 0
    try:
        for ev in dev.read_loop():
            if ev.type == e.EV_KEY and ev.code in FIXED_KEYS:
                if ev.value in (1, 2):
                    ui.write(e.EV_KEY, ev.code, 1)
                    ui.syn()
                    ui.write(e.EV_KEY, ev.code, 0)
                    ui.syn()
                    pulses += 1
                    if verbose:
                        log(f"pulse {e.KEY[ev.code]} (raw value {ev.value})")
                else:
                    dropped += 1
                    if verbose:
                        log(f"drop raw release {e.KEY[ev.code]}")
                continue
            if ev.type == e.EV_SYN and ev.code == e.SYN_REPORT:
                ui.syn()
                continue
            if ev.type in (e.EV_MSC, e.EV_LED, e.EV_REP):
                continue     # scancodes/LED state are not needed on the mirror
            ui.write(ev.type, ev.code, ev.value)
    except OSError as ex:
        log(f"source device gone ({ex}); pulses={pulses} dropped={dropped}")
    finally:
        try:
            dev.ungrab()
        except Exception:
            pass
        dev.close()
        ui.close()
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", help="source event device (default: find by name)")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    while True:
        try:
            if not run_once(args.device, args.verbose):
                log(f"waiting for '{SRC_NAME}'...")
                time.sleep(2)
                continue
        except PermissionError as ex:
            log(f"permission error: {ex} (run as root)")
            sys.exit(1)
        time.sleep(1)


if __name__ == "__main__":
    main()
EOT
)

VOLKEY_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3 volume keys fix (synthesize releases lost by the EC on the i8042 keyboard)
After=systemd-udevd.service
Wants=systemd-udevd.service
# Must grab event4 BEFORE the graphical session (gamescope/Steam) and powerbuttond, otherwise they
# bind the raw device and ignore the virtual device's volume keys (mid-session hotplug is not wired in).
Before=display-manager.service sddm.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 __VOLKEY_PY__
Restart=always
RestartSec=2
# needs root: EVIOCGRAB on /dev/input/event* and /dev/uinput
User=root
Nice=-5

[Install]
WantedBy=multi-user.target
EOT
)

BATT_SH_CONTENT=$(cat <<'EOT'
#!/bin/bash
# oxp3-battery-clamp.sh - keep the ONEXPLAYER 3 battery percentage at or below 100 %.
#
# The battery gauge ("Intel SR 1", model "SR Real Battery") reports an energy_now above its own energy_full after a
# full charge (seen: 92.17 Wh now vs 89.88 Wh full, design 84.55 Wh). Two things then show more than 100 %:
#   * the ACPI battery driver reports /sys/class/power_supply/BAT0/capacity = 103 (rounded, not clamped because
#     energy_full is above the design value); Steam reads that through its bundled SDL3 -> 103 % in the Steam UI;
#   * the performance overlay (mangoapp / MangoHud) computes energy_now / energy_full itself -> 101-103 %.
# upower is the only reader that clamps.
#
# Fix: bind-mount tmpfs files over the sysfs "capacity" and "energy_full" attributes. energy_full is reported as
# max(kernel energy_full, energy_now) - the value the battery demonstrably holds, the same thing upower does - and
# capacity as min(100, round(energy_now * 100 / energy_full)). Refreshed once a minute with fixed-width in-place
# writes, so a reader never sees an empty file. energy_now / status / uevent stay untouched. Runs as a root service
# (see the fix pack). Revert: systemctl disable --now oxp3-battery-clamp.service (ExecStopPost unmounts both files).
BAT=/sys/class/power_supply/BAT0
[ -r "$BAT/energy_now" ] && [ -r "$BAT/energy_full" ] || exit 0
REALDIR="$(readlink -f "$BAT")"
DIR=/run/oxp3-battery
INTERVAL=${OXP3_BATTERY_INTERVAL:-60}   # the percentage moves about 1 % per minute at most

kernel_full() { # the driver's energy_full, read from behind our own mount if it is already there
    if mountpoint -q "$REALDIR/energy_full"; then cat "$DIR/kernel_energy_full"; else cat "$BAT/energy_full"; fi
}

compute() { # sets FULL (uWh) and PCT
    local n f
    n=$(cat "$BAT/energy_now"); f=$(kernel_full)
    [ "${f:-0}" -gt 0 ] || f=$n
    [ -s "$DIR/max_energy_now" ] && [ "$(cat "$DIR/max_energy_now")" -gt "$n" ] 2>/dev/null && n_max=$(cat "$DIR/max_energy_now") || n_max=$n
    echo "$n_max" > "$DIR/max_energy_now"
    FULL=$f; [ "$n_max" -gt "$FULL" ] && FULL=$n_max
    PCT=$(( (n * 100 + FULL / 2) / FULL ))
    [ "$PCT" -gt 100 ] && PCT=100
    [ "$PCT" -lt 0 ] && PCT=0
}

write_fixed() { # write_fixed <file> <width> <value>: in-place, no truncation (single write of a fixed-size record)
    printf "%${2}d\n" "$3" | dd of="$1" bs=$(( $2 + 1 )) count=1 conv=notrunc status=none
}

case "$1" in
    --stop)
        # lazy: readers such as Steam keep the file open, a plain umount would fail with "target is busy"
        for a in capacity energy_full; do while mountpoint -q "$REALDIR/$a"; do umount -l "$REALDIR/$a" || break; done; done
        exit 0 ;;
    --once)
        if ! mkdir -p "$DIR" 2>/dev/null || [ ! -w "$DIR" ]; then   # not root: keep the service's state untouched
            t=$(mktemp -d); [ -f "$DIR/kernel_energy_full" ] && cp "$DIR/kernel_energy_full" "$DIR/max_energy_now" "$t/" 2>/dev/null; DIR=$t
        fi
        compute
        echo "energy_now=$(cat "$BAT/energy_now") kernel energy_full=$(kernel_full) -> reported energy_full=$FULL capacity=$PCT"
        exit 0 ;;
esac

mkdir -p "$DIR"
mountpoint -q "$REALDIR/energy_full" || cat "$BAT/energy_full" > "$DIR/kernel_energy_full"
compute
[ -s "$DIR/capacity" ]    || printf '%3d\n' "$PCT"  > "$DIR/capacity"
[ -s "$DIR/energy_full" ] || printf '%9d\n' "$FULL" > "$DIR/energy_full"
for a in capacity energy_full; do
    mountpoint -q "$REALDIR/$a" || mount --bind "$DIR/$a" "$REALDIR/$a" || exit 1
done
last=""
while :; do
    compute
    if [ "$PCT/$FULL" != "$last" ]; then
        write_fixed "$DIR/capacity" 3 "$PCT"
        write_fixed "$DIR/energy_full" 9 "$FULL"
        last="$PCT/$FULL"
    fi
    sleep "$INTERVAL"
done
EOT
)

BATT_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: keep the battery percentage at or below 100 % (sysfs overlay for Steam / performance overlay)
# see the header of __BATT_SH__ ; revert: systemctl disable --now oxp3-battery-clamp.service
After=basic.target
ConditionPathExists=/sys/class/power_supply/BAT0/energy_now

[Service]
Type=simple
ExecStart=/bin/bash __BATT_SH__
ExecStopPost=/bin/bash __BATT_SH__ --stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
)

IP_YAML_CONTENT=$(cat <<'EOT'
# yaml-language-server: $schema=https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/composite_device_v1.json
# ONEXPLAYER 3 (Intel Panther Lake) - custom InputPlumber composite device (oxp-debug 2026-09-06)
# Based on /usr/share/inputplumber/devices/50-onexplayer_apex.yaml (same MCU generation: xpad 045e:028e + WCH 1a86:fe00).
# Differences vs apex: DMI match = "ONEXPLAYER 3"; phys paths of this board; the "AT Translated Set 2 keyboard" (i8042) source is
# intentionally NOT included because event4 is grabbed by ~/oxp3-fix/oxp3-volkey-fix.py (volume-key fix) and its
# virtual mirror "OXP3 EC keys (volkey fix)" must keep feeding gamescope/Steam/powerbuttond directly.
# Target: deck-uhid (virtual Steam Deck controller; what steamos-manager forces for OneXPlayer models). Formerly xbox-elite (apex default
# controller - what steamos-manager configures for its supported OneXPlayer models). keyboard+mouse targets keep the MCU combos.
# Revert: sudo systemctl disable --now inputplumber; sudo rm /etc/inputplumber/devices.d/50-onexplayer_3.yaml
version: 1
kind: CompositeDevice
name: ONEXPLAYER 3
single_source: false

matches:
  - dmi_data:
      product_name: ONEXPLAYER 3
      sys_vendor: ONE-NETBOOK

source_devices:
  # Gamepad (X360 emulation of the controller MCU)
  - group: gamepad
    evdev:
      name: Microsoft X-Box 360 pad
      handler: event*
  # MCU keyboard interface (extra keys: Ctrl+Meta+O / Ctrl+Meta+Alt etc.)
  # NOTE: the MCU exposes TWO evdev nodes with this exact name (input0 keyboard, input1 consumer/mouse).
  # unique: false makes InputPlumber add both to the SAME composite device instead of spawning a second
  # composite (which left the real X360 pad unhidden and broke the deck-uhid target on boot/hot-plug).
  - group: keyboard
    unique: false
    evdev:
      name: "HID 1a86:fe00"
      handler: event*
  # MCU vendor interface 2: raw reports for back paddles M1/M2 (0xB2 3F 01 ... [01|02])
  - group: gamepad
    hidraw:
      vendor_id: 0x1a86
      product_id: 0xfe00
      interface_num: 2
  # IMU (BMI160 currently fails to probe on this board: "Error reading chip id" -121; kept for when the kernel/BIOS fix lands)
  - group: imu
    iio:
      name: "{i2c-BMI0160:00,bmi260,bmi160}"

options:
  auto_manage: true

target_devices:
  - deck-uhid   # steamos-manager forces deck-uhid on this model anyway; set it here to avoid a transient xbox target on (re)start
  - mouse
  - keyboard

capability_map_id: oxp3   # custom map: oxp8 + Home(0x24 native "Keyboard" button) -> Guide (see /etc/inputplumber/capability_maps.d/onexplayer_type3.yaml)
EOT
)

IP_CAPMAP_CONTENT=$(cat <<'EOT'
# yaml-language-server: $schema=https://raw.githubusercontent.com/ShadowBlip/InputPlumber/main/rootfs/usr/share/inputplumber/schema/capability_map_v1.json
# ONEXPLAYER 3 capability map (oxp-debug 2026-09-06) - copy of /usr/share/inputplumber/capability_maps/onexplayer_type8.yaml (id oxp8)
# plus one OXP3-specific entry: the chassis "Home" key arrives on the MCU vendor interface as raw frame
#   B2 3F 01 01 1F 80 24 02 02 05 00 00 [01=press|02=release], which InputPlumber's oxp_hid driver decodes as
#   Gamepad:Button:Keyboard (on the Steam Deck target that becomes the STEAM+X chord = on-screen keyboard).
#   The entry below remaps that native button to HOME_TARGET.  (chosen: Guide = Steam menu, closest to "go to Home"; alternatives:
#   Guide | QuickAccess | QuickAccess2 | Screenshot | Keyboard (keep) - change and restart inputplumber to switch)
# Back paddles: the MCU (hid-oxp driver defaults M1/M2 = KEY_F16/KEY_F17 + boot-time report-mode cycle) emits
#   B2 3F 01 01 1F 80 22 02 01 69 .. (physical LEFT) and .. 23 02 01 6A .. (physical RIGHT); InputPlumber's oxp_hid
#   decodes them as LeftPaddle1 / RightPaddle1 already in the right order, so unlike the oxp8 map there is NO
#   LeftPaddle1<->RightPaddle1 swap here (the swap made the OXP3 paddles come out reversed).
# Install: /etc/inputplumber/capability_maps.d/onexplayer_type3.yaml and set `capability_map_id: oxp3` in
#          /etc/inputplumber/devices.d/50-onexplayer_3.yaml, then `sudo systemctl restart inputplumber`.
# Revert:  delete this file and set capability_map_id back to oxp8.
version: 1
kind: CapabilityMap
name: OneXPlayer 3 (Type 8 + Home remap, paddles unswapped)
id: oxp3
mapping:
  - name: Home key (native btn 0x24 reported as Keyboard)
    source_events:
      - gamepad:
          button: Keyboard
    target_event:
      gamepad:
        button: Guide
  - name: Console key (Ctrl+Alt+Meta) -> Quick Access Menu
    source_events:
      - keyboard: KeyLeftCtrl
      - keyboard: KeyLeftAlt
      - keyboard: KeyLeftMeta
    target_event:
      gamepad:
        button: QuickAccess
  - name: Keyboard key (Ctrl+Meta+O) -> on-screen keyboard
    source_events:
      - keyboard: KeyLeftCtrl
      - keyboard: KeyLeftMeta
      - keyboard: KeyO
    target_event:
      gamepad:
        button: Keyboard
  - name: Orange Button (Short Press)
    source_events:
      - keyboard: KeyLeftMeta
      - keyboard: KeyG
    target_event:
      gamepad:
        button: Guide
  - name: Orange Button (Long Press)
    source_events:
      - keyboard: KeyLeftMeta
      - keyboard: KeyD
    target_event:
      gamepad:
        button: QuickAccess2
  - name: Turbo + Orange Button
    source_events:
      - keyboard: KeyLeftMeta
      - keyboard: KeySysrq
    target_event:
      gamepad:
        button: Screenshot
  - name: KB + Orange Button
    source_events:
      - keyboard: KeyRightCtrl
      - keyboard: KeyRightAlt
      - keyboard: KeyDelete
    target_event:
      keyboard: KeyF13
filtered_events: []
EOT
)
VOLKEY_UNIT_CONTENT="${VOLKEY_UNIT_CONTENT//__VOLKEY_PY__/$VOLKEY_PY}"
BATT_UNIT_CONTENT="${BATT_UNIT_CONTENT//__BATT_SH__/$BATT_SH}"

XEVMA_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3 games survive waking from sleep (xe rebind array via kvmalloc)
After=systemd-modules-load.service
RequiresMountsFor=__XEVMA_KO__
ConditionKernelVersion=__XEVMA_FOR__
ConditionPathExists=__XEVMA_KO__

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/modprobe xe
ExecStart=/bin/sh -c '[ -d /sys/module/xevmafix ] || exec /usr/bin/insmod __XEVMA_KO__'

[Install]
WantedBy=multi-user.target
EOT
)
XEVMA_UNIT_CONTENT="${XEVMA_UNIT_CONTENT//__XEVMA_KO__/$XEVMA_KO}"
XEVMA_UNIT_CONTENT="${XEVMA_UNIT_CONTENT//__XEVMA_FOR__/$XEVMA_FOR}"

# ---- TDP: MSR package PL1 follows the MMIO package PL1 (step 8) --------------------
TDP_SH_CONTENT=$(cat <<'EOT'
#!/bin/bash
# oxp3-tdp-sync.sh - keep the ONEXPLAYER 3's MSR package power limit (PL1) equal to the MMIO one.
#
# Panther Lake has two package RAPL interfaces: MMIO (/sys/class/powercap/intel-rapl-mmio:0) and MSR
# (/sys/class/powercap/intel-rapl:0). TDP tools such as SimpleDeckyTDP and the firmware itself (AC/DC switch) only
# write the MMIO one, while the firmware leaves the MSR PL1 at 25 W. CPU loads follow the MMIO limit, but the GPU obeys
# the MSR PL1: with MMIO at 50 W a ray-traced game ran the GPU at 1600-1850 of 2300 MHz with the throttle reason
# "pl1" and ~33 W package power. Copying the MMIO PL1 into the MSR PL1 made the GPU run at 2300 MHz, unthrottled.
#
# This root service checks every 2 s and copies the MMIO PL1 into the MSR PL1 whenever they differ, so whatever sets
# the TDP (a plugin, the firmware on AC/DC changes, a manual write) also sets the limit the GPU obeys. Only PL1 is
# touched; the MSR PL2 stays at its firmware value. On stop the MSR PL1 found at the first start is written back
# (a reboot restores the firmware value anyway). Options: --once prints both limits and exits, --stop restores.
MSR=/sys/class/powercap/intel-rapl:0
MMIO=/sys/class/powercap/intel-rapl-mmio:0
DIR=/run/oxp3-tdp
INTERVAL=${OXP3_TDP_INTERVAL:-2}
[ -r "$MSR/constraint_0_power_limit_uw" ] && [ -r "$MMIO/constraint_0_power_limit_uw" ] || { echo "no MSR/MMIO package RAPL, nothing to do"; exit 0; }
[ "$(cat "$MSR/name")" = package-0 ] && [ "$(cat "$MMIO/name")" = package-0 ] || { echo "RAPL zones are not package-0, nothing to do"; exit 0; }
w() { echo "$(( $1 / 1000000 )) W"; }
case "${1:-}" in
    --once) echo "MMIO PL1 $(w "$(cat "$MMIO/constraint_0_power_limit_uw")") / PL2 $(w "$(cat "$MMIO/constraint_1_power_limit_uw")")"
            echo "MSR  PL1 $(w "$(cat "$MSR/constraint_0_power_limit_uw")") / PL2 $(w "$(cat "$MSR/constraint_1_power_limit_uw")")"; exit 0 ;;
    --stop) if [ -s "$DIR/msr_pl1_orig" ]; then
                cat "$DIR/msr_pl1_orig" > "$MSR/constraint_0_power_limit_uw" && echo "MSR PL1 restored to $(w "$(cat "$DIR/msr_pl1_orig")")"
            fi; exit 0 ;;
esac
mkdir -p "$DIR"
[ -s "$DIR/msr_pl1_orig" ] || cat "$MSR/constraint_0_power_limit_uw" > "$DIR/msr_pl1_orig"
last=""
while :; do
    want=$(cat "$MMIO/constraint_0_power_limit_uw" 2>/dev/null)
    have=$(cat "$MSR/constraint_0_power_limit_uw" 2>/dev/null)
    if [ "${want:-0}" -gt 0 ] && [ "$want" != "$have" ]; then
        if echo "$want" > "$MSR/constraint_0_power_limit_uw" 2>/dev/null; then
            [ "$want" != "$last" ] && echo "MSR PL1 $(w "$have") -> $(w "$want") (follows MMIO PL1)"
            last=$want
        elif [ "$want" != "$last" ]; then
            echo "writing MSR PL1 = $(w "$want") failed"; last=$want
        fi
    fi
    sleep "$INTERVAL"
done
EOT
)

TDP_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: keep the MSR package power limit (PL1, obeyed by the GPU) equal to the MMIO one set by TDP tools
# see the header of __TDP_SH__ ; revert: systemctl disable --now oxp3-tdp-sync.service
After=basic.target
ConditionPathExists=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw

[Service]
Type=simple
ExecStart=/bin/bash __TDP_SH__
ExecStopPost=/bin/bash __TDP_SH__ --stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
)
TDP_UNIT_CONTENT="${TDP_UNIT_CONTENT//__TDP_SH__/$TDP_SH}"

PANEL_SH_CONTENT=$(cat <<'EOT'
#!/bin/bash
for _ in $(seq 1 100); do
    for d in /sys/kernel/debug/dri/*/; do
        [ -e "${d}eDP-1/i915_edp_lobf_debug" ] && [ -e "${d}i915_edp_psr_debug" ] && break 2
    done
    d=""
    sleep 0.2
done
[ -n "$d" ] || { echo "no xe debugfs entries for eDP-1, LOBF and PSR left unchanged"; exit 0; }
echo 1 > "${d}eDP-1/i915_edp_lobf_debug" && echo 0x1 > "${d}i915_edp_psr_debug" && echo "LOBF and PSR/Panel Replay disabled on eDP-1 (${d%/})"
EOT
)

PANEL_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: turn off LOBF and PSR/Panel Replay on the OLED before the display session starts
After=systemd-modules-load.service sys-kernel-debug.mount
Before=display-manager.service sddm.service
RequiresMountsFor=__PANEL_SH__

[Service]
Type=oneshot
ExecStart=/bin/bash __PANEL_SH__
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOT
)
PANEL_UNIT_CONTENT="${PANEL_UNIT_CONTENT//__PANEL_SH__/$PANEL_SH}"

# ---- CPU power for the overlay (step 10) ------------------------------
RAPL_PY_CONTENT=$(cat <<'EOT'
#!/usr/bin/python3
# oxp3-rapl-overlay.py - let the performance overlay show CPU and GPU power without exposing the raw RAPL counters.
#
# The overlay (mangoapp, MangoHud) runs as the desktop user and reads RAPL energy counters, which the kernel keeps
# root-only since the PLATYPUS power side channel (CVE-2020-8694): with a raw counter (updated about every millisecond,
# microjoule resolution) an unprivileged program can sample the energy of short code paths. So the overlay shows no
# CPU power ("Failed to initialize CPU power data" in the journal).
#
# Fix: a root service opens the real counters once, then bind-mounts world-readable copies over the attributes and
# refreshes them twice a second, rounded down to 10 mJ. That is plenty for a power reading over the overlay's 500 ms
# window, and useless for the side channel, which needs thousands of samples per second. Covered zones:
#   intel-rapl:0    package-0  whole-chip power (read by stock MangoHud as CPU power; includes the GPU)
#   intel-rapl:0:0  core       RAPL PP0, the CPU cores (read by the patched mangoapp as CPU power)
#   intel-rapl:0:1  uncore     RAPL PP1, the graphics power plane (read by the patched mangoapp for the integrated GPU)
# Every other RAPL counter stays root-only. The copies are monotonic counters that never wrap.
# Run as a root service (see the fix pack). --stop removes the overlays (systemctl stop does it too).
import os
import subprocess
import sys
import time

BASE = "/sys/class/powercap"
ZONES = [("intel-rapl:0", "package-0"), ("intel-rapl:0:0", "core"), ("intel-rapl:0:1", "uncore")]
RUNDIR = "/run/oxp3-rapl"
PERIOD = 0.5         # s between refreshes
QUANTUM = 10000      # uJ (10 mJ) resolution of the copies
WIDTH = 20           # fixed width, so every refresh is one same-length in-place write


def real_path(zone: str) -> str:
    return f"{BASE}/{zone}/energy_uj"


def mounted(path: str) -> bool:
    return subprocess.run(["mountpoint", "-q", path]).returncode == 0


def unmount(path: str) -> None:
    # lazy: the overlay keeps the file open, so a plain umount fails with "target is busy". Detaching is enough: a reader
    # holding the old copy keeps reading the same tmpfs file, which the next run keeps updating.
    for _ in range(10):
        if not mounted(path):
            return
        subprocess.run(["umount", "-l", path], check=False)


if len(sys.argv) > 1 and sys.argv[1] == "--stop":
    for zone, _ in ZONES:
        unmount(real_path(zone))
    sys.exit(0)

os.makedirs(RUNDIR, mode=0o755, exist_ok=True)
zones = []
for zone, name in ZONES:
    path = real_path(zone)
    try:
        with open(f"{BASE}/{zone}/name") as f:
            if f.read().strip() != name:
                continue
    except OSError:
        continue
    unmount(path)                           # a stale overlay from an earlier run would hide the real counter
    real = os.open(path, os.O_RDONLY)       # kept open: after the bind mount this fd is the only way to the real file
    with open(f"{BASE}/{zone}/max_energy_range_uj") as f:
        wrap = int(f.read()) + 1
    copy = f"{RUNDIR}/{zone}.energy_uj"
    fd = os.open(copy, os.O_RDWR | os.O_CREAT, 0o444)   # same file (inode) across restarts, see unmount()
    os.fchmod(fd, 0o444)
    try:
        total = int(os.pread(fd, 64, 0) or b"0")  # continue the published count, so a reader never sees it go back
    except ValueError:
        total = 0
    zones.append({"path": path, "real": real, "wrap": wrap, "copy": copy, "fd": fd, "total": total})

if not zones:
    print("no RAPL package zone, nothing to do")
    sys.exit(0)


def read_real(z) -> int:
    return int(os.pread(z["real"], 64, 0))


def publish(z) -> None:
    v = z["total"] - z["total"] % QUANTUM
    os.pwrite(z["fd"], b"%0*d\n" % (WIDTH, v), 0)


for z in zones:
    publish(z)
    subprocess.run(["mount", "--bind", z["copy"], z["path"]], check=True)
    z["last"] = read_real(z)
print(f"overlay active for {', '.join(z['path'] for z in zones)}: world-readable copies, {PERIOD} s / {QUANTUM // 1000} mJ")
sys.stdout.flush()
while True:
    time.sleep(PERIOD)
    for z in zones:
        now = read_real(z)
        z["total"] += now - z["last"] if now >= z["last"] else now + z["wrap"] - z["last"]
        z["last"] = now
        publish(z)
EOT
)

RAPL_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: coarse world-readable copies of the package, CPU core (PP0) and GPU (PP1) energy counters for the performance overlay
# see the header of __RAPL_PY__ ; revert: systemctl disable --now oxp3-rapl-overlay.service
After=basic.target
Before=display-manager.service
ConditionPathExists=/sys/class/powercap/intel-rapl:0/energy_uj

[Service]
Type=simple
ExecStart=/usr/bin/python3 __RAPL_PY__
ExecStopPost=/usr/bin/python3 __RAPL_PY__ --stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOT
)
RAPL_UNIT_CONTENT="${RAPL_UNIT_CONTENT//__RAPL_PY__/$RAPL_PY}"

MANGO_LAUNCH_CONTENT=$(cat <<'EOT'
#!/bin/sh
# Starts the OXP3 build of mangoapp (adds GPU power and temperature for the integrated xe GPU) through the systemd user
# drop-in oxp3-mangoapp.conf. The stock /usr/bin/mangoapp starts instead when the binary is missing, cannot load its
# libraries, was built for another mangohud version, or crashed three times within a minute, so the overlay never
# depends on this build.
B=__MANGO_BIN__
STOCK=/usr/bin/mangoapp
LOG="${XDG_RUNTIME_DIR:-/tmp}/oxp3-mangoapp.starts"
now=$(date +%s)
recent=$(awk -v n="$now" '$1 > n - 60' "$LOG" 2>/dev/null | wc -l)
echo "$now" >> "$LOG"
if [ "$recent" -lt 3 ] && [ -x "$B" ] && ! ldd "$B" 2>&1 | grep -q 'not found'; then
    case "$(pacman -Q mangohud 2>/dev/null)" in
        "mangohud __MANGO_FOR__-"*) exec "$B" "$@" ;;
    esac
fi
echo "oxp3: patched mangoapp not used here (version, libraries or repeated crashes), starting the stock one" >&2
exec "$STOCK" "$@"
EOT
)

MANGO_DROPIN_CONTENT=$(cat <<'EOT'
# OXP3: start mangoapp through a launcher that adds GPU power/temperature and falls back to the stock binary.
# Revert: ./oxp3-apply-fixes.sh --revert (or rm this file, systemctl --user daemon-reload)
[Service]
ExecStart=
ExecStart=__MANGO_LAUNCH__
EOT
)
MANGO_LAUNCH_CONTENT="${MANGO_LAUNCH_CONTENT//__MANGO_BIN__/$MANGO_BIN}"
MANGO_LAUNCH_CONTENT="${MANGO_LAUNCH_CONTENT//__MANGO_FOR__/$MANGO_FOR}"
MANGO_DROPIN_CONTENT="${MANGO_DROPIN_CONTENT//__MANGO_LAUNCH__/$MANGO_LAUNCH}"

# ---- speaker route check (step 12) contents ---------------------------
AUDIO_SH_CONTENT=$(cat <<'EOT'
#!/bin/sh
# oxp3-audio-route.sh - the speakers stay silent after a boot or resume although nothing is plugged into the headphone jack.
#
# The jack detection reports "plugged" for a moment while the codec (Realtek ALC245) powers up. PipeWire picks the
# Headphones card profile from that and misses the later "unplugged" event, so the speaker amplifier stays switched off
# until WirePlumber is restarted. This check runs a few times shortly after the session starts and after every resume
# (user unit oxp3-audio-route.service, started by the fix pack's resume hook). It only acts on a mismatch: the ALSA
# "Headphone Jack" control is off, but the active profile is a Headphones profile. It then selects the matching Speaker
# profile, or restarts WirePlumber when that does not take. A plugged-in headset is never touched.
log() { echo "oxp3-audio-route: $*"; }

check() {
    pactl list cards 2>/dev/null | awk '
        /^Card #/ { if (name != "") print name "\t" alsa "\t" active "\t" spk; name = ""; alsa = ""; active = ""; spk = ""; inprof = 0 }
        /^\tName: / { name = $2 }
        /api\.alsa\.card = / { v = $3; gsub(/"/, "", v); alsa = v }
        /^\tProfiles:/ { inprof = 1; next }
        /^\tActive Profile: / { inprof = 0; sub(/^\tActive Profile: /, ""); active = $0 }
        inprof && /^\t\t/ { p = $0; sub(/^\t\t/, "", p); sub(/: .*/, "", p); if (p ~ /Speaker/ && p !~ /Headphones/) spk = p }
        /^\t[A-Z]/ && !/^\tProfiles:/ { inprof = 0 }
        END { if (name != "") print name "\t" alsa "\t" active "\t" spk }' |
    while IFS="$(printf '\t')" read -r card alsa active spk; do
        case "$active" in *Headphones*) ;; *) continue ;; esac
        [ -n "$spk" ] && [ -n "$alsa" ] || continue
        amixer -c "$alsa" cget iface=CARD,name='Headphone Jack' 2>/dev/null | grep -q ': values=off' || continue
        log "nothing in the headphone jack, but $card uses \"$active\": switching to \"$spk\""
        pactl set-card-profile "$card" "$spk"
        sleep 2
        if pactl list cards 2>/dev/null | grep -q "Active Profile: $spk\$"; then
            log "speaker profile active"
        else
            log "the profile did not change, restarting WirePlumber"
            systemctl --user restart wireplumber.service
        fi
    done
}

# the jack settles within a few seconds; check a few times so a late wrong selection is caught too
for d in 3 7 20; do
    sleep "$d"
    check
done
EOT
)

AUDIO_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: select the speakers when the headphone jack is empty (jack misdetection at boot/resume)
# see the header of __AUDIO_SH__ ; revert: ./oxp3-apply-fixes.sh --revert
After=wireplumber.service

[Service]
Type=simple
ExecStart=/bin/sh __AUDIO_SH__

[Install]
WantedBy=graphical-session.target
EOT
)
AUDIO_UNIT_CONTENT="${AUDIO_UNIT_CONTENT//__AUDIO_SH__/$AUDIO_SH}"

AUDIO_RESUME_UNIT_CONTENT=$(cat <<'EOT'
[Unit]
Description=OXP3: re-check the speaker route after resume (starts the user unit oxp3-audio-route.service)
# revert: systemctl disable --now oxp3-audio-resume.service
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=-/usr/bin/systemctl --user -M __AUDIO_USER__@ start --no-block oxp3-audio-route.service

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOT
)
AUDIO_RESUME_UNIT_CONTENT="${AUDIO_RESUME_UNIT_CONTENT//__AUDIO_USER__/$AUDIO_USER}"

# ---- experimental gyro (step 7) contents ------------------------------
GRUB_IMU_CONTENT=$(cat <<'EOT'
# ACPI table override for the gyroscope (experimental): renames the IMU node so the kernel's bmi270 driver binds.
# Revert: ./oxp3-apply-fixes.sh --no-gyro   (or rm this file and /boot/acpi_override.img, then run update-grub)
GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.img"
EOT
)

GYRO_LAUNCH_CONTENT=$(cat <<'EOT'
#!/bin/sh
# Starts the OXP3 gyro build of InputPlumber (systemd drop-in oxp3-gyro-fork.conf). If that binary cannot run (a library it needs
# is gone after an OS update) or the stock InputPlumber is no longer the 0.78 series it was built from, the stock binary starts instead,
# so the gamepad never depends on the experimental build.
B=__GYRO_BIN__
STOCK=/usr/bin/inputplumber
case "$($STOCK --version 2>/dev/null)" in
    *" __GYRO_IP_SERIES__."*)
        if [ -x "$B" ] && ! ldd "$B" 2>&1 | grep -q 'not found'; then exec "$B"; fi ;;
esac
echo "oxp3: gyro InputPlumber build unusable here, starting the stock inputplumber" >&2
exec "$STOCK"
EOT
)

GYRO_DROPIN_CONTENT=$(cat <<'EOT'
# OXP3 gyro (experimental): run the patched InputPlumber through a launcher that falls back to the stock binary.
# Revert: ./oxp3-apply-fixes.sh --no-gyro
[Service]
ExecStart=
ExecStart=__GYRO_LAUNCH__
EOT
)

GYRO_CONF_CONTENT=$(cat <<'EOT'
# OXP3 gyro drift handling (InputPlumber fork, deck-uhid target). Re-read every 2 s, no restart needed.
enabled=1
mode=gyro         # gyro: shape the yaw rate sent to Steam (Steam's own gyro layout keeps working)
                  # stick: map the angle to the left stick X instead
tau=20            # seconds: Steam's integrated angle relaxes toward centre with this time constant
                  # (a 0.08 deg/s bias then stays a ~1.6 deg offset instead of drifting; long held turns relax slowly)
bias_auto=1       # learn the gyro bias while the device rests (2 s still windows)
bias_gyro_ptp=0.6 # deg/s: max gyro span for a window to count as still
bias_accel_ptp=0.02 # g: max accelerometer span for a window to count as still
# response shaping (gyro mode): Steam's integrated angle = gain * curve(physical angle)
range=45          # deg: knee of the curve; below it small tilts are boosted, above it the response flattens
curve=0           # 0 = linear (default); 0.5 = 1.5x near centre tapering to 0.5x at `range` (max 0.95)
gain=1.0          # overall multiplier (lower = calmer at large angles)
# stick mode only
max_angle=25
deadzone=1.5
accel_gain=2.0
smooth_hz=8
invert=0
upright_min=0.6
EOT
)

# extra keys for the IMU source in the InputPlumber yaml (only understood by the patched build)
IP_YAML_GYRO_MARK='      name: "{i2c-BMI0160:00,bmi260,bmi160}"'
IP_YAML_GYRO_EXTRA=$(cat <<'EOT'
      sample_rate: 400
      # Gyro bias compensation is available (deg/s, sensor frame) but left OFF: Steam estimates the gyro bias of a
      # Steam Deck controller itself, and our compensation fought with it (centre wandered 2-3 deg in Forza, 2026-09-19).
      gyro_bias: [0, 0, 0]
      gyro_auto_calibrate: false
      # Sensor -> Steam Deck frame (right, top edge, out of screen); the forked bmi_imu.rs then orders the gyro
      # fields the way SDL_hidapi_steamdeck.c reads them. Pose test 2026-09-19: flat screen-up sensor z=-9.8
      # (z into the screen), kickstand sensor x<0 (x toward the bottom edge), left edge raised sensor y>0 (y to the left).
      mount_matrix:
        x: [0, -1, 0]
        y: [-1, 0, 0]
        z: [0, 0, -1]
      # Accelerometer bias (m/s^2, sensor frame) from the flat / rotated-180-degrees pair on 2026-09-19:
      # Deck-frame readings x=+163 y=-822 LSB in both orientations -> table tilt cancels, this is sensor offset.
      accel_bias: [0.503, -0.100, 0]
EOT
)
IP_YAML_CONTENT_BASE="$IP_YAML_CONTENT"
set_gyro_yaml() { IP_YAML_CONTENT="${IP_YAML_CONTENT_BASE/"$IP_YAML_GYRO_MARK"/"$IP_YAML_GYRO_MARK"$'\n'"$IP_YAML_GYRO_EXTRA"}"; }
set_base_yaml() { IP_YAML_CONTENT="$IP_YAML_CONTENT_BASE"; }

# The ACPI override: a cpio image (kernel/firmware/acpi/ssdt-oxp3-imu.aml) holding this BIOS's SSDT26 (Rtd3 I2C_DEVT) with the IMU node
# renamed 10EC5280 -> BMI0260 (source: gyro/SSDT26-oxp3-imu.dsl). gzip + base64.
# DMC v2.20 for xe3lpd (Intel firmware, redistributable unmodified under firmware/LICENSE.i915), zstd as shipped, base64
DMC_B64=$(cat <<'EOT'
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
E+rZxAFOeU0W
EOT
)

ACPI_IMG_B64=$(cat <<'EOT'
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
UQAA
EOT
)
GYRO_LAUNCH_CONTENT="${GYRO_LAUNCH_CONTENT//__GYRO_BIN__/$GYRO_BIN}"
GYRO_LAUNCH_CONTENT="${GYRO_LAUNCH_CONTENT//__GYRO_IP_SERIES__/$GYRO_IP_SERIES}"
GYRO_DROPIN_CONTENT="${GYRO_DROPIN_CONTENT//__GYRO_LAUNCH__/$GYRO_LAUNCH}"

# ---- helpers ------------------------------------------------------
say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n== %s ==\n' "$*"; }
same_content() { # same_content <file> <content>  -> 0 if identical
    [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]
}
CHANGED=0; NEED_REBOOT=0; NEED_RELOGIN=0; VOLKEY_RESTART=0; IP_RESTART=0; BATT_RESTART=0; TDP_RESTART=0; RAPL_RESTART=0; PANEL_RESTART=0
have_rapl_pkg() { [ -e /sys/class/powercap/intel-rapl:0/energy_uj ]; }
# the running kernel loads the xe3lpd DMC (Panther Lake display); the line also names the loaded version
dmc_loaded() { journalctl -k -b 0 --no-pager 2>/dev/null | sed -n "s|.*Finished loading DMC firmware $DMC_NAME (\(v[0-9.]*\)).*|\1|p" | tail -n1; }
dmc_system_sha() { sha256sum /usr/lib/firmware/$DMC_NAME.zst 2>/dev/null | cut -d' ' -f1; }
dmc_override_ok() { [ "$(sha256sum "$DMC_OVERRIDE" 2>/dev/null | cut -d' ' -f1)" = "$DMC_SHA256" ]; }
# only on machines that use this firmware at all
dmc_applies() { [ -e /usr/lib/firmware/$DMC_NAME.zst ] || [ -e /usr/lib/firmware/$DMC_NAME ]; }
DMC_RUNNING="$(dmc_loaded)"
# the patched mangoapp is only useful for an integrated xe GPU without its own hwmon device
igpu_without_hwmon() { [ "$(basename "$(readlink /sys/class/drm/card0/device/driver 2>/dev/null)")" = xe ] && ! ls -d /sys/class/drm/card0/device/hwmon >/dev/null 2>&1; }
mango_bin_ok() { [ -f "$MANGO_BIN" ] && [ "$(sha256sum "$MANGO_BIN" | cut -d' ' -f1)" = "$MANGO_SHA256" ]; }
mango_matches() { pacman -Q mangohud 2>/dev/null | grep -q "^mangohud $MANGO_FOR-"; }
xe_gpu() { [ "$(basename "$(readlink /sys/class/drm/card0/device/driver 2>/dev/null)")" = xe ]; }
xevma_kernel_ok() { [ "$KVER" = "$XEVMA_FOR" ]; }
xevma_ko_ok() { [ -f "$XEVMA_KO" ] && [ "$(sha256sum "$XEVMA_KO" | cut -d' ' -f1)" = "$XEVMA_SHA256" ]; }
xevma_loaded() { [ -d /sys/module/xevmafix ]; }
xevma_handled() { cut -d' ' -f1 /sys/module/xevmafix/parameters/large_allocations 2>/dev/null || echo "?"; }
user_systemctl() { systemctl --user "$@" 2>/dev/null || true; }   # the desktop user's manager (the script runs as that user)
have_rapl() { [ -r /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ] && [ -r /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw ]; }

# ---- guards -----------------------------------------------------------
DMI_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
DMI_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
OS_ID="$(. /etc/os-release 2>/dev/null; echo "${ID:-}")"
OS_BUILD="$(. /etc/os-release 2>/dev/null; echo "${BUILD_ID:-${VERSION_ID:-}}")"
KVER="$(uname -r)"
if [ "$FORCE" != 1 ]; then
    if [ "$DMI_VENDOR" != "ONE-NETBOOK" ] || [[ "$DMI_PRODUCT" != ONEXPLAYER\ 3* ]]; then
        say "!! This script targets the ONEXPLAYER 3 only (detected: '$DMI_VENDOR' / '$DMI_PRODUCT'). Use --force to override."
        exit 3
    fi
    if [ "$OS_ID" != "steamos" ]; then
        say "!! SteamOS required (ID=$OS_ID); --force to override."
        exit 3
    fi
fi
if [ "$OS_BUILD" != "$TESTED_STEAMOS_BUILD" ] || [[ "$KVER" != ${TESTED_KERNEL_PREFIX}* ]]; then
    say "  Note: tested on SteamOS $TESTED_STEAMOS_BUILD / kernel ${TESTED_KERNEL_PREFIX}*; you have $OS_BUILD / $KVER."
fi
# only the Predator GM7 / Biwin-Maxio 1dee:1602 is known to need nvme.noacpi=1 (s2idle resume failure)
nvme_bug_present() {
    [ "$FORCE_NVME" = 1 ] && return 0
    lspci -n 2>/dev/null | grep -qi '1dee:1602' && return 0
    grep -qiE 'GM7|Predator' /sys/class/nvme/nvme*/model 2>/dev/null && return 0
    return 1
}
have_evdev() { python3 -c 'import evdev' >/dev/null 2>&1; }
have_split_lock_detect() { grep -qw split_lock_detect /proc/cpuinfo 2>/dev/null; }
sls_split_lock_traces() { # $1 = "sudo" in apply (credentials validated), default "sudo -n" (state/--check, no prompt)
    local S="${1:-sudo -n}"
    $S test -d "$SLS_TRACE_DIR" 2>/dev/null || { echo '?'; return 0; }
    $S grep -rlZ '"type": "split_lock"' "$SLS_TRACE_DIR" 2>/dev/null | tr -cd '\0' | wc -c || true
}
have_ip() { command -v inputplumber >/dev/null 2>&1 && [ -f /usr/lib/systemd/system/inputplumber.service ]; }
# the hid-oxp-bound MCU config interface (iface 2, has the gamepad_mode attribute)
oxp_hid_dev() { local d; for d in /sys/bus/hid/drivers/hid-oxp/0003:1A86:FE00.*; do [ -f "$d/gamepad_mode" ] && { echo "$d"; return 0; }; done; return 1; }
OXP_DEV="$(oxp_hid_dev || true)"
OXP_MODE="$(cat "$OXP_DEV/gamepad_mode" 2>/dev/null || echo '-')"
OXP_M1="$(cat "$OXP_DEV/button_m1" 2>/dev/null || echo '-')"
OXP_M2="$(cat "$OXP_DEV/button_m2" 2>/dev/null || echo '-')"
# M1/M2 only need to be two different function keys: the paddles reach InputPlumber through the MCU vendor frames, the key
# the driver maps them to does not matter (kernel 7.2.4 default F16/F17, 7.2.7 default F15/F16)
paddle_key_ok() { case "$1" in KEY_F1[3-9]|KEY_F2[0-4]) return 0 ;; esac; return 1; }
paddles_ok() { [ -n "$OXP_DEV" ] && [ "$OXP_MODE" = xinput ] && paddle_key_ok "$OXP_M1" && paddle_key_ok "$OXP_M2" && [ "$OXP_M1" != "$OXP_M2" ]; }
# the 7.2.7+ driver with native OXP3 support registers these LEDs; its paddle defaults are F15/F16
if ls -d /sys/class/leds/oxp:rgb:* >/dev/null 2>&1; then PADDLE_M1=KEY_F15; PADDLE_M2=KEY_F16; else PADDLE_M1=KEY_F16; PADDLE_M2=KEY_F17; fi
NVME_MODEL="$(cat /sys/class/nvme/nvme0/model 2>/dev/null | xargs || echo unknown)"
panel_is_oled() { grep -qa AMS881KB01 /sys/class/drm/card*-eDP-*/edid 2>/dev/null; }
bios_at_least() { [ -n "$BIOS_VER" ] && [ "$(printf '%s\n' "$1" "$BIOS_VER" | sort -V | head -n1)" = "$1" ]; }
panel_fix_needed() {
    [ "$FORCE_PANEL" = 1 ] && return 0
    panel_is_oled && bios_at_least "$PANEL_BIOS_MIN"
}
panel_debugfs() { sudo -n sh -c "cat /sys/kernel/debug/dri/*/$1" 2>/dev/null | sed -n "s/^$2: //p" | head -n1 || true; }

# ---- experimental gyro: wanted? possible? ------------------------------
IMU_ACTIVE=0; [ -e /sys/bus/i2c/devices/i2c-BMI0260:00 ] && IMU_ACTIVE=1     # the ACPI override is live in the running kernel
BIOS_VER="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || true)"
IP_VER="$(/usr/bin/inputplumber --version 2>/dev/null | awk '{print $2}' || true)"
# prints why the gyro step cannot be used here (nothing when it can)
gyro_block_reason() {
    if [ "$FORCE" = 1 ]; then return 0; fi
    if [ "$BIOS_VER" != "$GYRO_BIOS" ]; then echo "BIOS is '${BIOS_VER:-?}', the ACPI override only matches BIOS $GYRO_BIOS (--force overrides)"; return 0; fi
    if ! have_ip; then echo "InputPlumber is not installed"; return 0; fi
    case "$IP_VER" in "$GYRO_IP_SERIES".*) ;; *) echo "InputPlumber is '${IP_VER:-?}', the patched build is for the $GYRO_IP_SERIES series (--force overrides)"; return 0 ;; esac
}
GYRO_WANT=0
if [ "$GYRO_REQ" = 1 ]; then GYRO_WANT=1
elif [ "$GYRO_REQ" = 0 ]; then GYRO_WANT=0
elif [ -f "$GYRO_ON_FILE" ] || [ -f "$GYRO_DROPIN" ]; then GYRO_WANT=1; fi     # opted in earlier (or installed by hand)
GYRO_BLOCK="$(gyro_block_reason)"
GYRO_ON=0; GYRO_DECLINED=0
if [ "$GYRO_WANT" = 1 ] && [ -z "$GYRO_BLOCK" ]; then GYRO_ON=1; set_gyro_yaml; fi
gyro_bin_ok() { [ -f "$GYRO_BIN" ] && [ "$(sha256sum "$GYRO_BIN" | cut -d' ' -f1)" = "$GYRO_BIN_SHA256" ]; }
acpi_img_sha() { sha256sum "$ACPI_IMG" 2>/dev/null | cut -d' ' -f1 || true; }
gyro_installed() { [ -f "$GYRO_DROPIN" ] || [ -f "$GYRO_LAUNCH" ] || [ -f "$GYRO_BIN" ] || [ -f "$GYRO_CONF" ] || [ -f "$GRUB_IMU_FILE" ] || [ -f "$GYRO_ON_FILE" ] \
    || [ "$(acpi_img_sha)" = "$ACPI_IMG_SHA256" ] || [ "$(acpi_img_sha)" = "$ACPI_IMG_OLD_SHA256" ]; }
sudo_put() { # sudo_put <file> <content>: write as root when it differs; returns 1 when unchanged
    if same_content "$1" "$2"; then say "  [skip] $1 unchanged"; return 1; fi
    sudo mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" | sudo tee "$1" >/dev/null; say "  [write] $1"; return 0
}
# take every gyro file away again (the grub reference goes before the image, so the boot menu never points at a missing file)
remove_gyro() {
    local _cur
    if [ -f "$GYRO_DROPIN" ]; then
        sudo rm -f "$GYRO_DROPIN"; sudo rmdir "$(dirname "$GYRO_DROPIN")" 2>/dev/null || true; sudo systemctl daemon-reload
        say "  [remove] $GYRO_DROPIN (InputPlumber is the stock binary again)"; IP_RESTART=1; CHANGED=1
    fi
    for _f in "$GYRO_LAUNCH" "$GYRO_BIN" "$GYRO_BIN.part"; do [ -f "$_f" ] && { rm -f "$_f"; say "  [remove] $_f"; }; done
    if [ -f "$GYRO_CONF" ]; then sudo rm -f "$GYRO_CONF"; say "  [remove] $GYRO_CONF"; fi
    if [ -f "$GRUB_IMU_FILE" ]; then
        sudo rm -f "$GRUB_IMU_FILE"; say "  [remove] $GRUB_IMU_FILE"; sudo update-grub; CHANGED=1
    fi
    _cur="$(acpi_img_sha)"
    if [ -n "$_cur" ] && { [ "$_cur" = "$ACPI_IMG_SHA256" ] || [ "$_cur" = "$ACPI_IMG_OLD_SHA256" ]; }; then
        if sudo grep -q 'acpi_override.img' "$EFI_GRUB_CFG" 2>/dev/null; then sudo update-grub; fi
        sudo rm -f "$ACPI_IMG"; say "  [remove] $ACPI_IMG"; CHANGED=1
        [ "$IMU_ACTIVE" = 1 ] && NEED_REBOOT=1
    fi
    return 0
}
have_decky() { [ -d "$DECKY_PLUGINS" ] && systemctl cat plugin_loader.service >/dev/null 2>&1; }
sdtdp_installed() { [ -f "$SDTDP_PLUGIN/plugin.json" ]; }
sdtdp_version() { sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$SDTDP_PLUGIN/package.json" 2>/dev/null | head -n1; }
SDTDP_WANT=0
if [ "$SDTDP_REQ" = 1 ]; then SDTDP_WANT=1
elif [ "$SDTDP_REQ" = "" ] && [ -f "$SDTDP_ON_FILE" ]; then SDTDP_WANT=1; fi
SDTDP_DECLINED=0
remove_sdtdp() {
    sdtdp_installed || return 0
    sudo rm -rf "$SDTDP_PLUGIN"; CHANGED=1
    say "  [remove] $SDTDP_PLUGIN (its settings stay in $USER_HOME/homebrew/settings/SimpleDeckyTDP-Intel)"
    sudo systemctl restart plugin_loader.service || true
    say "  CPU frequency caps set by Smart boost stay until the next reboot. The original SimpleDeckyTDP is not put back; install it from the Decky store (https://github.com/aarron-lee/SimpleDeckyTDP)."
}
install_sdtdp() {
    local _tmp _zip=""
    if ! command -v unzip >/dev/null 2>&1; then
        say "  [error] SimpleDeckyTDP-Intel: unzip is needed"; return 1
    fi
    _tmp="$(mktemp -d "${TMPDIR:-/tmp}/oxp3-sdtdp.XXXXXX")"
    if [ -f "$SCRIPT_DIR/$SDTDP_ZIP_NAME" ] && [ "$(sha256sum "$SCRIPT_DIR/$SDTDP_ZIP_NAME" | cut -d' ' -f1)" = "$SDTDP_SHA256" ]; then
        _zip="$SCRIPT_DIR/$SDTDP_ZIP_NAME"; say "  SimpleDeckyTDP-Intel $SDTDP_VERSION from the release archive (sha256 verified)"
    elif ! command -v curl >/dev/null 2>&1 || ! ip route 2>/dev/null | grep -q '^default'; then
        say "  [error] SimpleDeckyTDP-Intel: the plugin is not on this machine and there is no network to download it"; rm -rf "$_tmp"; return 1
    else
        say "  [run] downloading the release archive ($PKG_URL) ..."
        if curl -fL --retry 3 --progress-bar -o "$_tmp/pkg.tar.gz" "$PKG_URL" \
            && tar -xzf "$_tmp/pkg.tar.gz" -C "$_tmp" "oxp3-fix/$SDTDP_ZIP_NAME" \
            && [ "$(sha256sum "$_tmp/oxp3-fix/$SDTDP_ZIP_NAME" | cut -d' ' -f1)" = "$SDTDP_SHA256" ]; then
            _zip="$_tmp/oxp3-fix/$SDTDP_ZIP_NAME"
        else
            say "  [error] SimpleDeckyTDP-Intel: download failed or the sha256 does not match"; rm -rf "$_tmp"; return 1
        fi
    fi
    if ! sudo unzip -oq "$_zip" -d "$DECKY_PLUGINS"; then
        say "  [error] SimpleDeckyTDP-Intel: could not unpack it into $DECKY_PLUGINS"; rm -rf "$_tmp"; return 1
    fi
    rm -rf "$_tmp"; CHANGED=1
    say "  [write] $SDTDP_PLUGIN ($SDTDP_VERSION)"
    return 0
}

# ---- a. current state ------------------------------------------
hdr "Current state  (oxp3-steamos-fixes $OXP3_FIXES_VERSION)"
say "  device: $DMI_VENDOR $DMI_PRODUCT ; SteamOS $OS_BUILD ; kernel $KVER ; NVMe: $NVME_MODEL"
if grep -qw 'nvme.noacpi=1' /proc/cmdline; then
    say "  kernel param nvme.noacpi=1 : active (in /proc/cmdline)"; CMD_OK=1
else
    say "  kernel param nvme.noacpi=1 : NOT active (not in /proc/cmdline)"; CMD_OK=0
fi
if [ -f "$GRUB_D_FILE" ]; then say "  $GRUB_D_FILE : present"; else say "  $GRUB_D_FILE : missing"; fi
SL_OK=0; SL_TRACES='?'
if have_split_lock_detect; then
    if grep -qw 'split_lock_detect=off' /proc/cmdline; then
        say "  kernel param split_lock_detect=off : active (in /proc/cmdline)"; SL_OK=1
    else
        say "  kernel param split_lock_detect=off : NOT active (not in /proc/cmdline)"
    fi
    SL_TRACES="$(sls_split_lock_traces)"
    say "  split-lock reports queued by steamos-log-submitter : $SL_TRACES   ('?' = needs sudo to read)"
fi
XE_DSB="$(cat /sys/module/xe/parameters/enable_dsb 2>/dev/null || sudo -n cat /sys/module/xe/parameters/enable_dsb 2>/dev/null || echo '?')"
say "  xe enable_dsb (running) : $XE_DSB   expected N or 0 ('?' = needs sudo to read)"
if [ -f "$MODPROBE_FILE" ]; then say "  $MODPROBE_FILE : present"; else say "  $MODPROBE_FILE : missing"; fi
if [ -f "$LUA_HDR" ]; then say "  HDR lua $LUA_HDR : present"; else say "  HDR lua : missing"; fi
if [ -f "$LUA_NOHDR" ]; then say "  old nohdr lua $LUA_NOHDR : present (will be removed)"; fi
if systemctl is-active -q oxp3-volkey-fix.service 2>/dev/null; then say "  volume-key fix service oxp3-volkey-fix : active"; else say "  volume-key fix service oxp3-volkey-fix : inactive/missing"; fi
if systemctl is-active -q inputplumber.service 2>/dev/null; then say "  InputPlumber (paddles/gamepad) : active"; else say "  InputPlumber (paddles/gamepad) : inactive"; fi
BAT_SYS=/sys/class/power_supply/BAT0
if [ -r "$BAT_SYS/energy_now" ]; then
    say "  battery gauge : energy_now=$(cat "$BAT_SYS/energy_now") energy_full=$(cat "$BAT_SYS/energy_full" | tr -d ' ') capacity=$(cat "$BAT_SYS/capacity" | tr -d ' ')%   ($(findmnt -T "$BAT_SYS/capacity" -n -o SOURCE 2>/dev/null | grep -q oxp3-battery && echo "overlay active" || echo "raw kernel values"))"
    if systemctl is-active -q oxp3-battery-clamp.service 2>/dev/null; then say "  battery clamp service oxp3-battery-clamp : active"; else say "  battery clamp service oxp3-battery-clamp : inactive/missing"; fi
fi
if have_rapl; then
    say "  package power limit PL1 : MMIO $(( $(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw) / 1000000 )) W, MSR $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw) / 1000000 )) W   (the GPU obeys MSR; they should match)"
    if systemctl is-active -q oxp3-tdp-sync.service 2>/dev/null; then say "  TDP sync service oxp3-tdp-sync : active"; else say "  TDP sync service oxp3-tdp-sync : inactive/missing"; fi
fi
PANEL_PSR="$(panel_debugfs i915_edp_psr_status 'PSR mode')"; PANEL_PSR="${PANEL_PSR:-?}"
PANEL_LOBF="$(panel_debugfs eDP-1/i915_edp_lobf_info 'LOBF status')"; PANEL_LOBF="${PANEL_LOBF:-?}"
if panel_fix_needed; then
    say "  OLED power saving (running) : PSR $PANEL_PSR, LOBF $PANEL_LOBF   expected disabled for both on BIOS $PANEL_BIOS_MIN and later ('?' = needs sudo to read)"
    if systemctl is-active -q oxp3-panel-fix.service 2>/dev/null; then say "  panel fix service oxp3-panel-fix : active"; else say "  panel fix service oxp3-panel-fix : inactive/missing"; fi
elif panel_is_oled; then
    say "  OLED power saving (running) : PSR $PANEL_PSR, LOBF $PANEL_LOBF   driver default kept on BIOS ${BIOS_VER:-?} (the panel fix is for BIOS $PANEL_BIOS_MIN and later, --force-panel overrides)"
fi
if have_rapl_pkg; then
    if findmnt -n -T /sys/class/powercap/intel-rapl:0/energy_uj -o SOURCE 2>/dev/null | grep -q oxp3-rapl; then RAPL_STATE="coarse copy published (overlay can read it)"; else RAPL_STATE="root-only (overlay shows no CPU power)"; fi
    say "  CPU power for the overlay : $RAPL_STATE"
fi
if dmc_applies; then
    if [ "$(dmc_system_sha)" = "$DMC_SHA256" ]; then DMC_SRC="SteamOS ships v2.20"; elif dmc_override_ok; then DMC_SRC="v2.20 override in place"; else DMC_SRC="SteamOS ships a newer DMC, no override"; fi
    say "  display firmware DMC : running ${DMC_RUNNING:-?} ($DMC_SRC)   expected v2.20 (newer DMC caps VRR at 70-80 fps)"
fi
if systemctl --user is-enabled -q oxp3-audio-route.service 2>/dev/null && systemctl is-enabled -q oxp3-audio-resume.service 2>/dev/null; then
    say "  speaker route check (boot/resume) : enabled"
else
    say "  speaker route check (boot/resume) : missing (speakers may stay silent after boot or resume)"
fi
if igpu_without_hwmon; then
    if [ -f "$MANGO_DROPIN" ] && mango_bin_ok; then MANGO_STATE="patched mangoapp installed$(mango_matches || echo ", but SteamOS has another mangohud version: the stock overlay runs")"; else MANGO_STATE="stock mangoapp (no GPU power/temperature)"; fi
    say "  GPU power/temperature for the overlay : $MANGO_STATE"
fi
if xe_gpu; then
    if xevma_loaded; then XEVMA_STATE="loaded, $(xevma_handled) oversized rebinds handled since boot"
    elif xevma_kernel_ok; then XEVMA_STATE="not loaded (big games can crash with \"out of memory\" after sleep)"
    else XEVMA_STATE="not available for kernel $KVER (the module is built for $XEVMA_FOR)"; fi
    say "  games after sleep (xevmafix) : $XEVMA_STATE"
fi
if [ "$GYRO_ON" = 1 ]; then
    say "  gyro (experimental) : enabled ; IMU $([ "$IMU_ACTIVE" = 1 ] && echo "visible to the kernel (ACPI override active)" || echo "NOT visible yet (ACPI override not loaded: reboot needed)") ; patched InputPlumber $(gyro_bin_ok && echo present || echo missing)"
elif [ "$GYRO_WANT" = 1 ]; then
    say "  gyro (experimental) : wanted but unavailable - $GYRO_BLOCK"
else
    say "  gyro (experimental) : not enabled (opt in with --gyro)"
fi
if [ -n "$OXP_DEV" ]; then
    say "  hid-oxp MCU driver (paddles) : $(basename "$OXP_DEV") gamepad_mode=$OXP_MODE button_m1=$OXP_M1 button_m2=$OXP_M2   expected xinput and two different F13-F24 keys"
else
    say "  hid-oxp MCU driver (paddles) : not bound (hid-oxp not bound to 1A86:FE00 iface 2 - kernel lacks hid-oxp or it was unbound)"
fi
RO_STATUS="$(steamos-readonly status 2>/dev/null | head -n1 || true)"   # note: exits non-zero when disabled
[ -n "$RO_STATUS" ] || RO_STATUS=unknown
say "  steamos-readonly : $RO_STATUS"
if sdtdp_installed; then
    say "  SimpleDeckyTDP-Intel : $(sdtdp_version)$([ -d "$SDTDP_UPSTREAM" ] && echo ", the original SimpleDeckyTDP is installed too")"
elif have_decky; then
    say "  SimpleDeckyTDP-Intel : not installed (a normal run asks, or --sdtdp)"
else
    say "  SimpleDeckyTDP-Intel : Decky Loader is not installed ($SDTDP_README)"
fi
# Wi-Fi / Bluetooth firmware state. The kernel names the firmware family it wants in the boot log; the package that
# provides "linux-firmware" on SteamOS (linux-firmware-neptune) does not carry every family.
IWL_DEV=""   # Intel network controller (class 0x0280) - present even when iwlwifi gave up for lack of firmware
for _d in /sys/bus/pci/devices/*; do
    if [ "$(cat "$_d/class" 2>/dev/null)" = "0x028000" ] && [ "$(cat "$_d/vendor" 2>/dev/null)" = "0x8086" ]; then IWL_DEV="$(basename "$_d")"; break; fi
done
WL_IF="$(ls -d /sys/class/net/*/wireless 2>/dev/null | head -n1 | cut -d/ -f5 || true)"
IWL_FAMILY="$(journalctl -k -b 0 --no-pager 2>/dev/null | sed -n 's/.*minimum version required: \(iwlwifi-[^ ]*\)-c\{0,1\}[0-9]*$/\1/p' | tail -n1)"
[ -n "$IWL_FAMILY" ] || IWL_FAMILY="$(journalctl -k -b 0 --no-pager 2>/dev/null | sed -n 's/.*Direct firmware load for \(iwlwifi-[^ ]*\)-c\{0,1\}[0-9]*\.ucode failed.*/\1/p' | tail -n1)"
BT_FAMILY="$(journalctl -k -b 0 --no-pager 2>/dev/null | sed -n 's/.*Failed to load Intel firmware file intel\/\(ibt-[0-9a-f]*-[0-9a-f]*\)-.*/\1/p' | tail -n1)"
WIFI_MISSING=0; BT_MISSING=0
[ -n "$IWL_DEV" ] && [ -z "$WL_IF" ] && WIFI_MISSING=1
[ -n "$BT_FAMILY" ] && ! ls /usr/lib/firmware/intel/"$BT_FAMILY"-* >/dev/null 2>&1 && BT_MISSING=1
if [ -n "$IWL_DEV" ]; then
    say "  Wi-Fi (Intel $IWL_DEV) : $([ -n "$WL_IF" ] && echo "interface $WL_IF present" || echo "NO wireless interface - firmware ${IWL_FAMILY:-?} missing")"
else
    say "  Wi-Fi : no Intel network controller found"
fi
if [ -n "$BT_FAMILY" ]; then say "  Bluetooth firmware intel/$BT_FAMILY : $([ "$BT_MISSING" = 1 ] && echo MISSING || echo present)"; fi
if command -v pacman >/dev/null 2>&1 && pacman -Q linux-firmware >/dev/null 2>&1; then
    say "  linux-firmware package : $(pacman -Q linux-firmware | tr ' ' '-')   (SteamOS' own package; may lack newer chips)"
fi

if [ "$MODE" = "--check" ]; then
    hdr "check-only, nothing changed"
    ok=1
    if [ "$SKIP_WIFI" != 1 ] && { [ "$WIFI_MISSING" = 1 ] || [ "$BT_MISSING" = 1 ]; }; then
        say "  [diff] Wi-Fi/Bluetooth firmware missing (apply extracts it from linux-firmware-intel)"; ok=0
    fi
    same_content "$GRUB_D_FILE" "$GRUB_D_CONTENT" || { say "  [diff] grub.d file missing or differs"; ok=0; }
    if have_split_lock_detect; then
        same_content "$SPLITLOCK_FILE" "$SPLITLOCK_CONTENT" || { say "  [diff] split-lock grub.d file missing or differs"; ok=0; }
        [ "$SL_OK" = 1 ] || { say "  [diff] kernel not running with split_lock_detect=off"; ok=0; }
        case "$SL_TRACES" in 0|'?') ;; *) say "  [diff] $SL_TRACES split-lock reports queued by steamos-log-submitter (apply removes them)"; ok=0 ;; esac
    fi
    same_content "$MODPROBE_FILE" "$MODPROBE_CONTENT" || { say "  [diff] modprobe file missing or differs"; ok=0; }
    same_content "$LUA_HDR" "$LUA_HDR_CONTENT" || { say "  [diff] HDR lua missing or differs"; ok=0; }
    if [ -f "$LUA_NOHDR" ]; then say "  [diff] old nohdr lua still present"; ok=0; fi
    same_content "$VOLKEY_PY" "$VOLKEY_PY_CONTENT" || { say "  [diff] volkey .py missing or differs"; ok=0; }
    same_content "$VOLKEY_UNIT" "$VOLKEY_UNIT_CONTENT" || { say "  [diff] volkey unit missing or differs"; ok=0; }
    systemctl is-enabled -q oxp3-volkey-fix.service 2>/dev/null || { say "  [diff] oxp3-volkey-fix.service not enabled"; ok=0; }
    same_content "$BATT_SH" "$BATT_SH_CONTENT" || { say "  [diff] battery clamp script missing or differs"; ok=0; }
    same_content "$BATT_UNIT" "$BATT_UNIT_CONTENT" || { say "  [diff] battery clamp unit missing or differs"; ok=0; }
    systemctl is-enabled -q oxp3-battery-clamp.service 2>/dev/null || { say "  [diff] oxp3-battery-clamp.service not enabled"; ok=0; }
    if have_rapl; then
        same_content "$TDP_SH" "$TDP_SH_CONTENT" || { say "  [diff] TDP sync script missing or differs"; ok=0; }
        same_content "$TDP_UNIT" "$TDP_UNIT_CONTENT" || { say "  [diff] TDP sync unit missing or differs"; ok=0; }
        systemctl is-enabled -q oxp3-tdp-sync.service 2>/dev/null || { say "  [diff] oxp3-tdp-sync.service not enabled"; ok=0; }
    fi
    if panel_fix_needed; then
        same_content "$PANEL_SH" "$PANEL_SH_CONTENT" || { say "  [diff] panel fix script missing or differs"; ok=0; }
        same_content "$PANEL_UNIT" "$PANEL_UNIT_CONTENT" || { say "  [diff] panel fix unit missing or differs"; ok=0; }
        systemctl is-enabled -q oxp3-panel-fix.service 2>/dev/null || { say "  [diff] oxp3-panel-fix.service not enabled"; ok=0; }
        if [ "$PANEL_PSR" != "?" ] && [ "$PANEL_LOBF" != "?" ] && { [ "$PANEL_PSR" != disabled ] || [ "$PANEL_LOBF" != disabled ]; }; then
            say "  [diff] PSR or LOBF is still on for the panel (reboot after apply)"; ok=0
        fi
    fi
    if have_rapl_pkg; then
        same_content "$RAPL_PY" "$RAPL_PY_CONTENT" || { say "  [diff] CPU power overlay script missing or differs"; ok=0; }
        same_content "$RAPL_UNIT" "$RAPL_UNIT_CONTENT" || { say "  [diff] CPU power overlay unit missing or differs"; ok=0; }
        systemctl is-enabled -q oxp3-rapl-overlay.service 2>/dev/null || { say "  [diff] oxp3-rapl-overlay.service not enabled"; ok=0; }
    fi
    if igpu_without_hwmon; then
        mango_bin_ok || { say "  [diff] patched mangoapp missing or differs (apply takes it from the release archive)"; ok=0; }
        same_content "$MANGO_LAUNCH" "$MANGO_LAUNCH_CONTENT" || { say "  [diff] mangoapp launcher missing or differs"; ok=0; }
        same_content "$MANGO_DROPIN" "$MANGO_DROPIN_CONTENT" || { say "  [diff] mangoapp user drop-in missing or differs"; ok=0; }
        mango_matches || say "  [info] SteamOS ships another mangohud than the patched build ($MANGO_FOR): the overlay uses the stock mangoapp"
    fi
    same_content "$AUDIO_SH" "$AUDIO_SH_CONTENT" || { say "  [diff] speaker route script missing or differs"; ok=0; }
    same_content "$AUDIO_UNIT" "$AUDIO_UNIT_CONTENT" || { say "  [diff] speaker route user unit missing or differs"; ok=0; }
    systemctl --user is-enabled -q oxp3-audio-route.service 2>/dev/null || { say "  [diff] oxp3-audio-route.service (user) not enabled"; ok=0; }
    same_content "$AUDIO_RESUME_UNIT" "$AUDIO_RESUME_UNIT_CONTENT" || { say "  [diff] speaker route resume unit missing or differs"; ok=0; }
    systemctl is-enabled -q oxp3-audio-resume.service 2>/dev/null || { say "  [diff] oxp3-audio-resume.service not enabled"; ok=0; }
    if dmc_applies; then
        if [ "$(dmc_system_sha)" != "$DMC_SHA256" ] && ! dmc_override_ok; then say "  [diff] SteamOS ships a newer DMC and the v2.20 override is missing"; ok=0; fi
        if [ -n "$DMC_RUNNING" ] && [ "$DMC_RUNNING" != v2.20 ]; then say "  [diff] the running kernel loaded DMC $DMC_RUNNING (reboot after apply)"; ok=0; fi
    fi
    if xe_gpu && xevma_kernel_ok; then
        xevma_ko_ok || { say "  [diff] xevmafix.ko missing or differs (apply takes it from the release archive)"; ok=0; }
        same_content "$XEVMA_UNIT" "$XEVMA_UNIT_CONTENT" || { say "  [diff] xevmafix unit missing or differs"; ok=0; }
        systemctl is-enabled -q oxp3-xevmafix.service 2>/dev/null || { say "  [diff] oxp3-xevmafix.service not enabled"; ok=0; }
        xevma_loaded || { say "  [diff] xevmafix is not loaded"; ok=0; }
    elif xe_gpu; then
        say "  [info] xevmafix is built for kernel $XEVMA_FOR and this is $KVER: big games can crash after sleep until a rebuilt module ships"
    fi
    if [ "$SDTDP_WANT" = 1 ] && have_decky; then
        sdtdp_installed || { say "  [diff] SimpleDeckyTDP-Intel is opted in but not installed"; ok=0; }
        [ -d "$SDTDP_UPSTREAM" ] && { say "  [diff] the original SimpleDeckyTDP is installed next to SimpleDeckyTDP-Intel; the two override each other (apply asks whether to replace it)"; ok=0; }
    fi
    same_content "$IP_YAML" "$IP_YAML_CONTENT" || { say "  [diff] IP yaml missing or differs"; ok=0; }
    same_content "$IP_CAPMAP" "$IP_CAPMAP_CONTENT" || { say "  [diff] IP capability map missing or differs"; ok=0; }
    systemctl is-enabled -q inputplumber.service 2>/dev/null || { say "  [diff] inputplumber.service not enabled"; ok=0; }
    if [ "$GYRO_ON" = 1 ]; then
        gyro_bin_ok || { say "  [diff] patched InputPlumber missing or differs (apply downloads it)"; ok=0; }
        same_content "$GYRO_LAUNCH" "$GYRO_LAUNCH_CONTENT" || { say "  [diff] gyro launcher missing or differs"; ok=0; }
        same_content "$GYRO_DROPIN" "$GYRO_DROPIN_CONTENT" || { say "  [diff] gyro systemd drop-in missing or differs"; ok=0; }
        [ -f "$GYRO_CONF" ] || { say "  [diff] $GYRO_CONF missing"; ok=0; }
        [ "$(acpi_img_sha)" = "$ACPI_IMG_SHA256" ] || { say "  [diff] $ACPI_IMG missing or differs"; ok=0; }
        same_content "$GRUB_IMU_FILE" "$GRUB_IMU_CONTENT" || { say "  [diff] $GRUB_IMU_FILE missing or differs"; ok=0; }
        [ "$IMU_ACTIVE" = 1 ] || { say "  [diff] the IMU is not visible to the running kernel (ACPI override not loaded)"; ok=0; }
    elif [ "$GYRO_WANT" = 1 ]; then
        say "  [info] gyro is wanted but cannot be used here: $GYRO_BLOCK"
    fi
    if [ -z "$OXP_DEV" ]; then say "  [diff] hid-oxp not bound, paddles will be silent"; ok=0;
    elif ! paddles_ok; then say "  [diff] paddle driver state differs (apply re-asserts via sysfs)"; ok=0; fi
    if nvme_bug_present && [ "$CMD_OK" != 1 ]; then say "  [diff] kernel not running with nvme.noacpi=1"; ok=0; fi
    if [ $ok = 1 ]; then say "  RESULT: all fixes in place"; else say "  RESULT: run without --check to apply"; fi
    exit 0
fi

# ---- h. restore MCU button-table page 3 (Home + Xbox) --------
# background: the OXP3 MCU keeps its button table in 3 pages of 9 slots [id, func, v1, v2, 0, 0].
# hid-oxp rewrites pages 1-2 at every boot (that is normal and harmless). Page 3 holds the chassis keys
# (Home = 0x24 -> func 02 02 05; Xbox = one of 0x21/0x25..0x2B, factory mapping). A foreign write of page 3
# (e.g. a test tool) wipes them and NOTHING (reboot, full power-off, reset_buttons) brings them back - only
# writing page 3 again does. func 0x05 = "restore this key's factory function" (same code the OneXPlayer Apex
# community tools use), so unknown ids are written as [id 05 00 00] which is a no-op for ids the MCU doesn't have.
# This was verified on this unit on 2026-09-12 (Xbox key came back immediately). It is NOT part of normal apply.
if [ "$MODE" = "--mcu-restore" ]; then
    hdr "Restore MCU button-table page 3 (Home 0x24 + factory 0x21,0x25-0x2B)"
    if [ -z "$OXP_DEV" ]; then say "  hid-oxp not bound, cannot locate hidraw node"; exit 1; fi
    HR="$(ls -d "$OXP_DEV"/hidraw/hidraw* 2>/dev/null | head -n1)"; HR="/dev/$(basename "${HR:-none}")"
    [ -e "$HR" ] || { say "  hidraw node not found under $OXP_DEV"; exit 1; }
    say "  target: $HR  ($(basename "$OXP_DEV"))"
    say "  will write ONE 64-byte packet:"
    say "    B4 3F 01 | 02 38 20 03 01 | 24 02 02 05 00 00 | 21 05 00 00 00 00 | 25..2B 05 00 00 00 00 | .. | 3F B4"
    say "  Use ONLY when Home/Xbox are dead; pages 1-2 (ABXY/paddles) untouched."
    say ""
    say "  ############################  DANGER  ############################"
    say "  This writes the controller MCU directly, bypassing the kernel driver. The table is stored"
    say "  persistently (survives reboot and power-off) and cannot be read back to verify. A bad write"
    say "  can leave Home/Xbox dead for good. If both keys work, do NOT run this option."
    say "  #########################################################################"
    say ""
    if [ "$ASSUME_YES" != 1 ]; then
        [ -t 0 ] || { say "  non-interactive: pass --yes"; exit 1; }
        read -r -p "  type yes to continue: " _ans; [ "$_ans" = yes ] || { say "  cancelled."; exit 0; }
    fi
    sudo -v
    sudo python3 - "$HR" <<'PY'
import sys
hr = sys.argv[1]
def slot(bid, func, v1, v2): return bytes([bid, func, v1, v2, 0, 0])
page = bytearray([0x02, 0x38, 0x20, 0x03, 0x01]) + slot(0x24, 0x02, 0x02, 0x05)
for bid in (0x21, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B):
    page += slot(bid, 0x05, 0x00, 0x00)
assert len(page) == 59
pkt = bytearray(64); pkt[0:3] = bytes([0xB4, 0x3F, 0x01]); pkt[3:3+len(page)] = page; pkt[62:64] = bytes([0x3F, 0xB4])
with open(hr, "r+b", buffering=0) as f:
    f.write(bytes(pkt))
print("  written:", " ".join(f"{b:02x}" for b in pkt[:20]), "...")
PY
    say "  Done. Press Xbox / Home now; the MCU persists this table."
    exit 0
fi

# ---- g. revert ---------------------------------------------------------
if [ "$MODE" = "--revert" ]; then
    hdr "Reverting all fixes"
    sudo -v
    if [ -f "$GRUB_D_FILE" ]; then sudo rm -f "$GRUB_D_FILE"; say "  removed $GRUB_D_FILE"; sudo update-grub; NEED_REBOOT=1; fi
    if [ -f "$SPLITLOCK_FILE" ]; then sudo rm -f "$SPLITLOCK_FILE"; say "  removed $SPLITLOCK_FILE"; sudo update-grub; NEED_REBOOT=1; fi
    if [ -f "$MODPROBE_FILE" ]; then sudo rm -f "$MODPROBE_FILE"; say "  removed $MODPROBE_FILE"; NEED_REBOOT=1; fi
    if gyro_installed; then remove_gyro; fi
    rm -f "$GYRO_ON_FILE" "$GYRO_OFF_FILE"
    if [ -f "$SDTDP_ON_FILE" ]; then remove_sdtdp; fi
    rm -f "$SDTDP_ON_FILE" "$SDTDP_OFF_FILE"
    if [ -f "$IP_CAPMAP" ]; then sudo rm -f "$IP_CAPMAP"; say "  removed $IP_CAPMAP"; fi
    if [ -f "$IP_YAML" ]; then sudo systemctl disable --now inputplumber.service 2>/dev/null || true; sudo rm -f "$IP_YAML"; say "  InputPlumber disabled and OXP3 config removed (gamepad back to plain xpad)"; fi
    if [ -f "$VOLKEY_UNIT" ]; then sudo systemctl disable --now oxp3-volkey-fix.service 2>/dev/null || true; sudo rm -f "$VOLKEY_UNIT"; sudo systemctl daemon-reload; say "  oxp3-volkey-fix.service stopped and removed (volume keys back to raw EC behavior)"; fi
    if [ -f "$VOLKEY_PY" ]; then rm -f "$VOLKEY_PY"; say "  removed $VOLKEY_PY"; fi
    if [ -f "$BATT_UNIT" ]; then sudo systemctl disable --now oxp3-battery-clamp.service 2>/dev/null || true; sudo rm -f "$BATT_UNIT"; sudo systemctl daemon-reload; say "  oxp3-battery-clamp.service stopped and removed (raw kernel battery values again)"; fi
    if [ -f "$BATT_SH" ]; then rm -f "$BATT_SH"; say "  removed $BATT_SH"; fi
    if [ -f "$TDP_UNIT" ]; then sudo systemctl disable --now oxp3-tdp-sync.service 2>/dev/null || true; sudo rm -f "$TDP_UNIT"; sudo systemctl daemon-reload; say "  oxp3-tdp-sync.service stopped and removed (MSR PL1 back to the firmware value)"; fi
    if [ -f "$TDP_SH" ]; then rm -f "$TDP_SH"; say "  removed $TDP_SH"; fi
    if [ -f "$PANEL_UNIT" ]; then sudo systemctl disable oxp3-panel-fix.service 2>/dev/null || true; sudo rm -f "$PANEL_UNIT"; sudo systemctl daemon-reload; say "  oxp3-panel-fix.service removed (the driver's PSR and LOBF return after the reboot)"; NEED_REBOOT=1; fi
    if [ -f "$PANEL_SH" ]; then rm -f "$PANEL_SH"; say "  removed $PANEL_SH"; fi
    if [ -f "$XEVMA_UNIT" ]; then sudo systemctl disable oxp3-xevmafix.service 2>/dev/null || true; sudo rm -f "$XEVMA_UNIT"; sudo systemctl daemon-reload; say "  oxp3-xevmafix.service removed (the module stays loaded until the reboot)"; xevma_loaded && NEED_REBOOT=1; fi
    if [ -f "$XEVMA_KO" ]; then rm -f "$XEVMA_KO"; say "  removed $XEVMA_KO"; fi
    if [ -f "$RAPL_UNIT" ]; then sudo systemctl disable --now oxp3-rapl-overlay.service 2>/dev/null || true; sudo rm -f "$RAPL_UNIT"; sudo systemctl daemon-reload; say "  oxp3-rapl-overlay.service stopped and removed (CPU energy counter root-only again)"; fi
    if [ -f "$RAPL_PY" ]; then rm -f "$RAPL_PY"; say "  removed $RAPL_PY"; fi
    if [ -f "$MANGO_DROPIN" ]; then sudo rm -f "$MANGO_DROPIN"; sudo rmdir "$(dirname "$MANGO_DROPIN")" 2>/dev/null || true; user_systemctl daemon-reload; say "  removed $MANGO_DROPIN (stock mangoapp from the next overlay start)"; fi
    for _f in "$MANGO_LAUNCH" "$MANGO_BIN"; do [ -f "$_f" ] && { rm -f "$_f"; say "  removed $_f"; }; done
    if [ -f "$DMC_OVERRIDE" ]; then sudo rm -f "$DMC_OVERRIDE"; say "  removed $DMC_OVERRIDE (the packaged DMC loads after the reboot)"; NEED_REBOOT=1; fi
    if [ -f "$AUDIO_RESUME_UNIT" ]; then sudo systemctl disable oxp3-audio-resume.service 2>/dev/null || true; sudo rm -f "$AUDIO_RESUME_UNIT"; sudo systemctl daemon-reload; say "  removed $AUDIO_RESUME_UNIT"; fi
    if [ -f "$AUDIO_UNIT" ]; then user_systemctl disable --now oxp3-audio-route.service; rm -f "$AUDIO_UNIT"; user_systemctl daemon-reload; say "  removed $AUDIO_UNIT (no speaker route check any more)"; fi
    if [ -f "$AUDIO_SH" ]; then rm -f "$AUDIO_SH"; say "  removed $AUDIO_SH"; fi
    if [ -f "$LUA_HDR" ]; then mv -f "$LUA_HDR" "$USER_HOME/oxp3-oled-hdr.lua.disabled"; say "  HDR lua moved to $USER_HOME/oxp3-oled-hdr.lua.disabled"; NEED_RELOGIN=1; fi
    if [ -f "$LUA_NOHDR_BAK" ] && [ ! -f "$LUA_NOHDR" ]; then mkdir -p "$LUA_DIR"; cp -f "$LUA_NOHDR_BAK" "$LUA_NOHDR"; say "  nohdr lua restored (prevents a black screen when HDR is on)"; NEED_RELOGIN=1; fi
    say "revert done. (The Wi-Fi firmware step is not undone: linux-firmware stays installed.)"
    if [ $NEED_REBOOT = 1 ]; then say "reboot required for the kernel parameter change to take effect."; elif [ $NEED_RELOGIN = 1 ]; then say "re-enter game mode to reload the lua."; fi
    exit 0
fi

if [ "$MODE" != "apply" ]; then
    say "unknown option: $MODE  (valid: --check | --revert | --mcu-restore)"; exit 2
fi

# ---- apply --------------------------------------------------------------
if [ "$GYRO_REQ" = "" ] && [ "$GYRO_ON" = 0 ] && [ "$GYRO_WANT" = 0 ] && [ -z "$GYRO_BLOCK" ] && [ ! -f "$GYRO_OFF_FILE" ] && [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    say ""
    say "  Optional, EXPERIMENTAL: gyroscope. The kernel cannot see this device's Bosch BMI260 on its own. Enabling this installs"
    say "  an ACPI table override (needs a reboot) and swaps InputPlumber for a patched build from the project's GitHub release"
    say "  (sha256-checked; it falls back to the stock binary automatically if it cannot run). Steam's gyro settings then work."
    say "  Drift is reduced but not eliminated. Undo any time with: $0 --no-gyro"
    read -r -p "  Enable the experimental gyro support? (y/N) " _ans
    case "$_ans" in
        y|Y) GYRO_REQ=1; GYRO_WANT=1; GYRO_ON=1; set_gyro_yaml ;;
        *) GYRO_DECLINED=1 ;;
    esac
fi
SDTDP_ASKED=0
if [ "$SDTDP_REQ" = "" ] && [ "$SDTDP_WANT" = 0 ] && ! sdtdp_installed && have_decky && [ ! -f "$SDTDP_OFF_FILE" ] && [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    say ""
    say "  Optional (step 14): SimpleDeckyTDP-Intel, a TDP plugin for this device by kas5852 (a fork of SimpleDeckyTDP)."
    say "  Its CPU Boost control has Off / Smart / Full per game; Smart caps the CPU clocks so more of the TDP goes to"
    say "  the GPU, which smooths stutter in CPU-heavy games (RE4 at 30 W: 1% low fps +48 %)."
    say "  It comes with this release (sha256 pinned); later updates come from the fork through the plugin's own updater."
    if [ -d "$SDTDP_UPSTREAM" ]; then
        say "  You have the original SimpleDeckyTDP installed. Installing SimpleDeckyTDP-Intel REPLACES it: the original"
        say "  is removed (two TDP plugins would override each other). Your profiles are copied, and the original's"
        say "  settings stay, so reinstalling it from the Decky store later brings them back."
    fi
    say "  Undo any time with: $0 --no-sdtdp"
    read -r -p "  Install SimpleDeckyTDP-Intel$([ -d "$SDTDP_UPSTREAM" ] && echo " and replace SimpleDeckyTDP")? (y/N) " _ans
    case "$_ans" in
        y|Y) SDTDP_REQ=1; SDTDP_WANT=1; SDTDP_ASKED=1 ;;
        *) SDTDP_DECLINED=1 ;;
    esac
fi
# the original SimpleDeckyTDP is only removed with the user's consent: the answer above, --sdtdp, or a confirmation
SDTDP_REPLACE=0
if [ "$SDTDP_WANT" = 1 ] && [ "$SDTDP_REQ" != 0 ] && [ -d "$SDTDP_UPSTREAM" ] && have_decky; then
    if [ "$SDTDP_ASKED" = 1 ]; then
        SDTDP_REPLACE=1
    elif [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
        say ""
        say "  The original SimpleDeckyTDP is installed$(sdtdp_installed && echo " next to SimpleDeckyTDP-Intel; the two override each other"). Replacing it removes the"
        say "  original (its settings stay, reinstalling it from the Decky store brings them back)."
        read -r -p "  Replace SimpleDeckyTDP with SimpleDeckyTDP-Intel? (y/N) " _ans
        case "$_ans" in y|Y) SDTDP_REPLACE=1 ;; esac
    elif [ "$SDTDP_REQ" = 1 ]; then
        SDTDP_REPLACE=1   # --sdtdp given explicitly in a non-interactive run
    fi
fi
hdr "Applying fixes (will ask for sudo password)"
say "  will check and write as needed:"
if [ "$SKIP_WIFI" = 1 ]; then
    say "   0) Wi-Fi firmware   [SKIPPED: --no-wifi]"
else
    say "   0) Wi-Fi/Bluetooth firmware from linux-firmware-intel   $({ [ "$WIFI_MISSING" = 1 ] || [ "$BT_MISSING" = 1 ]; } && echo "[will extract missing files]" || echo "[nothing missing]")"
fi
say "   1) $GRUB_D_FILE (nvme.noacpi=1) + update-grub   $(nvme_bug_present && echo "[SSD matches]" || echo "[SKIPPED: not the affected SSD; use --force-nvme]")"
say "   2) $MODPROBE_FILE (xe enable_dsb=0)"
say "   3) $LUA_HDR (gamescope HDR lua) and remove 99-oxp3-nohdr.lua"
say "   4) $VOLKEY_PY + $VOLKEY_UNIT (volume-key fix)   $(have_evdev && echo "[python3-evdev OK]" || echo "[SKIPPED: python3 evdev missing]")"
say "   5) $IP_YAML + $IP_CAPMAP + enable inputplumber   $(have_ip && echo "[inputplumber OK]" || echo "[SKIPPED: inputplumber missing]")"
say "      + paddle driver state: hid-oxp gamepad_mode=xinput, button_m1/m2 = two different F13-F24 keys   $([ -n "$OXP_DEV" ] && echo "[hid-oxp OK]" || echo "[SKIPPED: hid-oxp not bound]")"
say "   6) $BATT_SH + $BATT_UNIT (battery percentage clamp)   $([ -r /sys/class/power_supply/BAT0/energy_now ] && echo "[battery OK]" || echo "[SKIPPED: no energy_* battery]")"
if [ "$GYRO_REQ" = 0 ]; then
    say "   7) gyro (experimental): REMOVE the ACPI override, the patched InputPlumber and its files (--no-gyro)"
elif [ "$GYRO_ON" = 1 ]; then
    say "   7) gyro (experimental): $ACPI_IMG + $GRUB_IMU_FILE (ACPI override, update-grub), patched InputPlumber $(gyro_bin_ok && echo "[present]" || echo "[from the release archive]") + $GYRO_DROPIN"
elif [ "$GYRO_WANT" = 1 ]; then
    say "   7) gyro (experimental): [SKIPPED: $GYRO_BLOCK]"
else
    say "   7) gyro (experimental): not enabled (opt in with --gyro)"
fi
say "   8) $TDP_SH + $TDP_UNIT (MSR package PL1 follows the MMIO PL1)   $(have_rapl && echo "[RAPL OK]" || echo "[SKIPPED: no MSR/MMIO package RAPL]")"
say "   9) $SPLITLOCK_FILE (split_lock_detect=off) + update-grub, and remove the split-lock reports steamos-log-submitter queued   $(have_split_lock_detect && echo "[CPU has split-lock detection]" || echo "[SKIPPED: the CPU has no split-lock detection]")"
say "  10) $RAPL_PY + $RAPL_UNIT (CPU/GPU energy for the performance overlay, coarse copies of the counters)   $(have_rapl_pkg && echo "[RAPL OK]" || echo "[SKIPPED: no intel-rapl:0]")"
say "      + $MANGO_BIN + $MANGO_DROPIN (GPU power/temperature)   $(igpu_without_hwmon && echo "[integrated xe GPU]" || echo "[SKIPPED: the GPU has its own sensors]")"
say "  11) $DMC_OVERRIDE (display firmware DMC v2.20, VRR)   $(dmc_applies || echo "[SKIPPED: this GPU does not use $DMC_NAME]")$(dmc_applies && { [ "$(dmc_system_sha)" = "$DMC_SHA256" ] && echo "[SteamOS ships v2.20, nothing to do]" || echo "[SteamOS ships a newer DMC]"; })"
say "  12) $AUDIO_SH + $AUDIO_UNIT + $AUDIO_RESUME_UNIT (speakers after boot/resume when the headphone jack is empty)"
if [ "$FORCE_PANEL" = 1 ]; then PANEL_NOTE="[forced: --force-panel]"
elif panel_fix_needed; then PANEL_NOTE="[AMS881KB01 on BIOS $BIOS_VER]"
else PANEL_NOTE="[SKIPPED: needs the AMS881KB01 panel on BIOS $PANEL_BIOS_MIN or later; use --force-panel]"; fi
say "  13) $PANEL_SH + $PANEL_UNIT (OLED: LOBF and PSR/Panel Replay off at boot)   $PANEL_NOTE"
if ! xe_gpu; then XEVMA_NOTE="[SKIPPED: not an xe GPU]"
elif ! xevma_kernel_ok; then XEVMA_NOTE="[SKIPPED: built for kernel $XEVMA_FOR, this is $KVER]"
elif xevma_loaded; then XEVMA_NOTE="[loaded]"
else XEVMA_NOTE="[from the release archive, sha256 pinned, loads right away]"; fi
if [ "$SDTDP_REQ" = 0 ]; then
    say "  14) SimpleDeckyTDP-Intel: REMOVE $SDTDP_PLUGIN (--no-sdtdp)"
elif [ "$SDTDP_WANT" = 1 ] && ! have_decky; then
    say "  14) SimpleDeckyTDP-Intel: [SKIPPED: Decky Loader is not installed, see $SDTDP_README]"
elif [ "$SDTDP_WANT" = 1 ]; then
    say "  14) SimpleDeckyTDP-Intel Decky plugin $(sdtdp_installed && echo "[$(sdtdp_version) installed]" || echo "[$SDTDP_VERSION from the release archive, sha256 pinned]")$([ -d "$SDTDP_UPSTREAM" ] && { [ "$SDTDP_REPLACE" = 1 ] && echo " and replace the original SimpleDeckyTDP" || echo " [original SimpleDeckyTDP kept]"; })"
else
    say "  14) SimpleDeckyTDP-Intel: not installed (a normal run asks once, or --sdtdp; see $SDTDP_README)"
fi
say "  15) $XEVMA_KO + $XEVMA_UNIT (games survive waking from sleep)   $XEVMA_NOTE"
if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then read -r -p "  Continue? (y/N) " _ans; case "$_ans" in y|Y) ;; *) say "  cancelled."; exit 0 ;; esac; fi
sudo -v

# ---- 0. Wi-Fi / Bluetooth firmware --------------------------------------------------------------
# SteamOS' linux-firmware-neptune provides "linux-firmware" but not every chip family (the OXP3's BE201 needs
# iwlwifi-sc-a0-fm-c0-c10x + intel/ibt-00a0-0291-*). Download the repo's linux-firmware-intel package (cached) and
# extract only the missing families into /usr/lib/firmware; existing files are never overwritten and no package is
# replaced. Needs a writable rootfs and some network connection (USB Ethernet / USB tethering while Wi-Fi is down).
WIFI_FAILED=0
# the package is cached in /home, which survives OS updates, so after an update Wi-Fi can be restored without any network
FW_CACHE="$USER_HOME/.cache/oxp3-fix"
FW_CACHED="$(ls -t "$FW_CACHE"/linux-firmware-intel-*.pkg.tar.zst 2>/dev/null | head -n1 || true)"
HAVE_NET=0; ip route 2>/dev/null | grep -q '^default' && HAVE_NET=1
if [ "$SKIP_WIFI" = 1 ]; then
    say "  [skip] Wi-Fi firmware step disabled (--no-wifi)"
elif [ "$WIFI_MISSING" != 1 ] && [ "$BT_MISSING" != 1 ]; then
    say "  [skip] Wi-Fi/Bluetooth firmware: nothing missing"
elif ! command -v pacman >/dev/null 2>&1; then
    say "  [skip] pacman not found, cannot locate linux-firmware-intel"; WIFI_FAILED=1
elif [ "$HAVE_NET" != 1 ] && [ -z "$FW_CACHED" ]; then
    say "  [skip] no network connection and no cached package, cannot download linux-firmware-intel."
    say "         Connect USB Ethernet or USB tethering and run this script again."
    WIFI_FAILED=1
else
    hdr "0. Wi-Fi / Bluetooth firmware (from linux-firmware-intel)"
    if [ "$RO_STATUS" = "enabled" ]; then
        say "  rootfs is read-only; disabling so /usr/lib/firmware can be written (updates re-enable it)"
        sudo steamos-readonly disable
        RO_STATUS=disabled
    fi
    if [ "$HAVE_NET" != 1 ]; then
        say "  [offline] no network, using the cached $(basename "$FW_CACHED")"
        FW_URL="$FW_CACHED"
    else
        FW_URL="$(pacman -Sp linux-firmware-intel 2>/dev/null | grep -m1 '^http' || true)"
    fi
    if [ -z "$FW_URL" ]; then
        say "  [run] pacman -Sy   (package database sync, needed to locate linux-firmware-intel)"
        sudo pacman -Sy >/dev/null 2>&1 || true
        FW_URL="$(pacman -Sp linux-firmware-intel 2>/dev/null | grep -m1 '^http' || true)"
    fi
    if [ -z "$FW_URL" ]; then
        say "  [error] linux-firmware-intel not found in the configured repositories"; WIFI_FAILED=1
    else
        mkdir -p "$FW_CACHE"
        FW_PKG="$FW_CACHE/$(basename "$FW_URL")"
        if [ ! -s "$FW_PKG" ]; then
            say "  [run] downloading $(basename "$FW_URL") (about 130 MB) ..."
            curl -fL --retry 3 --progress-bar -o "$FW_PKG.part" "$FW_URL" && mv "$FW_PKG.part" "$FW_PKG" || { rm -f "$FW_PKG.part"; say "  [error] download failed"; WIFI_FAILED=1; }
        else
            say "  [skip] using cached $(basename "$FW_PKG")"
        fi
        if [ -s "$FW_PKG" ] && tar --zstd -tf "$FW_PKG" >/dev/null 2>&1; then
            FW_PATTERNS=""
            if [ "$WIFI_MISSING" = 1 ]; then
                if [ -n "$IWL_FAMILY" ]; then FW_PATTERNS="$FW_PATTERNS ${IWL_FAMILY}*"; else FW_PATTERNS="$FW_PATTERNS iwlwifi-*"; fi
            fi
            [ "$BT_MISSING" = 1 ] && FW_PATTERNS="$FW_PATTERNS ${BT_FAMILY}-*"
            FW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/oxp3-fw.XXXXXX")"
            say "  [run] extracting$FW_PATTERNS (files and symlinks; symlink targets are added as needed)"
            # shellcheck disable=SC2086
            tar --zstd -xf "$FW_PKG" -C "$FW_TMP" --wildcards --no-anchored $FW_PATTERNS 2>/dev/null || true
            # symlinks whose target is neither on the system nor in the extracted set: pull the target from the package too
            for _round in 1 2 3; do
                _more=""
                while IFS= read -r _l; do
                    _t="$(readlink "$_l")"; _dir="$(dirname "$_l")"
                    _sys="/usr/lib/firmware${_dir#"$FW_TMP"/usr/lib/firmware}/$_t"
                    [ -e "$_dir/$_t" ] || [ -e "$_sys" ] || _more="$_more $(basename "$_t")"
                done < <(find "$FW_TMP" -type l 2>/dev/null)
                [ -n "$_more" ] || break
                # shellcheck disable=SC2086
                tar --zstd -xf "$FW_PKG" -C "$FW_TMP" --wildcards --no-anchored $_more 2>/dev/null || true
            done
            _n=$(find "$FW_TMP" \( -type f -o -type l \) | wc -l)
            if [ "$_n" = 0 ]; then
                say "  [error] the package has no ${IWL_FAMILY:-iwlwifi}/${BT_FAMILY:-ibt} firmware (kernel/package version mismatch)"; WIFI_FAILED=1
            elif sudo cp -an "$FW_TMP/usr/lib/firmware/." /usr/lib/firmware/; then
                say "  [done] $_n firmware files/links in place (existing files untouched)"
                CHANGED=1; NEED_REBOOT=1
                if [ "$WIFI_MISSING" = 1 ]; then
                    say "  [run] reloading iwlwifi so Wi-Fi comes up now (Bluetooth needs the reboot)"
                    sudo modprobe -r iwlmld iwlmvm iwlwifi 2>/dev/null || true
                    sudo modprobe iwlwifi 2>/dev/null || true
                    sleep 4
                    WL_IF="$(ls -d /sys/class/net/*/wireless 2>/dev/null | head -n1 | cut -d/ -f5 || true)"
                    say "  Wi-Fi interface now: ${WL_IF:-still missing (check: journalctl -k | grep iwlwifi)}"
                fi
            else
                say "  [error] copying into /usr/lib/firmware failed"; WIFI_FAILED=1
            fi
            rm -rf "$FW_TMP"
        fi
    fi
fi
# re-read xe param now that sudo is available
XE_DSB="$(sudo cat /sys/module/xe/parameters/enable_dsb 2>/dev/null || echo '?')"
say "  xe enable_dsb (running, via sudo) : $XE_DSB"

# read-only rootfs
if [ "$RO_STATUS" = "enabled" ]; then
    say "  rootfs is read-only; disabling so /etc can be written (updates re-enable it)"
    sudo steamos-readonly disable
fi

# c. grub.d + update-grub  (only for the affected SSD)
if ! nvme_bug_present; then
    say "  [skip] NVMe is not a Predator GM7/1dee:1602 ($NVME_MODEL), not applying nvme.noacpi=1 (force with --force-nvme)"
elif same_content "$GRUB_D_FILE" "$GRUB_D_CONTENT"; then
    say "  [skip] $GRUB_D_FILE unchanged"
else
    sudo mkdir -p /etc/default/grub.d
    printf '%s\n' "$GRUB_D_CONTENT" | sudo tee "$GRUB_D_FILE" >/dev/null
    say "  [write] $GRUB_D_FILE"
    CHANGED=1
fi
if nvme_bug_present && { [ "$CMD_OK" = 0 ] || ! sudo grep -q 'nvme.noacpi=1' "$EFI_GRUB_CFG" 2>/dev/null; }; then
    say "  [run] update-grub -> $EFI_GRUB_CFG"
    sudo update-grub
    CHANGED=1
fi
CNT="$(sudo grep -c 'nvme.noacpi=1' "$EFI_GRUB_CFG" 2>/dev/null || echo 0)"
if ! nvme_bug_present; then :
elif [ "$CNT" -gt 0 ]; then
    say "  [verify] $EFI_GRUB_CFG contains nvme.noacpi=1 ($CNT times) OK"
else
    say "  [error] nvme.noacpi=1 NOT found in grub.cfg, check manually"
fi
if nvme_bug_present; then [ "$CMD_OK" = 1 ] || NEED_REBOOT=1; fi

if ! have_split_lock_detect; then
    say "  [skip] the CPU has no split-lock detection, not applying split_lock_detect=off"
else
if same_content "$SPLITLOCK_FILE" "$SPLITLOCK_CONTENT"; then
    say "  [skip] $SPLITLOCK_FILE unchanged"
else
    sudo mkdir -p "$(dirname "$SPLITLOCK_FILE")"
    printf '%s\n' "$SPLITLOCK_CONTENT" | sudo tee "$SPLITLOCK_FILE" >/dev/null
    say "  [write] $SPLITLOCK_FILE"; CHANGED=1
fi
if [ "$SL_OK" = 0 ] || ! sudo grep -q 'split_lock_detect=off' "$EFI_GRUB_CFG" 2>/dev/null; then
    say "  [run] update-grub -> $EFI_GRUB_CFG"
    sudo update-grub
    CHANGED=1
fi
if sudo grep -q 'split_lock_detect=off' "$EFI_GRUB_CFG" 2>/dev/null; then
    say "  [verify] $EFI_GRUB_CFG contains split_lock_detect=off OK"
else
    say "  [error] split_lock_detect=off NOT found in grub.cfg, check manually"
fi
[ "$SL_OK" = 1 ] || NEED_REBOOT=1
SL_TRACES="$(sls_split_lock_traces sudo)"
case "$SL_TRACES" in
    0) ;;
    '?') say "  [warn] could not read $SLS_TRACE_DIR, queued split-lock reports not checked" ;;
    *) if sudo grep -rlZ '"type": "split_lock"' "$SLS_TRACE_DIR" 2>/dev/null | sudo xargs -0 -r rm -f; then
           say "  [remove] $SL_TRACES queued split-lock reports from $SLS_TRACE_DIR"; CHANGED=1
       else
           say "  [error] could not remove the queued split-lock reports from $SLS_TRACE_DIR"
       fi ;;
esac
fi

# d. modprobe.d
if same_content "$MODPROBE_FILE" "$MODPROBE_CONTENT"; then
    say "  [skip] $MODPROBE_FILE unchanged"
else
    printf '%s\n' "$MODPROBE_CONTENT" | sudo tee "$MODPROBE_FILE" >/dev/null
    say "  [write] $MODPROBE_FILE"
    CHANGED=1
fi
case "$XE_DSB" in N|0) ;; *) NEED_REBOOT=1 ;; esac

# e. gamescope lua
mkdir -p "$LUA_DIR"
if same_content "$LUA_HDR" "$LUA_HDR_CONTENT"; then
    say "  [skip] $LUA_HDR unchanged"
else
    printf '%s\n' "$LUA_HDR_CONTENT" > "$LUA_HDR"
    say "  [write] $LUA_HDR"
    CHANGED=1; NEED_RELOGIN=1
fi
if [ -f "$LUA_NOHDR" ]; then
    mv -f "$LUA_NOHDR" "$LUA_NOHDR_BAK"
    say "  [remove] old nohdr lua -> $LUA_NOHDR_BAK"
    CHANGED=1; NEED_RELOGIN=1
fi

# e2. volume-key fix (EC drops key releases -> evdev forwarder as a boot-time system service)
if ! have_evdev; then
    say "  [skip] python3 evdev module missing, skipping volume-key fix"
else
mkdir -p "$(dirname "$VOLKEY_PY")"
if same_content "$VOLKEY_PY" "$VOLKEY_PY_CONTENT"; then
    say "  [skip] $VOLKEY_PY unchanged"
else
    printf '%s\n' "$VOLKEY_PY_CONTENT" > "$VOLKEY_PY"; chmod +x "$VOLKEY_PY"
    say "  [write] $VOLKEY_PY"; CHANGED=1; VOLKEY_RESTART=1
fi
if same_content "$VOLKEY_UNIT" "$VOLKEY_UNIT_CONTENT"; then
    say "  [skip] $VOLKEY_UNIT unchanged"
else
    printf '%s\n' "$VOLKEY_UNIT_CONTENT" | sudo tee "$VOLKEY_UNIT" >/dev/null
    sudo systemctl daemon-reload
    say "  [write] $VOLKEY_UNIT"; CHANGED=1; VOLKEY_RESTART=1
fi
if ! systemctl is-enabled -q oxp3-volkey-fix.service 2>/dev/null; then
    sudo systemctl enable oxp3-volkey-fix.service >/dev/null 2>&1
    say "  [enable] oxp3-volkey-fix.service (starts at boot before gamescope)"; CHANGED=1
fi
if ! systemctl is-active -q oxp3-volkey-fix.service 2>/dev/null; then
    # must start before the graphical session -> only flag a reboot
    say "  volkey service not running: takes effect after reboot"
    NEED_REBOOT=1
elif [ "$VOLKEY_RESTART" = 1 ]; then
    say "  volkey files updated: reboot to apply"
    NEED_REBOOT=1
fi
fi

# e2b. gyroscope (EXPERIMENTAL, opt-in; runs before e3 because the InputPlumber yaml and restart below depend on it)
mkdir -p "$GYRO_DIR"
if [ "$GYRO_REQ" = 0 ]; then
    if gyro_installed; then say "  [gyro] removing the experimental gyro support (--no-gyro)"; remove_gyro; else say "  [skip] gyro: nothing installed"; fi
    rm -f "$GYRO_ON_FILE"; : > "$GYRO_OFF_FILE"
elif [ "$GYRO_WANT" = 1 ] && [ -n "$GYRO_BLOCK" ]; then
    say "  [skip] gyro (experimental): $GYRO_BLOCK"
elif [ "$GYRO_ON" = 1 ]; then
    GYRO_OK=1
    # patched InputPlumber: keep the verified copy, else take it from the release archive next to the script, else download
    # the archive and extract it; the sha256 is checked every time
    if gyro_bin_ok; then
        say "  [skip] $GYRO_BIN unchanged"
    elif [ "$SCRIPT_DIR/inputplumber-oxp3-gyro" != "$GYRO_BIN" ] && [ -f "$SCRIPT_DIR/inputplumber-oxp3-gyro" ]         && [ "$(sha256sum "$SCRIPT_DIR/inputplumber-oxp3-gyro" | cut -d' ' -f1)" = "$GYRO_BIN_SHA256" ]; then
        install -m 755 "$SCRIPT_DIR/inputplumber-oxp3-gyro" "$GYRO_BIN"; say "  [write] $GYRO_BIN (from the release archive, sha256 verified)"; CHANGED=1; IP_RESTART=1
    elif ! command -v curl >/dev/null 2>&1 || ! ip route 2>/dev/null | grep -q '^default'; then
        say "  [error] gyro: the patched InputPlumber is not on this machine and there is no network to download it"; GYRO_OK=0
    else
        say "  [run] downloading the release archive ($GYRO_PKG_URL, about 4 MB) ..."
        _tmp="$(mktemp -d "${TMPDIR:-/tmp}/oxp3-pkg.XXXXXX")"
        if curl -fL --retry 3 --progress-bar -o "$_tmp/pkg.tar.gz" "$GYRO_PKG_URL"             && tar -xzf "$_tmp/pkg.tar.gz" -C "$_tmp" oxp3-fix/inputplumber-oxp3-gyro             && [ "$(sha256sum "$_tmp/oxp3-fix/inputplumber-oxp3-gyro" | cut -d' ' -f1)" = "$GYRO_BIN_SHA256" ]; then
            install -m 755 "$_tmp/oxp3-fix/inputplumber-oxp3-gyro" "$GYRO_BIN"; say "  [write] $GYRO_BIN (sha256 verified)"; CHANGED=1; IP_RESTART=1
        else
            say "  [error] gyro: download failed or the sha256 does not match"; GYRO_OK=0
        fi
        rm -rf "$_tmp"
    fi
    if [ "$GYRO_OK" = 1 ] && ldd "$GYRO_BIN" 2>&1 | grep -q 'not found'; then
        say "  [error] gyro: the patched InputPlumber needs libraries this SteamOS build does not have:"; ldd "$GYRO_BIN" 2>&1 | grep 'not found'; GYRO_OK=0
    fi
    # ACPI override image (never replace an acpi_override.img that is not ours)
    if [ "$GYRO_OK" = 1 ]; then
        _cur="$(acpi_img_sha)"
        if [ "$_cur" = "$ACPI_IMG_SHA256" ]; then
            say "  [skip] $ACPI_IMG unchanged"
        elif [ -n "$_cur" ] && [ "$_cur" != "$ACPI_IMG_OLD_SHA256" ]; then
            say "  [error] gyro: $ACPI_IMG already exists and is not from this pack (sha256 ${_cur:0:12}...), not overwriting it"; GYRO_OK=0
        else
            _tmp="$(mktemp "${TMPDIR:-/tmp}/oxp3-acpi.XXXXXX")"
            printf '%s' "$ACPI_IMG_B64" | base64 -d | gunzip > "$_tmp" 2>/dev/null || true
            if [ "$(sha256sum "$_tmp" | cut -d' ' -f1)" = "$ACPI_IMG_SHA256" ] && sudo install -m 644 "$_tmp" "$ACPI_IMG"; then
                say "  [write] $ACPI_IMG (ACPI override for the BMI260)"; CHANGED=1; GRUB_UPD=1
            else
                say "  [error] gyro: could not write the ACPI override image"; GYRO_OK=0
            fi
            rm -f "$_tmp"
        fi
    fi
    if [ "$GYRO_OK" = 1 ]; then
        GRUB_UPD="${GRUB_UPD:-0}"
        if sudo_put "$GRUB_IMU_FILE" "$GRUB_IMU_CONTENT"; then CHANGED=1; GRUB_UPD=1; fi
        if ! sudo grep -q 'acpi_override.img' "$EFI_GRUB_CFG" 2>/dev/null; then GRUB_UPD=1; fi
        if [ "$GRUB_UPD" = 1 ]; then
            say "  [run] update-grub -> $EFI_GRUB_CFG"; sudo update-grub
            if sudo grep -q 'acpi_override.img' "$EFI_GRUB_CFG" 2>/dev/null; then say "  [verify] grub.cfg loads acpi_override.img OK"; else say "  [error] gyro: grub.cfg does not reference acpi_override.img"; GYRO_OK=0; fi
        fi
        [ "$IMU_ACTIVE" = 1 ] || NEED_REBOOT=1
    fi
    if [ "$GYRO_OK" = 1 ]; then
        printf '%s\n' "$GYRO_LAUNCH_CONTENT" > "$GYRO_LAUNCH.new"; chmod +x "$GYRO_LAUNCH.new"
        if [ -f "$GYRO_LAUNCH" ] && cmp -s "$GYRO_LAUNCH.new" "$GYRO_LAUNCH"; then rm -f "$GYRO_LAUNCH.new"; say "  [skip] $GYRO_LAUNCH unchanged"
        else mv -f "$GYRO_LAUNCH.new" "$GYRO_LAUNCH"; say "  [write] $GYRO_LAUNCH"; CHANGED=1; IP_RESTART=1; fi
        if sudo_put "$GYRO_DROPIN" "$GYRO_DROPIN_CONTENT"; then sudo systemctl daemon-reload; CHANGED=1; IP_RESTART=1; fi
        if [ ! -f "$GYRO_CONF" ]; then sudo_put "$GYRO_CONF" "$GYRO_CONF_CONTENT" || true; CHANGED=1; else say "  [skip] $GYRO_CONF exists (your tuning is kept)"; fi
        rm -f "$GYRO_OFF_FILE"; : > "$GYRO_ON_FILE"
        say "  gyro (experimental) enabled$([ "$IMU_ACTIVE" = 1 ] || echo "; the IMU appears after the reboot")"
    else
        say "  gyro (experimental) NOT enabled: see the errors above; InputPlumber stays configured for the stock build."
        set_base_yaml
    fi
else
    if [ "$GYRO_DECLINED" = 1 ]; then : > "$GYRO_OFF_FILE"; fi
fi

# e3. InputPlumber: Home/Console/Keyboard keys + back paddles (L4/R4) + single virtual gamepad
if ! have_ip; then
    say "  [skip] inputplumber not installed, skipping gamepad integration"
else
if same_content "$IP_YAML" "$IP_YAML_CONTENT"; then
    say "  [skip] $IP_YAML unchanged"
else
    sudo mkdir -p "$(dirname "$IP_YAML")"
    printf '%s\n' "$IP_YAML_CONTENT" | sudo tee "$IP_YAML" >/dev/null
    say "  [write] $IP_YAML"; CHANGED=1; IP_RESTART=1
fi
if same_content "$IP_CAPMAP" "$IP_CAPMAP_CONTENT"; then
    say "  [skip] $IP_CAPMAP unchanged"
else
    sudo mkdir -p "$(dirname "$IP_CAPMAP")"
    printf '%s\n' "$IP_CAPMAP_CONTENT" | sudo tee "$IP_CAPMAP" >/dev/null
    say "  [write] $IP_CAPMAP (Home key -> Steam menu)"; CHANGED=1; IP_RESTART=1
fi
if ! systemctl is-enabled -q inputplumber.service 2>/dev/null; then
    sudo systemctl enable inputplumber.service >/dev/null 2>&1
    say "  [enable] inputplumber.service"; CHANGED=1; IP_RESTART=1
fi
if [ "${IP_RESTART:-0}" = 1 ] || ! systemctl is-active -q inputplumber.service 2>/dev/null; then
    sudo systemctl restart inputplumber.service && say "  [restart] inputplumber.service (the gamepad re-enumerates briefly)"
fi
fi

# e4. back paddles: re-assert the hid-oxp driver state (sysfs only -> driver rewrites its pages 1-2, never page 3)
if [ -z "$OXP_DEV" ]; then
    say "  [skip] hid-oxp not bound to 1A86:FE00 iface 2, paddles unavailable (needs a kernel with hid-oxp)"
elif paddles_ok; then
    say "  [skip] paddle driver state already correct (xinput / $OXP_M1 / $OXP_M2)"
else
    if [ "$OXP_MODE" != xinput ]; then
        printf 'xinput' | sudo tee "$OXP_DEV/gamepad_mode" >/dev/null && say "  [write] $(basename "$OXP_DEV")/gamepad_mode = xinput (was $OXP_MODE)"; CHANGED=1
    fi
    if ! paddle_key_ok "$OXP_M1" || ! paddle_key_ok "$OXP_M2" || [ "$OXP_M1" = "$OXP_M2" ]; then
        printf '%s' "$PADDLE_M1" | sudo tee "$OXP_DEV/button_m1" >/dev/null && say "  [write] $(basename "$OXP_DEV")/button_m1 = $PADDLE_M1 (was $OXP_M1)"; CHANGED=1
        printf '%s' "$PADDLE_M2" | sudo tee "$OXP_DEV/button_m2" >/dev/null && say "  [write] $(basename "$OXP_DEV")/button_m2 = $PADDLE_M2 (was $OXP_M2)"; CHANGED=1
    fi
    say "  paddles re-asserted via the driver."
fi

# e5. battery percentage clamp (root service, sysfs overlay; takes effect immediately, no reboot)
if [ ! -r /sys/class/power_supply/BAT0/energy_now ]; then
    say "  [skip] no BAT0 with energy_* attributes, skipping battery clamp"
else
mkdir -p "$(dirname "$BATT_SH")"
if same_content "$BATT_SH" "$BATT_SH_CONTENT"; then
    say "  [skip] $BATT_SH unchanged"
else
    printf '%s\n' "$BATT_SH_CONTENT" > "$BATT_SH"; chmod +x "$BATT_SH"
    say "  [write] $BATT_SH"; CHANGED=1; BATT_RESTART=1
fi
if same_content "$BATT_UNIT" "$BATT_UNIT_CONTENT"; then
    say "  [skip] $BATT_UNIT unchanged"
else
    printf '%s\n' "$BATT_UNIT_CONTENT" | sudo tee "$BATT_UNIT" >/dev/null
    sudo systemctl daemon-reload
    say "  [write] $BATT_UNIT"; CHANGED=1; BATT_RESTART=1
fi
if ! systemctl is-enabled -q oxp3-battery-clamp.service 2>/dev/null; then
    sudo systemctl enable oxp3-battery-clamp.service >/dev/null 2>&1
    say "  [enable] oxp3-battery-clamp.service"; CHANGED=1; BATT_RESTART=1
fi
if [ "$BATT_RESTART" = 1 ] || ! systemctl is-active -q oxp3-battery-clamp.service 2>/dev/null; then
    sudo systemctl restart oxp3-battery-clamp.service && say "  [restart] oxp3-battery-clamp.service (capacity now $(sleep 1; cat /sys/class/power_supply/BAT0/capacity | tr -d ' ')%)"
fi
fi

# e6. TDP sync (root service; the MSR package PL1, which the GPU obeys, follows the MMIO PL1 that TDP tools write)
if ! have_rapl; then
    say "  [skip] no MSR/MMIO package RAPL, skipping TDP sync"
else
mkdir -p "$(dirname "$TDP_SH")"
if same_content "$TDP_SH" "$TDP_SH_CONTENT"; then
    say "  [skip] $TDP_SH unchanged"
else
    printf '%s
' "$TDP_SH_CONTENT" > "$TDP_SH"; chmod +x "$TDP_SH"
    say "  [write] $TDP_SH"; CHANGED=1; TDP_RESTART=1
fi
if same_content "$TDP_UNIT" "$TDP_UNIT_CONTENT"; then
    say "  [skip] $TDP_UNIT unchanged"
else
    printf '%s
' "$TDP_UNIT_CONTENT" | sudo tee "$TDP_UNIT" >/dev/null
    sudo systemctl daemon-reload
    say "  [write] $TDP_UNIT"; CHANGED=1; TDP_RESTART=1
fi
if ! systemctl is-enabled -q oxp3-tdp-sync.service 2>/dev/null; then
    sudo systemctl enable oxp3-tdp-sync.service >/dev/null 2>&1
    say "  [enable] oxp3-tdp-sync.service"; CHANGED=1; TDP_RESTART=1
fi
if [ "$TDP_RESTART" = 1 ] || ! systemctl is-active -q oxp3-tdp-sync.service 2>/dev/null; then
    sudo systemctl restart oxp3-tdp-sync.service && sleep 1 && say "  [restart] oxp3-tdp-sync.service ($(bash "$TDP_SH" --once | tr '
' ';' | sed 's/;$//'))"
fi
fi

# e7. CPU power for the overlay (root service; coarse world-readable copy of the package energy counter, no reboot)
if ! have_rapl_pkg; then
    say "  [skip] no intel-rapl:0 package zone, skipping the CPU power overlay"
else
mkdir -p "$(dirname "$RAPL_PY")"
if same_content "$RAPL_PY" "$RAPL_PY_CONTENT"; then
    say "  [skip] $RAPL_PY unchanged"
else
    printf '%s\n' "$RAPL_PY_CONTENT" > "$RAPL_PY"; chmod +x "$RAPL_PY"
    say "  [write] $RAPL_PY"; CHANGED=1; RAPL_RESTART=1
fi
if same_content "$RAPL_UNIT" "$RAPL_UNIT_CONTENT"; then
    say "  [skip] $RAPL_UNIT unchanged"
else
    printf '%s\n' "$RAPL_UNIT_CONTENT" | sudo tee "$RAPL_UNIT" >/dev/null
    sudo systemctl daemon-reload
    say "  [write] $RAPL_UNIT"; CHANGED=1; RAPL_RESTART=1
fi
if ! systemctl is-enabled -q oxp3-rapl-overlay.service 2>/dev/null; then
    sudo systemctl enable oxp3-rapl-overlay.service >/dev/null 2>&1
    say "  [enable] oxp3-rapl-overlay.service"; CHANGED=1; RAPL_RESTART=1
fi
if [ "$RAPL_RESTART" = 1 ] || ! systemctl is-active -q oxp3-rapl-overlay.service 2>/dev/null; then
    sudo systemctl restart oxp3-rapl-overlay.service && say "  [restart] oxp3-rapl-overlay.service (the overlay picks it up when it restarts, e.g. after re-entering game mode)"
fi
fi

# e8. GPU power/temperature in the overlay: patched mangoapp started through a user drop-in (integrated xe GPU only)
if ! igpu_without_hwmon; then
    say "  [skip] the GPU has its own hwmon sensors, the stock overlay shows them"
else
MANGO_OK=1; MANGO_RESTART=0
if mango_bin_ok; then
    say "  [skip] $MANGO_BIN unchanged"
elif [ -f "$SCRIPT_DIR/mangoapp-oxp3" ] && [ "$(sha256sum "$SCRIPT_DIR/mangoapp-oxp3" | cut -d' ' -f1)" = "$MANGO_SHA256" ]; then
    install -m 755 "$SCRIPT_DIR/mangoapp-oxp3" "$MANGO_BIN"; say "  [write] $MANGO_BIN (from the release archive, sha256 verified)"; CHANGED=1; MANGO_RESTART=1
elif ! command -v curl >/dev/null 2>&1 || ! ip route 2>/dev/null | grep -q '^default'; then
    say "  [error] the patched mangoapp is not on this machine and there is no network to download it"; MANGO_OK=0
else
    say "  [run] downloading the release archive ($PKG_URL) ..."
    _tmp="$(mktemp -d "${TMPDIR:-/tmp}/oxp3-pkg.XXXXXX")"
    if curl -fL --retry 3 --progress-bar -o "$_tmp/pkg.tar.gz" "$PKG_URL" \
        && tar -xzf "$_tmp/pkg.tar.gz" -C "$_tmp" oxp3-fix/mangoapp-oxp3 \
        && [ "$(sha256sum "$_tmp/oxp3-fix/mangoapp-oxp3" | cut -d' ' -f1)" = "$MANGO_SHA256" ]; then
        install -m 755 "$_tmp/oxp3-fix/mangoapp-oxp3" "$MANGO_BIN"; say "  [write] $MANGO_BIN (sha256 verified)"; CHANGED=1; MANGO_RESTART=1
    else
        say "  [error] download failed or the sha256 does not match"; MANGO_OK=0
    fi
    rm -rf "$_tmp"
fi
if [ "$MANGO_OK" = 1 ]; then
    if same_content "$MANGO_LAUNCH" "$MANGO_LAUNCH_CONTENT"; then
        say "  [skip] $MANGO_LAUNCH unchanged"
    else
        printf '%s\n' "$MANGO_LAUNCH_CONTENT" > "$MANGO_LAUNCH"; chmod +x "$MANGO_LAUNCH"
        say "  [write] $MANGO_LAUNCH"; CHANGED=1; MANGO_RESTART=1
    fi
    if sudo_put "$MANGO_DROPIN" "$MANGO_DROPIN_CONTENT"; then CHANGED=1; MANGO_RESTART=1; fi
    if [ "$MANGO_RESTART" = 1 ]; then
        user_systemctl daemon-reload
        if systemctl --user is-active -q gamescope-mangoapp.service 2>/dev/null; then
            user_systemctl restart gamescope-mangoapp.service; say "  [restart] the performance overlay (mangoapp)"
        else
            say "  the overlay uses the patched build from the next game-mode session"
        fi
    fi
    mango_matches || say "  [info] SteamOS ships another mangohud than the patched build ($MANGO_FOR): the launcher starts the stock mangoapp until a matching build is released"
fi
fi

# e9. display firmware: keep DMC v2.20 (newer DMC caps VRR at 70-80 fps). xe is not in the initramfs, so firmware/updates
#     is read at boot; a SteamOS update resets /usr, re-run the script afterwards.
if ! dmc_applies; then
    say "  [skip] this GPU does not use $DMC_NAME"
elif [ "$(dmc_system_sha)" = "$DMC_SHA256" ]; then
    if [ -f "$DMC_OVERRIDE" ]; then sudo rm -f "$DMC_OVERRIDE"; say "  [remove] $DMC_OVERRIDE (SteamOS ships v2.20 itself)"; CHANGED=1; fi
    say "  [skip] SteamOS ships DMC v2.20, no override needed"
elif dmc_override_ok; then
    say "  [skip] $DMC_OVERRIDE unchanged"
else
    _tmp="$(mktemp "${TMPDIR:-/tmp}/oxp3-dmc.XXXXXX")"
    printf '%s' "$DMC_B64" | base64 -d > "$_tmp"
    if [ "$(sha256sum "$_tmp" | cut -d' ' -f1)" = "$DMC_SHA256" ] && sudo install -D -m 644 "$_tmp" "$DMC_OVERRIDE"; then
        say "  [write] $DMC_OVERRIDE (DMC v2.20)"; CHANGED=1
    else
        say "  [error] could not write the DMC v2.20 override"
    fi
    rm -f "$_tmp"
fi
if dmc_applies && [ -n "$DMC_RUNNING" ] && [ "$DMC_RUNNING" != v2.20 ] && { dmc_override_ok || [ "$(dmc_system_sha)" = "$DMC_SHA256" ]; }; then
    say "  DMC $DMC_RUNNING is loaded right now: v2.20 takes over after the reboot"; NEED_REBOOT=1
fi

# e10. speaker route check: user unit at session start, re-run by a root unit after every resume; it only switches the
#      card profile when the headphone jack is empty but the Headphones profile is active
mkdir -p "$(dirname "$AUDIO_SH")" "$(dirname "$AUDIO_UNIT")"
AUDIO_CHANGED=0
if same_content "$AUDIO_SH" "$AUDIO_SH_CONTENT"; then
    say "  [skip] $AUDIO_SH unchanged"
else
    printf '%s\n' "$AUDIO_SH_CONTENT" > "$AUDIO_SH"; chmod +x "$AUDIO_SH"
    say "  [write] $AUDIO_SH"; CHANGED=1; AUDIO_CHANGED=1
fi
if same_content "$AUDIO_UNIT" "$AUDIO_UNIT_CONTENT"; then
    say "  [skip] $AUDIO_UNIT unchanged"
else
    printf '%s\n' "$AUDIO_UNIT_CONTENT" > "$AUDIO_UNIT"
    say "  [write] $AUDIO_UNIT"; CHANGED=1; AUDIO_CHANGED=1
fi
[ "$AUDIO_CHANGED" = 1 ] && user_systemctl daemon-reload
if ! systemctl --user is-enabled -q oxp3-audio-route.service 2>/dev/null; then
    user_systemctl enable oxp3-audio-route.service; say "  [enable] oxp3-audio-route.service (user)"; CHANGED=1
fi
if sudo_put "$AUDIO_RESUME_UNIT" "$AUDIO_RESUME_UNIT_CONTENT"; then sudo systemctl daemon-reload; CHANGED=1; fi
if ! systemctl is-enabled -q oxp3-audio-resume.service 2>/dev/null; then
    sudo systemctl enable oxp3-audio-resume.service; say "  [enable] oxp3-audio-resume.service"; CHANGED=1
fi
# check right away too, the current session may have started with the wrong profile
[ "$AUDIO_CHANGED" = 1 ] && user_systemctl start --no-block oxp3-audio-route.service

if ! panel_fix_needed; then
    say "  [skip] the panel fix needs the AMS881KB01 panel on BIOS $PANEL_BIOS_MIN or later (BIOS ${BIOS_VER:-?}), keeping the driver's PSR and LOBF (force with --force-panel)"
else
mkdir -p "$(dirname "$PANEL_SH")"
if same_content "$PANEL_SH" "$PANEL_SH_CONTENT"; then
    say "  [skip] $PANEL_SH unchanged"
else
    printf '%s\n' "$PANEL_SH_CONTENT" > "$PANEL_SH"; chmod +x "$PANEL_SH"
    say "  [write] $PANEL_SH"; CHANGED=1; PANEL_RESTART=1
fi
if same_content "$PANEL_UNIT" "$PANEL_UNIT_CONTENT"; then
    say "  [skip] $PANEL_UNIT unchanged"
else
    printf '%s\n' "$PANEL_UNIT_CONTENT" | sudo tee "$PANEL_UNIT" >/dev/null
    sudo systemctl daemon-reload
    say "  [write] $PANEL_UNIT"; CHANGED=1; PANEL_RESTART=1
fi
if ! systemctl is-enabled -q oxp3-panel-fix.service 2>/dev/null; then
    sudo systemctl enable oxp3-panel-fix.service >/dev/null 2>&1
    say "  [enable] oxp3-panel-fix.service (runs at boot before gamescope)"; CHANGED=1
fi
if [ "$PANEL_RESTART" = 1 ] || ! systemctl is-active -q oxp3-panel-fix.service 2>/dev/null; then
    say "  panel fix takes effect after the reboot"
    NEED_REBOOT=1
fi
fi

# e12. SimpleDeckyTDP-Intel (optional Decky plugin, step 14)
mkdir -p "$GYRO_DIR"
if [ "$SDTDP_REQ" = 0 ]; then
    if sdtdp_installed; then remove_sdtdp; else say "  [skip] SimpleDeckyTDP-Intel: not installed"; fi
    rm -f "$SDTDP_ON_FILE"; : > "$SDTDP_OFF_FILE"
elif [ "$SDTDP_WANT" = 1 ] && ! have_decky; then
    say "  [skip] SimpleDeckyTDP-Intel: Decky Loader is not installed, see $SDTDP_README"
elif [ "$SDTDP_WANT" = 1 ]; then
    SDTDP_RESTART=0
    if [ -d "$SDTDP_UPSTREAM" ] && [ "$SDTDP_REPLACE" != 1 ]; then
        if sdtdp_installed; then
            say "  [warn] SimpleDeckyTDP-Intel and the original SimpleDeckyTDP are both installed and override each other; remove one in Decky, or re-run this script and answer y"
        else
            say "  [skip] SimpleDeckyTDP-Intel: the original SimpleDeckyTDP stays (not replaced)"
        fi
    elif sdtdp_installed; then
        say "  [skip] SimpleDeckyTDP-Intel $(sdtdp_version) installed (it updates itself from its System Info page)"
    elif install_sdtdp; then
        SDTDP_RESTART=1
    fi
    if sdtdp_installed; then
        if [ -d "$SDTDP_UPSTREAM" ] && [ "$SDTDP_REPLACE" = 1 ]; then
            sudo rm -rf "$SDTDP_UPSTREAM"; CHANGED=1; SDTDP_RESTART=1
            say "  [remove] $SDTDP_UPSTREAM (replaced; its settings file stays, and SimpleDeckyTDP-Intel copies it on its first start if it has no settings of its own)"
        fi
        rm -f "$SDTDP_OFF_FILE"; : > "$SDTDP_ON_FILE"
    fi
    if [ "$SDTDP_RESTART" = 1 ]; then sudo systemctl restart plugin_loader.service; say "  [restart] plugin_loader (Decky)"; fi
elif [ "$SDTDP_DECLINED" = 1 ]; then
    : > "$SDTDP_OFF_FILE"
fi

if ! xe_gpu; then
    say "  [skip] xevmafix: not an xe GPU"
elif ! xevma_kernel_ok; then
    say "  [skip] xevmafix is built for kernel $XEVMA_FOR and this is $KVER (big games can crash after sleep until a rebuilt module ships)"
else
    XEVMA_OK=1
    if xevma_ko_ok; then
        say "  [skip] $XEVMA_KO unchanged"
    elif [ "$SCRIPT_DIR/xevmafix.ko" != "$XEVMA_KO" ] && [ -f "$SCRIPT_DIR/xevmafix.ko" ] && [ "$(sha256sum "$SCRIPT_DIR/xevmafix.ko" | cut -d' ' -f1)" = "$XEVMA_SHA256" ]; then
        mkdir -p "$(dirname "$XEVMA_KO")"; install -m 644 "$SCRIPT_DIR/xevmafix.ko" "$XEVMA_KO"
        say "  [write] $XEVMA_KO (from the release archive, sha256 verified)"; CHANGED=1
    else
        say "  [skip] xevmafix.ko is not next to this script or its sha256 differs (it comes with the release archive)"; XEVMA_OK=0
    fi
    if [ "$XEVMA_OK" = 1 ]; then
        if same_content "$XEVMA_UNIT" "$XEVMA_UNIT_CONTENT"; then
            say "  [skip] $XEVMA_UNIT unchanged"
        else
            printf '%s\n' "$XEVMA_UNIT_CONTENT" | sudo tee "$XEVMA_UNIT" >/dev/null
            sudo systemctl daemon-reload
            say "  [write] $XEVMA_UNIT"; CHANGED=1
        fi
        if ! systemctl is-enabled -q oxp3-xevmafix.service 2>/dev/null; then
            sudo systemctl enable oxp3-xevmafix.service >/dev/null 2>&1
            say "  [enable] oxp3-xevmafix.service (loads the module at boot)"; CHANGED=1
        fi
        if ! xevma_loaded; then
            if sudo systemctl restart oxp3-xevmafix.service && xevma_loaded; then
                say "  [load] xevmafix (active now, no reboot needed)"; CHANGED=1
            else
                say "  [warn] xevmafix did not load, see: journalctl -k -b 0 | grep xevmafix"
            fi
        fi
    fi
fi

# f. summary
hdr "Summary"
if [ "$WIFI_FAILED" = 1 ]; then say "  Wi-Fi/Bluetooth firmware step did not complete, see the messages above."; fi
if [ $CHANGED = 1 ]; then say "  changes were made."; else say "  nothing to change, all fixes in place."; fi
if [ $NEED_REBOOT = 1 ]; then
    say "  REBOOT REQUIRED (kernel parameter or xe module parameter not active yet)"
    if [ -t 0 ]; then
        read -r -p "  Reboot now? (y/N) " ans
        case "$ans" in y|Y) sudo systemctl reboot ;; *) say "  please reboot later." ;; esac
    fi
elif [ $NEED_RELOGIN = 1 ]; then
    say "  re-enter game mode to load the lua (switch to desktop and back, or reboot)"
else
    say "  no reboot needed."
fi
