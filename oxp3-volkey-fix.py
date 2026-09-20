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
