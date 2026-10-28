# SteamOS on the ONEXPLAYER 3 (Intel Panther Lake)

Everything you need to run SteamOS on the ONEXPLAYER 3, in two steps:

1. **Install SteamOS** with the recovery image.
2. **Run the fix pack.** One script that fixes what doesn't work out of the box: sleep, the OLED panel (black screen, HDR, refresh rates, VRR), the volume keys, the chassis keys and back paddles (also on the controller connector dock), the speakers, the battery percentage, the GPU power limit, the performance overlay, a log flood and big games crashing after sleep. The gyroscope (experimental) and a TDP plugin with a smarter CPU boost are optional.

**Where to start:**
- **Still on Windows:** start at step 1.
- **Already on SteamOS:** start at step 2. If you never set a password, run `passwd` in Konsole first. If you ran the fix pack before, download and run it again to get the latest version.
- **Another distribution with native Steam** (Bazzite, CachyOS, Arch, ...): the fix pack is SteamOS only.

## Step 1: Install SteamOS

You need a Windows PC with Rufus, a USB drive and later a temporary internet connection such as USB tethering from a phone.

> **Warning:** `repair_device.sh all` reinstalls SteamOS on the internal drive and erases everything on it. Back up first.

> **Why the TTY:** the recovery image's graphics driver doesn't work properly on this machine. Outside the TTY the screen keeps flooding with error messages. That's why you add the extra kernel parameters below and do several steps from the TTY.

**Prepare the USB drive**

1. Download `steamdeck-oobe-repair-20260707.10-3.8.14.img.bz2` from https://steamdeck-images.steamos.cloud/recovery/.
2. Flash it to a USB drive with Rufus.
3. When flashing is done, open `/EFI/steamos/grub.cfg` on the USB drive.
4. At the end of line 117, append `nomodeset 3 pci=noaer modprobe.blacklist=rtsx_pci`. It should look something like this:

   ```
   steamenv_boot linux /boot/vmlinuz-linux-neptune-616 console=tty1 rd.luks=0 rd.lvm=0 rd.md=0 rd.dm=0 rd.systemd.gpt_auto=no log_buf_len=4M amd_iommu=off amdgpu.lockup_timeout=5000,10000,10000,5000 ttm.pages_min=2097152 amdgpu.sched_hw_submission=4 amdgpu.dcdebugmask=0x20000 audit=0 fbcon=vc:4-6 fsck.mode=auto fsck.repair=preen  loglevel=3 quiet splash plymouth.ignore-serial-consoles nomodeset 3 pci=noaer modprobe.blacklist=rtsx_pci
   ```

**Install**

5. Boot from the USB drive. It boots into the TTY on its own.
6. Type `deck` to log in.
7. Run:

   ```bash
   cd ./tools
   sed -i 's/zenity/true/g' ./repair_device.sh
   sed -i 's/kdialog/true/g' ./repair_device.sh
   sudo ./repair_device.sh all
   ```

   **Installing to the second SSD (Mini SSD) instead:** `repair_device.sh` always installs to the disk in its `DISK=` line near the top (`nvme0n1`) and erases it. Run `lsblk -o NAME,SIZE,MODEL` to find the name of the disk you want. Then before `sudo ./repair_device.sh all` change that line, for example `sed -i 's|nvme0n1|nvme1n1|g' ./repair_device.sh`. Check it with `grep -n nvme ./repair_device.sh`. Go by size and model since the numbering can change between boots and machines. (Tip from issue #13.)

8. The install starts. Soon the OneXPlayer logo shows and the machine looks frozen for a long time. Don't touch it. Wait until the USB drive's light turns off completely. It takes about half an hour.
9. Press Ctrl+Alt+F4 to get back to the TTY and type `reboot`.
10. If the screen floods with errors, don't panic. Hold the power button to force it off.
11. Remove the USB drive and turn the device on. Wait a moment at the OneXPlayer logo.

**First boot**

12. Press Ctrl+Alt+F4, log in as `deck` and type `passwd` to set your password.
13. Connect to the internet, for example with USB tethering from your phone. `ping google.com` confirms it works.
14. Run:

    ```bash
    sudo steamos-select-branch main
    sudo steamos-update
    ```

15. When the update is done, reboot. The first boot takes a while.
16. You should hear the Steam startup chime. Connect an external monitor and you're in.

## Step 2: Run the fix pack

Before you start, remove your own earlier hacks, such as boot-time `chvt` scripts or a masked `powerbuttond`. SimpleDeckyTDP-Intel (the Smart CPU boost) needs [Decky Loader](https://decky.xyz). Install it first if you want it.

In Desktop Mode open Konsole and run:

```bash
cd ~ && curl -fL https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/latest/download/oxp3-fix.tar.gz | tar -xz
~/oxp3-fix/oxp3-apply-fixes.sh --check     # dry run, no sudo, changes nothing
~/oxp3-fix/oxp3-apply-fixes.sh             # apply: asks for your sudo password, confirms and says if a reboot is needed
~/oxp3-fix/oxp3-apply-fixes.sh --revert    # undo everything, then reboot
```

It asks once about the two optional parts (the gyroscope and SimpleDeckyTDP-Intel) and remembers your answers. `--gyro` / `--no-gyro` / `--sdtdp` / `--no-sdtdp` change them later.

**Run it again after every SteamOS update.** Updates reset parts of `/etc` and `/usr`. Running it twice is safe and it runs `steamos-readonly disable` when needed.

### What it fixes

| Symptom | Cause | Fix |
|---|---|---|
| **No Wi-Fi or Bluetooth** (Intel BE201, only SteamOS before 20261015.1000) | `linux-firmware-neptune` lacked the BE201 firmware files | Step 0 extracts only the missing files from the repo's `linux-firmware-intel` and caches them in `~/.cache/oxp3-fix`. Later runs work offline. Newer SteamOS ships them and the step skips itself |
| **Freeze on resume from sleep in game mode** | The Predator GM7 NVMe (`1dee:1602`) doesn't come back from s2idle through the ACPI StorageD3 path (`Disabling device after reset failure: -19`) | Kernel parameter `nvme.noacpi=1`, only when that SSD is present. Deep S0ix still works |
| **Big games crash with "out of memory" right after waking from sleep** (FF7 Rebirth, about 2 s after resume, with 11-16 GB free) | On suspend xe moves every GPU buffer out. On resume it rebinds every mapping in one array of 384 bytes per mapping. FF7R has about 33,500 mappings which means 12.9 MB. That's over the 4 MB kmalloc limit which means it fails every time (63 of 63 in a trace) and Mesa reports `execbuf ioctl keeps returning ENOMEM` | `oxp3-xevmafix.service` loads a small module ([`xevmafix/`](xevmafix/README.md)) that lets that one array come from vmalloc, the same change Intel already made in drm-xe-next. Built for one kernel only and skipped on any other |
| **No real HDR: PQ output leaves the panel black, frozen or at 30 Hz** | gamescope doesn't know this OLED (Samsung AMS881KB01-0). With PQ (BT.2020, SMPTE ST 2084) xe breaks it three ways. With Panel Replay, the MSA "colorimetry in VSC SDP" bit makes the panel keep its stored frame (black or frozen). The DPCD bit "fixed vtotal AS SDP in PR active" makes the panel show new frames at only 30 Hz, its VRR minimum, until the next wake from sleep (measured with a 120 fps camera: a new image every 33 ms). And after some switches to HDR the VSC SDP header keeps a bad ECC and the panel drops it (black) | `oxp3-xehdrfix.service` loads a small module ([`xehdrfix/`](xehdrfix/README.md)) before game mode starts. It clears both bits and writes the VSC SDP header again. While it's loaded the gamescope lua registers the panel with PQ HDR and its EDID luminance (1100 nits peak, 475 full screen). Without it (another kernel) the lua keeps the panel in its native gamma-2.2 mode and lets gamescope tone-map, like the Steam Deck OLED. Panel Replay stays on. The lua also registers the real 30-144 Hz VRR range. With `content_driven = true` SDR games keep the panel in SDR and scan out directly (RE4 at 30 W: 87 → 93 fps). The panel switches to HDR only while an HDR game is showing |
| **Game mode freezes, then goes black** (BIOS 5.11 and later, audio and controls keep working) | Panel Replay with selective update fails on this panel (`Selective fetch area calculation failed`). PSR1 freezes it later and with PSR off LOBF keeps it black. No module parameter turns LOBF off | `oxp3-panel-fix.service` turns LOBF and PSR/Panel Replay off through xe debugfs before the display manager starts. Only on this panel with BIOS 5.11+ (`--force-panel` overrides). Reboot needed |
| **VRR caps the frame rate at about 70-80 fps** (SteamOS 20261015.1000 and later) | Display firmware DMC v2.36 (`i915/xe3lpd_dmc.bin`). v2.20 works (issue #1) | DMC v2.20 in `/usr/lib/firmware/updates`, which the kernel prefers. Intel firmware, redistributed unmodified ([`firmware/LICENSE.i915`](firmware/LICENSE.i915)). Reboot needed |
| `xe ... DSB 0 poll error` message flood | The xe display state buffer fails on this panel | `options xe enable_dsb=0`. Cosmetic |
| **Volume keys stick** when pressed quickly | The embedded controller drops key-release scancodes | `oxp3-volkey-fix.service` re-sends each volume key as press plus release on a virtual keyboard |
| **Home, Console and Keyboard keys do nothing** | They come through the MCU keyboard and vendor interfaces | InputPlumber composite device: Home → Steam menu, Console → Quick Access, Keyboard → on-screen keyboard |
| **Home and G-key do nothing with the controllers on the connector dock** (issue #23) | The [controller connector](https://onexplayerstore.com/collections/accessories/products/controller-connector-for-onexplayer-x1) has its own chip (`1a86:fe02`) that sends these keys. Stock InputPlumber 0.78 only reads the handheld's `fe00` and drops the G-key code | The patched InputPlumber, now installed for everyone (the gyro stays opt-in), also reads `fe02` and maps the G-key to the Steam menu. If the patched one can't run, the stock binary starts instead |
| **Back paddles M1 and M2 don't work** | hid-oxp has to map them and switch the MCU report mode | hid-oxp maps them to two F13-F24 keys (F15/F16 on kernel 7.2.7) and InputPlumber turns them into the left and right paddle. The script only re-asserts the driver state through sysfs |
| **No sound from the speakers after boot or resume** | The ALC245 jack detection briefly reports headphones and PipeWire keeps the Headphones profile with the speaker amp off | `oxp3-audio-route.service` picks the Speaker profile, only when the jack is empty but a Headphones profile is active |
| **Battery shows 101-104 %** after a full charge | The gauge reports `energy_now` above `energy_full` and Steam reads the raw sysfs value | `oxp3-battery-clamp.service` overlays corrected `capacity` and `energy_full` values |
| **GPU stays throttled below the TDP you set** | TDP tools write the MMIO package PL1 but the GPU obeys the MSR PL1, which keeps the firmware's 25 W | `oxp3-tdp-sync.service` copies the MMIO PL1 into the MSR PL1 (checked every 2 s) |
| **The journal only holds the last hour** and `/var/lib/steamos-log-submitter` grows by hundreds of MB an hour | Panther Lake traps user-space split locks, Steam causes them all the time and every hit gets logged and queued as a report | Kernel parameter `split_lock_detect=off` (like the Steam Deck). Apply also deletes the queued split-lock reports. Reboot needed |
| **Performance overlay shows no CPU power, GPU power or GPU temperature** | The RAPL energy counters are root-only (CVE-2020-8694) and xe has no hwmon sensors for an integrated GPU | `oxp3-rapl-overlay.service` publishes coarse world-readable copies (0.5 s, 10 mJ) of the package, CPU core and GPU counters. A patched mangoapp ([`mangoapp/`](mangoapp/README.md)) shows CPU power (cores), GPU power (RAPL PP1), GPU temperature (= package temperature) and a SoC total on levels 2-4. It falls back to the stock mangoapp when it can't run |
| **CPU boost is all or nothing** in SimpleDeckyTDP (optional, fix pack step 14) | With boost off the cores stop at base clock. With boost on the E- and LP E-cores clock up too and take power the GPU could use | Installs [SimpleDeckyTDP-Intel](https://github.com/kas5852/SimpleDeckyTDP-Intel) by kas5852 (PR #24) with an **Off / Smart / Full** CPU Boost per game. Smart caps P / E / LP E-cores at 3.0 / 2.0 / 1.5 GHz: RE4 at 30 W gets +12 % average fps and +48 % 1% low |
| **No gyroscope** (experimental, opt in with `--gyro`) | The BMI260's ACPI node is named for the `bmi160` driver, which fails on it | ACPI override (BIOS 5.09). The patched InputPlumber above handles the sensor. Drift is reduced, not gone. Details in [`gyro/`](gyro/README.md) |

### Good to know

- The archive extracts to `~/oxp3-fix`: the script, the desktop icons and the binaries some steps use (patched InputPlumber, patched mangoapp, the SimpleDeckyTDP-Intel zip, the xevmafix kernel module) with their source patches. Extracting a newer release over it updates it in place.
- **Desktop icons (optional).** `OXP3-Fix.desktop` runs the fix pack and `OXP3-Revert.desktop` reverts it, each in a Konsole window where you type your password: `cp ~/oxp3-fix/OXP3-*.desktop ~/Desktop/ && chmod +x ~/Desktop/OXP3-*.desktop`
- Flags: `--yes`, `--force`, `--force-nvme`, `--force-panel`, `--no-wifi`, `--gyro`, `--no-gyro`, `--sdtdp`, `--no-sdtdp`. `--help` prints the full usage.
- Binaries come from the release archive with a pinned sha256. If one can't run, the stock version is used.
- **SimpleDeckyTDP-Intel** is a community fork, not affiliated with SimpleDeckyTDP. The zip is unmodified from [kas5852's release](https://github.com/kas5852/SimpleDeckyTDP-Intel/releases) (BSD 3-Clause, license inside the zip). If the original SimpleDeckyTDP is installed, it's removed only after you say yes. Its profiles get copied on first start and its settings file stays. Reinstall it from the Decky store and they come back. It sets the TDP the same way SimpleDeckyTDP does and the TDP sync keeps working. After install the plugin updates itself from the fork's releases (System Info page), not through this repo. Smart needs "Enable Manual CPU Controls" in the plugin's advanced options.
- **Older SteamOS without Wi-Fi:** connect USB Ethernet or USB tethering before the first run so fix pack step 0 can download the firmware.
- Never unbind or rebind hid-oxp (kernel Oops, `issues/hid_oxp_oops_rebind.txt`) and don't write raw commands to the `1a86:fe00` or `1a86:fe02` hidraw devices.
- The volume key fix grabs the i8042 keyboard and forwards every key, including power, through a virtual device. Keep that in mind with an external PS/2 keyboard.
- Files go to `/etc`, `/home`, `/usr/lib/firmware`, `~/homebrew/plugins` and, with the gyro, `/boot`. `--revert` removes all of them except the Wi-Fi firmware.
- **Lighting** isn't touched. From kernel 7.2.7 (SteamOS 20261013.1000) hid-oxp drives the three light zones natively (`oxp:rgb:joystick_rings`, `oxp:rgb:guide_button`, `oxp:rgb:rear_logo`). For a UI use the [modified fork of HueSync](https://github.com/HHHHanasak1/HueSync/tree/oxp3), a Decky plugin with three separate zones.

### Game pack (optional)

[oxp3-game-pack](https://github.com/kas5852/oxp3-game-pack) by kas5852 is a separate project with patched Intel Vulkan driver builds and measured per-game settings for Final Fantasy VII Rebirth, Cyberpunk 2077 and Resident Evil 4. At 30 W it measured FF7 Rebirth 52.6 → 72.7 fps, Cyberpunk 2077 59.0 → 79.3 fps (built-in benchmark) and RE4 89.8 → 95.4 fps. The fix pack doesn't need it. It installs without sudo, changes no system files and loads only for the games you give its launch option. Install it after the fix pack (with step 14 for the RE4 profile) and follow its README.

## Known issues and limitations

- **Gyroscope drift is only reduced.** The BMI260's yaw bias changes with temperature and gravity can't correct it. The patched InputPlumber lets the angle relax towards the centre (20 s time constant), which turns a constant bias into an offset of about 1-2 degrees. See [`gyro/README.md`](gyro/README.md).
- **High TDP needs a strong charger.** When the charger reports disconnected, the firmware resets the TDP to its battery limits and the TDP plugin puts it back a little later. A charger that can't cover the SoC, screen and charging flaps on and off and the limit bounces. For TDPs around 50 W use a 100 W USB PD charger.
- **Overlay power values are estimates.** CPU is the cores (RAPL PP0) and GPU is the graphics plane (PP1). The TDP covers the whole package, including the memory controller and display (a few watts). CPU + GPU stays a little under it. The SoC item shows the package total. The GPU temperature is the package temperature. Short spikes are smoothed by the 0.5 s copies.
- **Smart CPU caps stay until a reboot** after you remove SimpleDeckyTDP-Intel.
- **The panel fix (BIOS 5.11+) turns off panel self-refresh.** Static screens draw a bit more power (not measured). It uses xe debugfs files that a future kernel may rename. If that happens the service leaves the panel alone and says so in `journalctl -u oxp3-panel-fix`. Driver reports: [xe#8924](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8924), [xe#9517](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9517), [xe#8557](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8557), [Bazzite #5975](https://github.com/ublue-os/bazzite/issues/5975).
- **Split-lock detection is off.** The kernel no longer reports programs that use split locks. SteamOS didn't slow them down anyway (`kernel.split_lock_mitigate=0`).
- **The sleep fix (xevmafix) only loads on the kernel it was built for** (`7.2.7-valve2-2-neptune-72`, SteamOS main 20261026.1000). After a SteamOS update with a new kernel it's skipped until a rebuilt module ships and big games can crash after sleep again. The real fix is in the kernel: [patch sent to intel-xe](xevmafix/README.md#upstream), [SteamOS #2962](https://github.com/ValveSoftware/SteamOS/issues/2962).
- **PQ HDR (xehdrfix) also only loads on the kernel it was built for** (`7.2.7-valve2-2-neptune-72`). On any other kernel HDR games fall back to the gamma-2.2 path until a rebuilt module ships. In PQ, gamescope shows the SDR parts of an HDR game (menus, the overlay) at a fixed SDR white (`--hdr-sdr-content-nits`, 400 nits by default) instead of stretching them over the panel's range, so they can look darker than with the gamma-2.2 path. That's how PQ works, not a fault.
- **The volume key problem is in the embedded controller firmware.** A vendor firmware update would make the forwarder unnecessary.

Upstream bug drafts are in `issues/`.

## Tested configuration

SteamOS main 20261026.1000, kernel 7.2.7-valve2-2, OXP3 BIOS 5.09, panel SDC AMS881KB01-0, SSD Predator GM7 1TB. The panel fix was found and verified on BIOS 5.12. The script refuses to run on other DMI or OS values (`--force` overrides) and applies `nvme.noacpi=1` only with a GM7 / `1dee:1602` SSD (`--force-nvme` overrides). The patched InputPlumber needs the stock InputPlumber to be 0.78.x. The gyro step also needs BIOS 5.09.

## Changelog

Releases are named by date (`YYYYMMDD`) from 20261014 on.

- **20261028**: real HDR. HDR games now get PQ instead of the gamma-2.2 path, so highlights reach the panel's 1100 nits. New step 16, xehdrfix, fixes the three xe problems that made PQ black, frozen or 30 Hz on this panel. Panel Replay stays on. Without the module (another kernel) HDR stays on the gamma-2.2 path.
- **20261027**: xevmafix rebuilt for kernel 7.2.7-valve2-2 (SteamOS main 20261026.1000), so the sleep fix (step 15) loads again after that update. Nothing else changed.
- **20261023**: the patched InputPlumber is installed for everyone (the gyro stays opt-in) and also reads the controller connector, so Home and the G-key work with the controllers on the dock (issue #23).
- **20261022**: big games no longer crash with "out of memory" after waking from sleep (step 15, xevmafix, contributed by kas5852 in PR #26). Overlay: when the kernel skips the GPU energy zone at boot, step 10 now brings it back, so GPU power and the SoC total no longer go missing.
- **20261018-2**: optional SimpleDeckyTDP-Intel (step 14, contributed by kas5852 in PR #24) with an Off / Smart / Full CPU boost. A normal run asks once. The zip comes with the release archive. An installed SimpleDeckyTDP is replaced only after you confirm.
- **20261018**: panel fix for BIOS 5.11 and later (step 13, PR #15). Content-driven HDR (PR #22). Overlay: CPU power is the cores only, new SoC total on levels 2-4, no empty VRAM item.
- **20261016**: speaker route check (step 12), DMC v2.20 for the VRR cap (step 11), CPU and GPU power/temperature in the overlay (step 10).
- **20261015**: split-lock flood (step 9, PR #16). README notes from PR #17 and #18.
- **20261014**: support for the kernel 7.2.7 hid-oxp (native lighting, paddles on F15/F16).
- **v1.6.1 (2026-09-25)**: the Wi-Fi step works offline from the cached package.
- **v1.6.0 (2026-09-25)**: TDP sync (step 8).
- **v1.5.1 (2026-09-25)**: a single release archive extracting to `~/oxp3-fix`.
- **v1.5.0 (2026-09-24)**: experimental, opt-in gyroscope (step 7).
- **v1.4.0 (2026-09-22)**: battery percentage clamp (step 6).
- **v1.3.1 (2026-09-22)**: the Wi-Fi step extracts the BE201 files that `linux-firmware-neptune` lacks.
- **v1.3.0 (2026-09-20)**: Wi-Fi firmware on a fresh install (step 0).
- **v1.2.0 (2026-09-12)**: back paddles through hid-oxp.
- **v1.1.0 (2026-09-10)**: 30-144 Hz `dynamic_modegen` in the HDR lua.
- **v1.0 (2026-09-06)**: initial release.
