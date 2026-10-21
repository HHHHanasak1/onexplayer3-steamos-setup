# SteamOS on the ONEXPLAYER 3 (Intel Panther Lake)

Everything you need to run SteamOS on the ONEXPLAYER 3, in three steps:

1. **Install SteamOS** with the recovery image.
2. **Run the fix pack.** One script that fixes what doesn't work out of the box: sleep, the OLED panel (black screen, HDR, refresh rates, VRR), the volume keys, the chassis keys and back paddles, the speakers, the battery percentage, the GPU power limit, the performance overlay and a log flood. The gyroscope (experimental) and a TDP plugin with a smarter CPU boost are optional.
3. **Add the game pack (optional).** Faster Final Fantasy VII Rebirth, Cyberpunk 2077 and Resident Evil 4.

**Where to start:**
- **Still on Windows:** start at step 1.
- **Already on SteamOS:** start at step 2. If you never set a password, run `passwd` in Konsole first. If you ran the fix pack before, download and run it again to get the latest version.
- **Another distribution with native Steam** (Bazzite, CachyOS, Arch, ...): the fix pack is SteamOS only. Skip to step 3 for the game pack.

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

> **Tip: let an AI agent do the typing.** A coding agent on your PC can SSH into the OXP3, run the steps, read the `--check` output and fix what breaks while you hold the device. To let it in, set a password (step 1.12 or `passwd` in Konsole), then run `sudo systemctl enable --now sshd` and `ip -4 addr` in Konsole to get the address. It connects with `ssh deck@<that address>` from a PC on the same Wi-Fi. `sudo systemctl disable --now sshd` turns SSH off again.

## Step 2: Run the fix pack

Before you start, remove your own earlier hacks, such as boot-time `chvt` scripts or a masked `powerbuttond`. SimpleDeckyTDP-Intel (the Smart CPU boost and the game pack's power profiles) needs [Decky Loader](https://decky.xyz). Install it first if you want it.

In Desktop Mode open Konsole and run:

```bash
cd ~ && curl -fL https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/latest/download/oxp3-fix.tar.gz | tar -xz
~/oxp3-fix/oxp3-apply-fixes.sh --check     # dry run, no sudo, changes nothing
~/oxp3-fix/oxp3-apply-fixes.sh             # apply: asks for your sudo password, confirms and says if a reboot is needed
~/oxp3-fix/oxp3-apply-fixes.sh --revert    # undo everything, then reboot
```

It asks once about the two optional parts (the gyroscope and SimpleDeckyTDP-Intel) and remembers your answers. `--gyro` / `--no-gyro` / `--sdtdp` / `--no-sdtdp` change them later. Say yes to SimpleDeckyTDP-Intel if you want the game pack's power profiles.

**Run it again after every SteamOS update.** Updates reset parts of `/etc` and `/usr`. Running it twice is safe and it runs `steamos-readonly disable` when needed.

### What it fixes

| Symptom | Cause | Fix |
|---|---|---|
| **No Wi-Fi or Bluetooth** (Intel BE201, only SteamOS before 20261015.1000) | `linux-firmware-neptune` lacked the BE201 firmware files | Step 0 extracts only the missing files from the repo's `linux-firmware-intel` and caches them in `~/.cache/oxp3-fix`. Later runs work offline. Newer SteamOS ships them and the step skips itself |
| **Freeze on resume from sleep in game mode** | The Predator GM7 NVMe (`1dee:1602`) doesn't come back from s2idle through the ACPI StorageD3 path (`Disabling device after reset failure: -19`) | Kernel parameter `nvme.noacpi=1`, only when that SSD is present. Deep S0ix still works |
| **Panel stays black in game mode** and the brightness slider does nothing | gamescope drives the OLED (Samsung AMS881KB01-0) in BT.2020/PQ but xe never turns on the panel's HDR backlight channel | A gamescope lua keeps the panel in its native gamma-2.2 mode and lets gamescope tone-map, like the Steam Deck OLED. It also registers the real 30-144 Hz VRR range. With `content_driven = true` SDR games keep the panel in SDR and scan out directly (RE4 at 30 W: 87 → 93 fps). The panel switches to HDR only while an HDR game is showing |
| **Game mode freezes, then goes black** (BIOS 5.11 and later, audio and controls keep working) | Panel Replay with selective update fails on this panel (`Selective fetch area calculation failed`). PSR1 freezes it later and with PSR off LOBF keeps it black. No module parameter turns LOBF off | `oxp3-panel-fix.service` turns LOBF and PSR/Panel Replay off through xe debugfs before the display manager starts. Only on this panel with BIOS 5.11+ (`--force-panel` overrides). Reboot needed |
| **VRR caps the frame rate at about 70-80 fps** (SteamOS 20261015.1000 and later) | Display firmware DMC v2.36 (`i915/xe3lpd_dmc.bin`). v2.20 works (issue #1) | DMC v2.20 in `/usr/lib/firmware/updates`, which the kernel prefers. Intel firmware, redistributed unmodified ([`firmware/LICENSE.i915`](firmware/LICENSE.i915)). Reboot needed |
| `xe ... DSB 0 poll error` message flood | The xe display state buffer fails on this panel | `options xe enable_dsb=0`. Cosmetic |
| **Volume keys stick** when pressed quickly | The embedded controller drops key-release scancodes | `oxp3-volkey-fix.service` re-sends each volume key as press plus release on a virtual keyboard |
| **Home, Console and Keyboard keys do nothing** | They come through the MCU keyboard and vendor interfaces | InputPlumber composite device: Home → Steam menu, Console → Quick Access, Keyboard → on-screen keyboard |
| **Back paddles M1 and M2 don't work** | hid-oxp has to map them and switch the MCU report mode | hid-oxp maps them to two F13-F24 keys (F15/F16 on kernel 7.2.7) and InputPlumber turns them into the left and right paddle. The script only re-asserts the driver state through sysfs |
| **No sound from the speakers after boot or resume** | The ALC245 jack detection briefly reports headphones and PipeWire keeps the Headphones profile with the speaker amp off | `oxp3-audio-route.service` picks the Speaker profile, only when the jack is empty but a Headphones profile is active |
| **Battery shows 101-104 %** after a full charge | The gauge reports `energy_now` above `energy_full` and Steam reads the raw sysfs value | `oxp3-battery-clamp.service` overlays corrected `capacity` and `energy_full` values |
| **GPU stays throttled below the TDP you set** | TDP tools write the MMIO package PL1 but the GPU obeys the MSR PL1, which keeps the firmware's 25 W | `oxp3-tdp-sync.service` copies the MMIO PL1 into the MSR PL1 (checked every 2 s) |
| **The journal only holds the last hour** and `/var/lib/steamos-log-submitter` grows by hundreds of MB an hour | Panther Lake traps user-space split locks, Steam causes them all the time and every hit gets logged and queued as a report | Kernel parameter `split_lock_detect=off` (like the Steam Deck). Apply also deletes the queued split-lock reports. Reboot needed |
| **Performance overlay shows no CPU power, GPU power or GPU temperature** | The RAPL energy counters are root-only (CVE-2020-8694) and xe has no hwmon sensors for an integrated GPU | `oxp3-rapl-overlay.service` publishes coarse world-readable copies (0.5 s, 10 mJ) of the package, CPU core and GPU counters. A patched mangoapp ([`mangoapp/`](mangoapp/README.md)) shows CPU power (cores), GPU power (RAPL PP1), GPU temperature (= package temperature) and a SoC total on levels 2-4. It falls back to the stock mangoapp when it can't run |
| **CPU boost is all or nothing** in SimpleDeckyTDP (optional, fix pack step 14) | With boost off the cores stop at base clock. With boost on the E- and LP E-cores clock up too and take power the GPU could use | Installs [SimpleDeckyTDP-Intel](https://github.com/kas5852/SimpleDeckyTDP-Intel) by kas5852 (PR #24) with an **Off / Smart / Full** CPU Boost per game. Smart caps P / E / LP E-cores at 3.0 / 2.0 / 1.5 GHz: RE4 at 30 W gets +12 % average fps and +48 % 1% low |
| **No gyroscope** (experimental, opt in with `--gyro`) | The BMI260's ACPI node is named for the `bmi160` driver, which fails on it | ACPI override (BIOS 5.09) plus a patched InputPlumber. Drift is reduced, not gone. Details in [`gyro/`](gyro/README.md) |

### Good to know

- The archive extracts to `~/oxp3-fix`: the script, the desktop icons and the binaries some steps use (patched InputPlumber for the gyro, patched mangoapp, the SimpleDeckyTDP-Intel zip) with their source patches. Extracting a newer release over it updates it in place.
- **Desktop icons (optional).** `OXP3-Fix.desktop` runs the fix pack and `OXP3-Revert.desktop` reverts it, each in a Konsole window where you type your password: `cp ~/oxp3-fix/OXP3-*.desktop ~/Desktop/ && chmod +x ~/Desktop/OXP3-*.desktop`
- Flags: `--yes`, `--force`, `--force-nvme`, `--force-panel`, `--no-wifi`, `--gyro`, `--no-gyro`, `--sdtdp`, `--no-sdtdp`. `--help` prints the full usage.
- Binaries come from the release archive with a pinned sha256. If one can't run, the stock version is used.
- **SimpleDeckyTDP-Intel** is a community fork, not affiliated with SimpleDeckyTDP. The zip is unmodified from [kas5852's release](https://github.com/kas5852/SimpleDeckyTDP-Intel/releases) (BSD 3-Clause, license inside the zip). If the original SimpleDeckyTDP is installed, it's removed only after you say yes. Its profiles get copied on first start and its settings file stays. Reinstall it from the Decky store and they come back. It sets the TDP the same way SimpleDeckyTDP does and the TDP sync keeps working. After install the plugin updates itself from the fork's releases (System Info page), not through this repo. Smart needs "Enable Manual CPU Controls" in the plugin's advanced options.
- **Older SteamOS without Wi-Fi:** connect USB Ethernet or USB tethering before the first run so fix pack step 0 can download the firmware.
- Never unbind or rebind hid-oxp (kernel Oops, `issues/hid_oxp_oops_rebind.txt`) and don't write raw commands to the `1a86:fe00` hidraw device.
- The volume key fix grabs the i8042 keyboard and forwards every key, including power, through a virtual device. Keep that in mind with an external PS/2 keyboard.
- Files go to `/etc`, `/home`, `/usr/lib/firmware` and `~/homebrew/plugins`. `--revert` removes all of them except the Wi-Fi firmware.
- **Lighting** isn't touched. From kernel 7.2.7 (SteamOS 20261013.1000) hid-oxp drives the three light zones natively (`oxp:rgb:joystick_rings`, `oxp:rgb:guide_button`, `oxp:rgb:rear_logo`). For a UI use the [modified fork of HueSync](https://github.com/HHHHanasak1/HueSync/tree/oxp3), a Decky plugin with three separate zones.

## Step 3: Add the game pack (optional)

Patched Intel Vulkan driver builds, a one-line vkd3d-proton fix and per-game settings that keep the games off the four LP E-cores without L3 cache. It installs into your home folder without sudo, changes no system files and `--revert` removes it. It's a separate download and the fix pack doesn't need it.

Measured on one ONEXPLAYER 3 at 30 W, same scene and settings before and after:

| Game | Before | With the pack | Scene |
|---|---|---|---|
| Final Fantasy VII Rebirth | 52.6 fps, 1% low 39.7 | **72.7 fps, 1% low 58.6** | Gongaga field, 1080p, TAA. A ROG Xbox Ally X (Z2 Extreme) does 55.5 fps here at 30 W |
| Cyberpunk 2077 | 59.0 fps | **79.3 fps** | Built-in benchmark, Steam Deck preset |
| Resident Evil 4 | 89.8 fps | **95.4 fps, 1% low 70.5** | Chapter 6, needs the power profile below |

On SteamOS run the fix pack first, since its TDP sync is part of these numbers. On another distribution you need the native Steam client (the installer refuses Flatpak Steam), `python3` and a TDP tool.

**1. Set the three games to Proton Experimental** (game > ⚙ > Properties > Compatibility). That's what the numbers used.

**2. Download and run the installer** in Konsole. It's hosted on kas5852's fork:

```bash
cd ~ && curl -fL https://github.com/kas5852/onexplayer3-steamos-setup/releases/download/game-pack-20261020/oxp3-game-pack.tar.gz | tar -xz
~/oxp3-game-pack/oxp3-game-pack.sh
```

Keep the `~/oxp3-game-pack` folder since the games load the driver from it.

**3. Paste the launch options** (game > ⚙ > Properties > General > Launch Options):

| Game | Launch option |
|---|---|
| Cyberpunk 2077 | `~/oxp3-game-pack/oxp3-run %command% --launcher-skip -skipStartScreen` |
| Resident Evil 4 | `~/oxp3-game-pack/oxp3-run %command%` |
| Final Fantasy VII Rebirth | `~/oxp3-game-pack/oxp3-run %command%` |

Already have launch options? Put your own variables in front, for example `MANGOHUD=1 ~/oxp3-game-pack/oxp3-run %command%`.

**4. Set a per-game power profile.** Back in Game Mode, start the game, open SimpleDeckyTDP, turn on the per-game profile and set:

| Game | TDP | GPU frequency | EPP | CPU Boost |
|---|---|---|---|---|
| Resident Evil 4 | 30 W | **Range, 650-2200 MHz** | **performance** | Smart |
| Final Fantasy VII Rebirth | 30 W | default | **performance** | default |
| Cyberpunk 2077 | 30 W | default | balance_performance | default |

EPP is in the plugin's advanced options. RE4's GPU cap matters most. Without it the faster driver runs the GPU into the power limit and the 1% low drops from about 70 to 58.

**5. Play.** The first launch of each game rebuilds its shaders for the new driver. Expect a longer load and some stutter for the first few minutes before you judge anything.

**Check it:** `~/oxp3-game-pack/oxp3-game-pack.sh --check` shows which driver builds load and whether each game's settings, DLLs and launch option are in place. `pack=on` after the last launch means the game ran with the pack. Paste this output with your numbers (scene, TDP, in-game preset) when you report results in the Discord or a [GitHub issue](https://github.com/HHHHanasak1/onexplayer3-steamos-setup/issues).

**Compare against stock:** put `OXP3_PACK=0` at the front of a game's launch option and run the same scene again.

**Remove it:** `~/oxp3-game-pack/oxp3-game-pack.sh --revert`, then delete the `oxp3-run` part from each launch option.

Where each gain comes from, troubleshooting, XeSS on the XMX units, the build sources and the patches are all in [game-pack/README.md](game-pack/README.md).

## Known issues and limitations

- **Games can crash about 2 seconds after waking from sleep** with an out-of-memory error. They aren't out of memory. It's a bug in Intel's xe kernel driver that hits big games like FF7 Rebirth, with or without the game pack ([SteamOS #2962](https://github.com/ValveSoftware/SteamOS/issues/2962)). A fix for the fix pack is on the way ([PR #26](https://github.com/HHHHanasak1/onexplayer3-steamos-setup/pull/26)). Until then, close big games before you put the device to sleep.
- **Gyroscope drift is only reduced.** The BMI260's yaw bias changes with temperature and gravity can't correct it. The patched InputPlumber lets the angle relax towards the centre (20 s time constant), which turns a constant bias into an offset of about 1-2 degrees. See [`gyro/README.md`](gyro/README.md).
- **High TDP needs a strong charger.** When the charger reports disconnected, the firmware resets the TDP to its battery limits and the TDP plugin puts it back a little later. A charger that can't cover the SoC, screen and charging flaps on and off and the limit bounces. For TDPs around 50 W use a 100 W USB PD charger.
- **Overlay power values are estimates.** CPU is the cores (RAPL PP0) and GPU is the graphics plane (PP1). The TDP covers the whole package, including the memory controller and display (a few watts). CPU + GPU stays a little under it. The SoC item shows the package total. The GPU temperature is the package temperature. Short spikes are smoothed by the 0.5 s copies.
- **Smart CPU caps stay until a reboot** after you remove SimpleDeckyTDP-Intel.
- **The panel fix (BIOS 5.11+) turns off panel self-refresh.** Static screens draw a bit more power (not measured). It uses xe debugfs files that a future kernel may rename. If that happens the service leaves the panel alone and says so in `journalctl -u oxp3-panel-fix`. Driver reports: [xe#8924](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8924), [xe#9517](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9517), [xe#8557](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8557), [Bazzite #5975](https://github.com/ublue-os/bazzite/issues/5975).
- **Split-lock detection is off.** The kernel no longer reports programs that use split locks. SteamOS didn't slow them down anyway (`kernel.split_lock_mitigate=0`).
- **HDR uses the gamma-2.2 path.** A true PQ path (`xe.enable_dpcd_backlight=1`) hasn't been tested.
- **The volume key problem is in the embedded controller firmware.** A vendor firmware update would make the forwarder unnecessary.

Upstream bug drafts are in `issues/`.

## Tested configuration

SteamOS main 20261015.1000, kernel 7.2.7-valve2, OXP3 BIOS 5.09, panel SDC AMS881KB01-0, SSD Predator GM7 1TB. The panel fix was found and verified on BIOS 5.12. The script refuses to run on other DMI or OS values (`--force` overrides) and applies `nvme.noacpi=1` only with a GM7 / `1dee:1602` SSD (`--force-nvme` overrides). The gyro step needs BIOS 5.09 and InputPlumber 0.78.x.

## Changelog

Releases are named by date (`YYYYMMDD`) from 20261014 on.

- **Unreleased**: optional game pack (`game-pack/`, separate download): patched Mesa builds, vkd3d-proton hostsync DLLs and per-game settings for Cyberpunk 2077, Resident Evil 4 and Final Fantasy VII Rebirth.
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
