#!/bin/bash
# oxp3-steamos-fixes - ONEXPLAYER 3 (Intel Panther Lake) SteamOS fix pack
# Version: v1.5.1 (2026-09-25)     License: MIT (see LICENSE)     Author: HANA & Claude
# Tested on: SteamOS 3.10 main build 20260827.1000, kernel 7.2.0-valve1-1-neptune-72, OXP3 BIOS 5.09,
#            panel Samsung SDC AMS881KB01-0, SSD Predator GM7 1TB (Biwin/Maxio 1dee:1602)
# v1.1.0: gamescope HDR lua now also registers real 30-144Hz dynamic_modegen (this panel has genuine
#         continuous VRR; the v1.0.1 lua declared dynamic_refresh_rates but never shipped the
#         matching dynamic_modegen function, so no extra Hz options ever actually appeared in the
#         Steam Performance panel's per-game refresh-rate selector).
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
OXP3_FIXES_VERSION="v1.5.1 (2026-09-25)"
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
# Usage:
#   ./oxp3-apply-fixes.sh                apply (asks sudo password, prints the plan and confirms)
#   ./oxp3-apply-fixes.sh --check        check only, changes nothing, needs no sudo (covers every fix, gyro included when enabled)
#   ./oxp3-apply-fixes.sh --revert       undo every fix incl. gyro (then reboot)
#   ./oxp3-apply-fixes.sh --mcu-restore  [DANGEROUS] raw-writes MCU button-table page 3 (Home/Xbox) to factory values, asks to confirm.
#                                        Use ONLY if Home/Xbox are already dead. A wrong write can kill chassis keys for good and
#                                        cannot be read back or verified. Normal users must NOT run this. No other option writes the MCU.
#   flags: --yes no confirmation prompt | --force skip the device/OS guards | --force-nvme apply nvme.noacpi=1 on any SSD
#          --no-wifi skip step 0 (Wi-Fi firmware)
#          --gyro enable the experimental gyro step (remembered; later runs and OS-update re-runs keep it)
#          --no-gyro switch the gyro step off and remove its files (remembered)
# Idempotent: safe to run repeatedly.
# ============================================================================
set -euo pipefail

MODE="apply"; FORCE=0; FORCE_NVME=0; ASSUME_YES=0; SKIP_WIFI=0; GYRO_REQ=""
for a in "$@"; do
    case "$a" in
        --check) MODE="--check" ;;
        --revert) MODE="--revert" ;;
        --mcu-restore) MODE="--mcu-restore" ;;  # DANGEROUS: restore MCU button page 3 (Home/Xbox)
        --force) FORCE=1 ;;            # skip DMI + OS guards
        --force-nvme) FORCE_NVME=1 ;;  # apply nvme.noacpi=1 regardless of SSD model
        --yes|-y) ASSUME_YES=1 ;;      # no confirmation prompt
        --no-wifi) SKIP_WIFI=1 ;;      # skip step 0 (Wi-Fi firmware)
        --gyro) GYRO_REQ=1 ;;          # enable the experimental gyro step (remembered)
        --no-gyro) GYRO_REQ=0 ;;       # disable it and remove its files (remembered)
        -h|--help) sed -n '2,/^set -euo pipefail/p' "$0" | grep -E '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a  (valid: --check | --revert | --mcu-restore | --force | --force-nvme | --no-wifi | --gyro | --no-gyro | --yes)"; exit 2 ;;
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
GYRO_PKG_URL="https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/download/v1.5.1/oxp3-fix.tar.gz"   # release archive holding the binary
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"                  # the extracted release archive, if the script came from it
ACPI_IMG_SHA256="0e9b716e65978ac7365fda6fddf476a18b352a2d1ed98f4f30c8d3f8558b2113"
ACPI_IMG_OLD_SHA256="2d1a0a88e4cfe694cd4edc9b0d0a5e28f7f3f5bb9ccdcf7cbf1d5d01a02d42ad"   # earlier build of the same table (long cpio member name)

# ---- desired contents ------------------------------------------
GRUB_D_CONTENT=$(cat <<'EOT'
# nvme.noacpi=1: Predator GM7 fails to resume from s2idle via ACPI simple-suspend. Revert: rm this file, run update-grub
GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX} nvme.noacpi=1"
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
        for a in capacity energy_full; do mountpoint -q "$REALDIR/$a" && umount "$REALDIR/$a"; done
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
CHANGED=0; NEED_REBOOT=0; NEED_RELOGIN=0; VOLKEY_RESTART=0; IP_RESTART=0; BATT_RESTART=0

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
have_ip() { command -v inputplumber >/dev/null 2>&1 && [ -f /usr/lib/systemd/system/inputplumber.service ]; }
# the hid-oxp-bound MCU config interface (iface 2, has the gamepad_mode attribute)
oxp_hid_dev() { local d; for d in /sys/bus/hid/drivers/hid-oxp/0003:1A86:FE00.*; do [ -f "$d/gamepad_mode" ] && { echo "$d"; return 0; }; done; return 1; }
OXP_DEV="$(oxp_hid_dev || true)"
OXP_MODE="$(cat "$OXP_DEV/gamepad_mode" 2>/dev/null || echo '-')"
OXP_M1="$(cat "$OXP_DEV/button_m1" 2>/dev/null || echo '-')"
OXP_M2="$(cat "$OXP_DEV/button_m2" 2>/dev/null || echo '-')"
paddles_ok() { [ -n "$OXP_DEV" ] && [ "$OXP_MODE" = xinput ] && [ "$OXP_M1" = KEY_F16 ] && [ "$OXP_M2" = KEY_F17 ]; }
NVME_MODEL="$(cat /sys/class/nvme/nvme0/model 2>/dev/null | xargs || echo unknown)"

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

# ---- a. current state ------------------------------------------
hdr "Current state  (oxp3-steamos-fixes $OXP3_FIXES_VERSION)"
say "  device: $DMI_VENDOR $DMI_PRODUCT ; SteamOS $OS_BUILD ; kernel $KVER ; NVMe: $NVME_MODEL"
if grep -qw 'nvme.noacpi=1' /proc/cmdline; then
    say "  kernel param nvme.noacpi=1 : active (in /proc/cmdline)"; CMD_OK=1
else
    say "  kernel param nvme.noacpi=1 : NOT active (not in /proc/cmdline)"; CMD_OK=0
fi
if [ -f "$GRUB_D_FILE" ]; then say "  $GRUB_D_FILE : present"; else say "  $GRUB_D_FILE : missing"; fi
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
if [ "$GYRO_ON" = 1 ]; then
    say "  gyro (experimental) : enabled ; IMU $([ "$IMU_ACTIVE" = 1 ] && echo "visible to the kernel (ACPI override active)" || echo "NOT visible yet (ACPI override not loaded: reboot needed)") ; patched InputPlumber $(gyro_bin_ok && echo present || echo missing)"
elif [ "$GYRO_WANT" = 1 ]; then
    say "  gyro (experimental) : wanted but unavailable - $GYRO_BLOCK"
else
    say "  gyro (experimental) : not enabled (opt in with --gyro)"
fi
if [ -n "$OXP_DEV" ]; then
    say "  hid-oxp MCU driver (paddles) : $(basename "$OXP_DEV") gamepad_mode=$OXP_MODE button_m1=$OXP_M1 button_m2=$OXP_M2   expected xinput / KEY_F16 / KEY_F17"
else
    say "  hid-oxp MCU driver (paddles) : not bound (hid-oxp not bound to 1A86:FE00 iface 2 - kernel lacks hid-oxp or it was unbound)"
fi
RO_STATUS="$(steamos-readonly status 2>/dev/null | head -n1 || true)"   # note: exits non-zero when disabled
[ -n "$RO_STATUS" ] || RO_STATUS=unknown
say "  steamos-readonly : $RO_STATUS"
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
    same_content "$MODPROBE_FILE" "$MODPROBE_CONTENT" || { say "  [diff] modprobe file missing or differs"; ok=0; }
    same_content "$LUA_HDR" "$LUA_HDR_CONTENT" || { say "  [diff] HDR lua missing or differs"; ok=0; }
    if [ -f "$LUA_NOHDR" ]; then say "  [diff] old nohdr lua still present"; ok=0; fi
    same_content "$VOLKEY_PY" "$VOLKEY_PY_CONTENT" || { say "  [diff] volkey .py missing or differs"; ok=0; }
    same_content "$VOLKEY_UNIT" "$VOLKEY_UNIT_CONTENT" || { say "  [diff] volkey unit missing or differs"; ok=0; }
    systemctl is-enabled -q oxp3-volkey-fix.service 2>/dev/null || { say "  [diff] oxp3-volkey-fix.service not enabled"; ok=0; }
    same_content "$BATT_SH" "$BATT_SH_CONTENT" || { say "  [diff] battery clamp script missing or differs"; ok=0; }
    same_content "$BATT_UNIT" "$BATT_UNIT_CONTENT" || { say "  [diff] battery clamp unit missing or differs"; ok=0; }
    systemctl is-enabled -q oxp3-battery-clamp.service 2>/dev/null || { say "  [diff] oxp3-battery-clamp.service not enabled"; ok=0; }
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
    if [ -f "$MODPROBE_FILE" ]; then sudo rm -f "$MODPROBE_FILE"; say "  removed $MODPROBE_FILE"; NEED_REBOOT=1; fi
    if gyro_installed; then remove_gyro; fi
    rm -f "$GYRO_ON_FILE" "$GYRO_OFF_FILE"
    if [ -f "$IP_CAPMAP" ]; then sudo rm -f "$IP_CAPMAP"; say "  removed $IP_CAPMAP"; fi
    if [ -f "$IP_YAML" ]; then sudo systemctl disable --now inputplumber.service 2>/dev/null || true; sudo rm -f "$IP_YAML"; say "  InputPlumber disabled and OXP3 config removed (gamepad back to plain xpad)"; fi
    if [ -f "$VOLKEY_UNIT" ]; then sudo systemctl disable --now oxp3-volkey-fix.service 2>/dev/null || true; sudo rm -f "$VOLKEY_UNIT"; sudo systemctl daemon-reload; say "  oxp3-volkey-fix.service stopped and removed (volume keys back to raw EC behavior)"; fi
    if [ -f "$VOLKEY_PY" ]; then rm -f "$VOLKEY_PY"; say "  removed $VOLKEY_PY"; fi
    if [ -f "$BATT_UNIT" ]; then sudo systemctl disable --now oxp3-battery-clamp.service 2>/dev/null || true; sudo rm -f "$BATT_UNIT"; sudo systemctl daemon-reload; say "  oxp3-battery-clamp.service stopped and removed (raw kernel battery values again)"; fi
    if [ -f "$BATT_SH" ]; then rm -f "$BATT_SH"; say "  removed $BATT_SH"; fi
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
say "      + paddle driver state: hid-oxp gamepad_mode=xinput, button_m1/m2=KEY_F16/KEY_F17   $([ -n "$OXP_DEV" ] && echo "[hid-oxp OK]" || echo "[SKIPPED: hid-oxp not bound]")"
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
if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then read -r -p "  Continue? (y/N) " _ans; case "$_ans" in y|Y) ;; *) say "  cancelled."; exit 0 ;; esac; fi
sudo -v

# ---- 0. Wi-Fi / Bluetooth firmware --------------------------------------------------------------
# SteamOS' linux-firmware-neptune provides "linux-firmware" but not every chip family (the OXP3's BE201 needs
# iwlwifi-sc-a0-fm-c0-c10x + intel/ibt-00a0-0291-*). Download the repo's linux-firmware-intel package (cached) and
# extract only the missing families into /usr/lib/firmware; existing files are never overwritten and no package is
# replaced. Needs a writable rootfs and some network connection (USB Ethernet / USB tethering while Wi-Fi is down).
WIFI_FAILED=0
if [ "$SKIP_WIFI" = 1 ]; then
    say "  [skip] Wi-Fi firmware step disabled (--no-wifi)"
elif [ "$WIFI_MISSING" != 1 ] && [ "$BT_MISSING" != 1 ]; then
    say "  [skip] Wi-Fi/Bluetooth firmware: nothing missing"
elif ! command -v pacman >/dev/null 2>&1; then
    say "  [skip] pacman not found, cannot locate linux-firmware-intel"; WIFI_FAILED=1
elif ! ip route 2>/dev/null | grep -q '^default'; then
    say "  [skip] no network connection, cannot download linux-firmware-intel."
    say "         Connect USB Ethernet or USB tethering and run this script again."
    WIFI_FAILED=1
else
    hdr "0. Wi-Fi / Bluetooth firmware (from linux-firmware-intel)"
    if [ "$RO_STATUS" = "enabled" ]; then
        say "  rootfs is read-only; disabling so /usr/lib/firmware can be written (updates re-enable it)"
        sudo steamos-readonly disable
        RO_STATUS=disabled
    fi
    FW_URL="$(pacman -Sp linux-firmware-intel 2>/dev/null | grep -m1 '^http' || true)"
    if [ -z "$FW_URL" ]; then
        say "  [run] pacman -Sy   (package database sync, needed to locate linux-firmware-intel)"
        sudo pacman -Sy >/dev/null 2>&1 || true
        FW_URL="$(pacman -Sp linux-firmware-intel 2>/dev/null | grep -m1 '^http' || true)"
    fi
    if [ -z "$FW_URL" ]; then
        say "  [error] linux-firmware-intel not found in the configured repositories"; WIFI_FAILED=1
    else
        FW_CACHE="$USER_HOME/.cache/oxp3-fix"; mkdir -p "$FW_CACHE"
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
    say "  [skip] paddle driver state already correct (xinput / KEY_F16 / KEY_F17)"
else
    if [ "$OXP_MODE" != xinput ]; then
        printf 'xinput' | sudo tee "$OXP_DEV/gamepad_mode" >/dev/null && say "  [write] $(basename "$OXP_DEV")/gamepad_mode = xinput (was $OXP_MODE)"; CHANGED=1
    fi
    if [ "$OXP_M1" != KEY_F16 ]; then
        printf 'KEY_F16' | sudo tee "$OXP_DEV/button_m1" >/dev/null && say "  [write] $(basename "$OXP_DEV")/button_m1 = KEY_F16 (was $OXP_M1)"; CHANGED=1
    fi
    if [ "$OXP_M2" != KEY_F17 ]; then
        printf 'KEY_F17' | sudo tee "$OXP_DEV/button_m2" >/dev/null && say "  [write] $(basename "$OXP_DEV")/button_m2 = KEY_F17 (was $OXP_M2)"; CHANGED=1
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
