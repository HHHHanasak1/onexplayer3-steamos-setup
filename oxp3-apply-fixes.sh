#!/bin/bash
# oxp3-steamos-fixes - ONEXPLAYER 3 (Intel Panther Lake) SteamOS fix pack
# Version: v1.3.0 (2026-09-20)     License: MIT (see LICENSE)     Author: HANA & Claude
# Tested on: SteamOS 3.10 main build 20260827.1000, kernel 7.2.0-valve1-1-neptune-72, OXP3 BIOS 5.09,
#            panel Samsung SDC AMS881KB01-0, SSD Predator GM7 1TB (Biwin/Maxio 1dee:1602)
# v1.1.0: gamescope HDR lua now also registers real 30-144Hz dynamic_modegen (this panel has genuine
#         continuous VRR; the v1.0.1 lua declared dynamic_refresh_rates but never shipped the
#         matching dynamic_modegen function, so no extra Hz options ever actually appeared in the
#         Steam Performance panel's per-game refresh-rate selector).
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
OXP3_FIXES_VERSION="v1.3.1 (2026-09-22)"
TESTED_STEAMOS_BUILD="20260827.1000"
TESTED_KERNEL_PREFIX="7.2.0-valve1"
# ============================================================================
# ONEXPLAYER 3 fix re-applier  (SteamOS 3.10, Intel Panther Lake, xe)
# Purpose:
#   SteamOS updates may overwrite /etc changes. This script re-applies all five fixes (idempotent),
#   preceded by step 0 which gets Wi-Fi working on a fresh install:
#     0) Wi-Fi firmware - unlock the root filesystem, initialize the pacman keyring, install linux-firmware (--no-wifi skips)
#     1) kernel param nvme.noacpi=1 (only for the Predator GM7 / 1dee:1602 SSD) - NVMe not resuming from s2idle
#     2) xe enable_dsb=0 - silence the per-frame xe DSB error flood under gamescope
#     3) gamescope known-display lua - HDR via the gamma2.2 path (native BT.2020/PQ output blanks the
#        panel), plus registers the panel's real 30-144Hz continuous VRR so the Steam Performance
#        panel's per-game refresh-rate selector actually has more than one option
#     4) volume-key fix service - the EC drops key releases; an evdev proxy synthesises them
#     5) InputPlumber composite device + capability map - Home/Console/Keyboard keys, back paddles as L4/R4, single virtual gamepad
#        (paddles rely on the in-kernel hid-oxp driver; this script only re-asserts its sysfs state, it never writes the MCU directly)
# Usage:
#   ./oxp3-apply-fixes.sh                apply (asks sudo password, prints the plan and confirms)
#   ./oxp3-apply-fixes.sh --check        check only, changes nothing, needs no sudo (covers all five fixes)
#   ./oxp3-apply-fixes.sh --revert       undo all five fixes (then reboot)
#   ./oxp3-apply-fixes.sh --mcu-restore  [DANGEROUS] raw-writes MCU button-table page 3 (Home/Xbox) to factory values, asks to confirm.
#                                        Use ONLY if Home/Xbox are already dead. A wrong write can kill chassis keys for good and
#                                        cannot be read back or verified. Normal users must NOT run this. No other option writes the MCU.
#   flags: --yes no confirmation prompt | --force skip the device/OS guards | --force-nvme apply nvme.noacpi=1 on any SSD
#          --no-wifi skip step 0 (Wi-Fi firmware)
# Idempotent: safe to run repeatedly.
# ============================================================================
set -euo pipefail

MODE="apply"; FORCE=0; FORCE_NVME=0; ASSUME_YES=0; SKIP_WIFI=0
for a in "$@"; do
    case "$a" in
        --check) MODE="--check" ;;
        --revert) MODE="--revert" ;;
        --mcu-restore) MODE="--mcu-restore" ;;  # DANGEROUS: restore MCU button page 3 (Home/Xbox)
        --force) FORCE=1 ;;            # skip DMI + OS guards
        --force-nvme) FORCE_NVME=1 ;;  # apply nvme.noacpi=1 regardless of SSD model
        --yes|-y) ASSUME_YES=1 ;;      # no confirmation prompt
        --no-wifi) SKIP_WIFI=1 ;;      # skip step 0 (Wi-Fi firmware)
        -h|--help) sed -n '2,50p' "$0" | grep -E '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a  (valid: --check | --revert | --mcu-restore | --force | --force-nvme | --no-wifi | --yes)"; exit 2 ;;
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
IP_YAML=/etc/inputplumber/devices.d/50-onexplayer_3.yaml
IP_CAPMAP=/etc/inputplumber/capability_maps.d/onexplayer_type3.yaml   # id oxp3: Home key -> Guide   # InputPlumber 0.78 override dir is devices.d

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

# ---- helpers ------------------------------------------------------
say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n== %s ==\n' "$*"; }
same_content() { # same_content <file> <content>  -> 0 if identical
    [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]
}
CHANGED=0; NEED_REBOOT=0; NEED_RELOGIN=0; VOLKEY_RESTART=0; IP_RESTART=0

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
    same_content "$IP_YAML" "$IP_YAML_CONTENT" || { say "  [diff] IP yaml missing or differs"; ok=0; }
    same_content "$IP_CAPMAP" "$IP_CAPMAP_CONTENT" || { say "  [diff] IP capability map missing or differs"; ok=0; }
    systemctl is-enabled -q inputplumber.service 2>/dev/null || { say "  [diff] inputplumber.service not enabled"; ok=0; }
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
    if [ -f "$IP_CAPMAP" ]; then sudo rm -f "$IP_CAPMAP"; say "  removed $IP_CAPMAP"; fi
    if [ -f "$IP_YAML" ]; then sudo systemctl disable --now inputplumber.service 2>/dev/null || true; sudo rm -f "$IP_YAML"; say "  InputPlumber disabled and OXP3 config removed (gamepad back to plain xpad)"; fi
    if [ -f "$VOLKEY_UNIT" ]; then sudo systemctl disable --now oxp3-volkey-fix.service 2>/dev/null || true; sudo rm -f "$VOLKEY_UNIT"; sudo systemctl daemon-reload; say "  oxp3-volkey-fix.service stopped and removed (volume keys back to raw EC behavior)"; fi
    if [ -f "$VOLKEY_PY" ]; then rm -f "$VOLKEY_PY"; say "  removed $VOLKEY_PY"; fi
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
