# SteamOS on the ONEXPLAYER 3 (Intel Panther Lake): install guide and fix pack

This repository covers everything needed to run SteamOS on the ONEXPLAYER 3, from a blank drive to a working machine:

1. **Part 1** is a step-by-step guide to installing SteamOS with the recovery image.
2. **Part 2** is a fix pack, one script that repairs what does not work out of the box: Wi-Fi, suspend/resume, the HDR panel and refresh rates, volume keys, the chassis keys and back paddles, the battery percentage, the GPU power limit, the missing CPU power reading in the performance overlay, a split-lock report flood that fills the journal and the disk, and (experimental, opt-in) the gyroscope.

## Part 1 - Installing SteamOS

This is the recovery-image method that works on this machine. You need a Windows PC with Rufus, a USB drive, and later a temporary network connection such as USB tethering from a phone.

> **Warning:** `repair_device.sh all` reinstalls SteamOS on the internal drive and erases what is on it. Back up first.

> **Why the TTY:** the graphics driver in the recovery image does not work properly on this machine. Unless you switch to the TTY, the screen is flooded with error messages continuously. That is why the extra kernel parameters are added below and why several steps are done from the TTY.

**Prepare the USB drive**

1. Download `steamdeck-oobe-repair-20260707.10-3.8.14.img.bz2` from https://steamdeck-images.steamos.cloud/recovery/.
2. Flash the image to a USB drive with Rufus.
3. When flashing is complete, open `/EFI/steamos/grub.cfg` on the USB drive.
4. At the end of line 117, append these parameters: `nomodeset 3 pci=noaer modprobe.blacklist=rtsx_pci`

   It should look something like this:

   ```
   steamenv_boot linux /boot/vmlinuz-linux-neptune-616 console=tty1 rd.luks=0 rd.lvm=0 rd.md=0 rd.dm=0 rd.systemd.gpt_auto=no log_buf_len=4M amd_iommu=off amdgpu.lockup_timeout=5000,10000,10000,5000 ttm.pages_min=2097152 amdgpu.sched_hw_submission=4 amdgpu.dcdebugmask=0x20000 audit=0 fbcon=vc:4-6 fsck.mode=auto fsck.repair=preen  loglevel=3 quiet splash plymouth.ignore-serial-consoles nomodeset 3 pci=noaer modprobe.blacklist=rtsx_pci
   ```

**Install**

5. Insert the USB drive and boot from it. The system boots into the TTY interface automatically.
6. Type `deck` to log in.
7. Enter the following commands:

   ```bash
   cd ./tools
   sed -i 's/zenity/true/g' ./repair_device.sh
   sed -i 's/kdialog/true/g' ./repair_device.sh
   sudo ./repair_device.sh all
   ```

8. The installation begins. After a moment the machine shows the OneXPlayer logo and appears to be completely frozen. This state lasts a long time. Do **not** touch or operate the machine. Wait until the USB drive's read/write indicator light turns off completely; this took about half an hour.
9. Once the light is off, press Ctrl+Alt+F4 to return to the TTY and type `reboot`.
10. You may see a massive amount of error logs flooding the screen. Do not panic, just press and hold the power button to force a shutdown.
11. Remove the USB drive and power on the device. Wait a moment at the OneXPlayer logo screen.

**First boot**

12. Press Ctrl+Alt+F4 to enter the TTY, type `deck` to log in, then type `passwd` to set your password.
13. Connect to the internet, for example with USB tethering from your phone. You can ping google.com to confirm the connection is active.
14. Run:

    ```bash
    sudo steamos-select-branch main
    sudo steamos-update
    ```

15. Wait for the system update to complete, then reboot. The first boot takes a while.
16. You should hear the familiar Steam startup chime. Connect an external monitor and you will enter the system.

## Part 2 - The fix pack

### What it fixes

| Symptom | Root cause | Fix |
|---|---|---|
| **No Wi-Fi / no Bluetooth** (Intel BE201 CNVi `8086:e440`, `iwlwifi`; SteamOS before 20261015.1000 only) | SteamOS' own `linux-firmware-neptune` satisfies `linux-firmware` but lacks the BE201 files (`iwlwifi-sc-a0-fm-c0-c10x`, `intel/ibt-00a0-0291-*`); every OS update restores that package | Step 0 downloads the repo's `linux-firmware-intel` once (cached in `~/.cache/oxp3-fix`) and extracts only the missing firmware families into `/usr/lib/firmware`, without overwriting files or replacing packages. Needs a temporary network connection (USB Ethernet or phone tethering). Wi-Fi works right away, Bluetooth after the reboot. SteamOS 20261015.1000 and later ship upstream `linux-firmware`, which includes these files; the step then finds nothing missing and skips itself without changing anything. |
| **Game-mode suspend/resume freeze** | The Predator GM7 NVMe (Biwin/Maxio `1dee:1602`) fails to come back from s2idle through the ACPI StorageD3 path (`nvme nvme0: Disabling device after reset failure: -19`), and the root filesystem goes away | Kernel parameter `nvme.noacpi=1` via `/etc/default/grub.d/oxp3-nvme.cfg` plus `update-grub`. Applied only when that SSD is present. Deep S0ix is still reached |
| **Panel stays black in game mode** after boot, session switch or resume; brightness slider does nothing | gamescope enables HDR and xe drives the Samsung AMS881KB01-0 OLED with BT.2020/PQ 10 bpc. The panel implements Intel's eDP HDR interface but the driver never enables its backlight channel, so the output is treated as SDR | A gamescope known-display lua keeps the panel in native gamma-2.2 mode and lets gamescope tone-map internally, the same approach as the Steam Deck OLED. HDR works and the brightness slider starts working |
| **Performance panel sometimes offers only one refresh rate** | The panel has genuine continuous 30-144 Hz VRR, but the lua only declared `dynamic_refresh_rates` without the matching `dynamic_modegen` function, so gamescope never generated any real modes | The same lua now registers the full 30-144 Hz range. The timing formula is derived from, and verified against, the 60 Hz and 144 Hz modes reported by the driver |
| Per-frame `xe ... DSB 0 poll error` kernel message flood | The xe display state buffer fails on this panel | `options xe enable_dsb=0` in `/etc/modprobe.d/xe-oxp3.conf`. Cosmetic, only silences the messages |
| **Volume keys stick** when pressed quickly | The embedded controller drops the key-release scancodes on the i8042 keyboard, so the kernel sees the key held down | `oxp3-volkey-fix.service`, a boot-time evdev forwarder that grabs the raw device and re-emits each volume key as a press plus release on a virtual keyboard without autorepeat |
| **Home, Console and Keyboard keys do nothing** | These keys are reported through the MCU keyboard and vendor interfaces | An InputPlumber composite device plus capability map: Home to Steam menu, Console to Quick Access, Keyboard to the on-screen keyboard |
| **Battery shows 101-104 %** after a full charge (Steam UI and performance overlay) | The gauge reports `energy_now` above its own `energy_full` (92.2 vs 89.9 Wh, design 84.5 Wh). The ACPI battery driver only clamps when `energy_full` is below the design value, so `capacity` becomes 103; upower clamps, but Steam reads the sysfs value through its bundled SDL3 and the overlay divides `energy_now` by `energy_full` itself | `oxp3-battery-clamp.service`, a root service that bind-mounts corrected `capacity` and `energy_full` files over the two sysfs attributes (`energy_full` = the larger of the kernel value and the highest `energy_now` seen), refreshed once a minute. |
| **Back paddles M1 and M2 do not work** | They need the hid-oxp driver to map them and switch the MCU report mode | hid-oxp maps M1 and M2 to `KEY_F16` and `KEY_F17` and cycles the report mode at boot. The MCU then emits vendor frames that InputPlumber decodes as the left and right paddle. On the OXP3 the physical left paddle is `0x22`, so the left/right swap inherited from the OneXPlayer 8 map was removed. The script only re-asserts the driver state through sysfs |
| **GPU stays throttled below the TDP you set** (e.g. 1600-1850 of 2300 MHz, throttle reason `pl1`, about 33 W package power with a 50 W TDP) | Panther Lake has two package power-limit interfaces. TDP tools such as SimpleDeckyTDP and the firmware (AC/DC switch) only write the MMIO one (`intel-rapl-mmio:0`), while the MSR one (`intel-rapl:0`) keeps the firmware's 25 W PL1. CPU loads follow the MMIO limit, but the GPU obeys the MSR PL1 | `oxp3-tdp-sync.service`, a root service that copies the MMIO PL1 into the MSR PL1 whenever they differ (checked every 2 s), so whatever sets the TDP also sets the limit the GPU obeys. With 50 W the GPU then runs at 2300 MHz unthrottled. Only PL1 is touched; `--revert` removes it and the firmware value returns after a reboot |
| **The system journal only holds the last hour or so, and `/var/lib/steamos-log-submitter` grows by hundreds of MB an hour** while Steam runs | Panther Lake traps user-space split locks (`split_lock_detect` defaults to warn), and Steam's `CHTTPClientThread` causes them continuously. steamos-manager traces every `split_lock_warn`, logs each one (`Forwarding line ... split_lock_warn`) and hands it to steamos-log-submitter, which queues one small report file per hit. Seen on one boot: 67,192 of the 68,418 journal lines, so the 50 MB journal had already rotated out the first 24 minutes of that boot and every earlier boot; 361,102 queued `split_lock` reports (1.3 GB, one inode each) in about 2 h 15 min, and the log submitter at 14 % of a CPU core. SteamOS already sets `kernel.split_lock_mitigate=0`, so the traps only produce these reports | Kernel parameter `split_lock_detect=off` via `/etc/default/grub.d/oxp3-splitlock.cfg` plus `update-grub`, so the CPU no longer traps split locks (like the Steam Deck, whose AMD APU does not trap split locks). Apply also deletes the queued `split_lock` reports, and only those. Reboot needed |
| **The performance overlay shows no CPU power** (0 W, journal: `Failed to initialize CPU power data`) | The overlay (mangoapp) runs as the desktop user and reads the CPU energy counter `/sys/class/powercap/intel-rapl:0/energy_uj`, which the kernel keeps root-only since the PLATYPUS power side channel ([CVE-2020-8694](https://nvd.nist.gov/vuln/detail/CVE-2020-8694)) | `oxp3-rapl-overlay.service`, a root service that keeps the real counter root-only and bind-mounts a coarse, world-readable copy over that one file: refreshed every 0.5 s, rounded to 10 mJ. That is plenty for a power reading and useless for the side channel, which needs thousands of fine-grained samples per second. All other RAPL counters stay root-only. No reboot needed (re-enter game mode so the overlay picks it up) |
| **The performance overlay shows no GPU power and no GPU temperature** | The xe driver creates hwmon sensors (power, temperature) only for discrete GPUs, so MangoHud finds nothing for the integrated Panther Lake GPU | A patched mangoapp ([`mangoapp/`](mangoapp/README.md), binary in the release archive, sha256 pinned) reads the GPU power from the RAPL PP1 (graphics) energy counter, published by the same service as a coarse copy, and shows the CPU package temperature as the GPU temperature. Both are estimates: PP1 covers the graphics power plane, not the GPU's share of memory and uncore power, and the GPU sits on the same die as the package sensor. It starts through a launcher that falls back to the stock mangoapp when the binary is missing, cannot load its libraries, does not match the installed mangohud package or crashes three times within a minute |
| **VRR caps the frame rate at about 70-80 fps** (SteamOS 20261015.1000 and later) | SteamOS switched to the upstream `linux-firmware` package, whose Panther Lake display firmware `i915/xe3lpd_dmc.bin` is v2.36. With it, VRR only ends a frame early when the flip arrives in time and otherwise waits for the 30 Hz limit, so about half the refresh rate is reached. Version 2.20, which SteamOS shipped before, works (verified by swapping only this file, see issue #1) | The script installs DMC v2.20 as `/usr/lib/firmware/updates/i915/xe3lpd_dmc.bin.zst`, which the kernel prefers over the packaged file (stock SteamOS loads Xe after the initramfs, so no rebuild is needed; [custom early-loading setups](xe/README.md#boot-integration-recovery-and-updates) must rebuild and verify their boot images). The file is Intel firmware, redistributed unmodified under [`firmware/LICENSE.i915`](firmware/LICENSE.i915). Nothing is installed when SteamOS ships v2.20 itself. Reboot needed |
| **No sound from the speakers after boot or resume** (nothing plugged into the headphone jack) | While the Realtek ALC245 codec powers up, its jack detection briefly reports headphones. PipeWire selects the `Headphones` card profile from that and misses the later unplug event, so the speaker amplifier stays switched off (ALSA `Headphone Jack` off, `Speaker Playback Switch` off) until WirePlumber is restarted | `oxp3-audio-route.service`, a user unit that checks a few times in the first 30 s of the session and again after every resume (started by the root unit `oxp3-audio-resume.service`). Only when the jack is empty but a Headphones profile is active does it select the matching Speaker profile, falling back to a WirePlumber restart. A plugged-in headset is never touched. No reboot needed |
| **No gyroscope** (experimental, opt-in with `--gyro`) | The IMU is a Bosch BMI260, but its ACPI node is named `10EC5280`, which only the `bmi160` driver claims, and that driver fails with `Error reading chip id` (-121); nothing is left for InputPlumber or Steam to read | An ACPI table override renames the node to `BMI0260` so `bmi270_i2c` binds (BIOS 5.09 only), and a patched InputPlumber 0.78.0 feeds the virtual Steam Deck controller with corrected axes and a drift-relaxing rate filter. Drift is reduced, not eliminated. Nothing is installed unless you opt in; `--no-gyro` removes it. Details, files and build instructions in [`gyro/`](gyro/README.md) |

### Installing and running the fix pack

Everything comes as one archive, `oxp3-fix.tar.gz`, from the latest release. On the deck:

```bash
cd ~ && curl -fL https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/latest/download/oxp3-fix.tar.gz | tar -xz
~/oxp3-fix/oxp3-apply-fixes.sh --check     # dry check, no sudo, changes nothing
~/oxp3-fix/oxp3-apply-fixes.sh             # apply: asks for the sudo password, confirms, says if a reboot is needed
~/oxp3-fix/oxp3-apply-fixes.sh --revert    # undo everything, then reboot
```

The archive extracts to `~/oxp3-fix` (the fix pack script, the patched InputPlumber used by the optional gyro step, the patched mangoapp for the GPU readings in the performance overlay, their source patches, and the desktop icons). Extracting a newer release over it updates it in place.

**Desktop icons (optional).** The archive contains two launchers for desktop mode, so the fix pack can be run by double-clicking instead of typing commands:

| File | Icon name | What it runs |
|---|---|---|
| `OXP3-Fix.desktop` | OXP3 Fix Pack | `~/oxp3-fix/oxp3-apply-fixes.sh` (apply; use it after every SteamOS update) |
| `OXP3-Revert.desktop` | OXP3 Revert Fix Pack | `~/oxp3-fix/oxp3-apply-fixes.sh --revert` (undo everything) |

Put them on the desktop:

```bash
cp ~/oxp3-fix/OXP3-*.desktop ~/Desktop/ && chmod +x ~/Desktop/OXP3-*.desktop
```

Each opens a Konsole window that stays open, so you can type the sudo password, answer the questions (including the optional gyro prompt) and read the result. On the first double-click KDE may ask whether to trust or execute the file; allow it. The launchers expect the pack in `~/oxp3-fix`, which is where the archive extracts to.

Flags: `--yes`, `--force`, `--force-nvme`, `--no-wifi`, `--gyro`, `--no-gyro`.

- SteamOS updates may make the root filesystem read-only again, reset `/etc` and remove installed packages. Re-run the script afterwards; it is idempotent. If the filesystem is read-only, the script runs `steamos-readonly disable` first.
- On SteamOS 20261015.1000 and later Wi-Fi and Bluetooth work out of the box. On an older build without working Wi-Fi, connect USB Ethernet or USB tethering before running the script, so the script can download `linux-firmware-intel`. The downloaded package is cached in `~/.cache/oxp3-fix`, which survives SteamOS updates, so every later run (for example after an update wiped the firmware again) works without any network. Without network and without the cache the step is skipped with a message and the other fixes still run. A reboot is needed afterwards so the driver loads the new firmware.
- Remove earlier hacks of your own first, such as boot-time `chvt` scripts or a masked `powerbuttond`, because they can interfere.
- Do not unbind or rebind hid-oxp, and do not write raw commands to the `1a86:fe00` hidraw device.
- After enabling InputPlumber mid-session, the controller page in Steam may need `sudo systemctl restart inputplumber` or a Steam restart before it shows the controller.
- **Gyroscope is opt-in.** In an interactive run the script asks once whether to enable it (`--gyro` enables without asking, `--no-gyro` removes it and stops asking). It installs an ACPI override (reboot needed the first time) and uses the patched InputPlumber from the release archive, checking a pinned sha256. It only applies on BIOS 5.09 with stock InputPlumber 0.78.x, otherwise it says why and skips. The choice is remembered, so re-running after a SteamOS update restores it. The patched build is started through a launcher that falls back to the stock binary if it cannot run, so a bad update cannot take the gamepad with it. See [`gyro/README.md`](gyro/README.md) for tuning (`/etc/inputplumber/oxp3-gyro-steer.conf`) and how to build the binary yourself.
- The volume key fix grabs the i8042 keyboard exclusively and forwards every key, including power, through a virtual device. Keep that in mind if you attach an external PS/2 keyboard.
- Everything is written under `/etc` and `/home`, and `--revert` undoes it.

### Lighting

The fix pack does not touch lighting.

- **Kernel 7.2.7 and later (SteamOS 20261013.1000 and later):** the hid-oxp driver supports the ONEXPLAYER 3 lights natively. It registers three LEDs, `oxp:rgb:joystick_rings`, `oxp:rgb:guide_button` (the Xbox button) and `oxp:rgb:rear_logo` (the slogan light), each with `brightness` and an RGB `multi_intensity`; the rings also have effects (`effect`, `speed`, `enabled`). The driver restores the lights after suspend.
- **Older kernels:** the hid-oxp LED interface has no effect on this controller.

For a lighting UI use the [modified fork of HueSync](https://github.com/HHHHanasak1/HueSync/tree/oxp3), a Decky plugin with three independently controlled zones. On kernel 7.2.7 and later it drives the native LEDs above, on older kernels it falls back to writing the controller directly. Its README explains how to install it. It is independent of the fix pack, so the two can be installed in either order.

### Known issues and limitations

As of 2026-09-24 the stable fixes have been in daily use for about half a month, including across the 20260921.1000 SteamOS update (re-run the script after an update). Later kernel-specific issues and the experimental gyroscope limitations are listed below.

- **Gyroscope (experimental, opt-in): usable, but drift is only reduced.** The BMI260's temperature-dependent bias about the vertical axis cannot be corrected with gravity, so flat-steering use would drift by several degrees per minute. The patched InputPlumber makes Steam's integrated angle relax towards the centre with a 20 s time constant, so a constant bias ends up as a bounded offset of about 1-2 degrees instead of a runaway, at the cost of a slow return when you hold a turn for a long time. Static compensation and automatic calibration on their own were tried without a usable result. Optional response shaping (`curve`, `gain`) exists but is off by default. See [`gyro/README.md`](gyro/README.md) and `issues/03-bmi160.md`.
- **High TDP needs a strong charger.** Whenever the charger reports disconnected, the firmware resets the TDP to its battery limits (35 W / 52 W) and a TDP plugin puts its own value back a little later. With a charger that cannot cover the SoC, the screen and charging at the same time, the adapter flaps between connected and disconnected (seen: 13 times in 4 minutes at a 50 W TDP, the battery still discharging at about 34 W while plugged in), so the limit bounces between 35 and 50 W. For TDPs around 50 W use a charger that covers all of it; a 100 W USB PD charger is recommended.
- **Volume key root cause** is in the embedded controller firmware. A firmware update from the vendor would remove the need for the forwarder.
- **Split-lock detection is off.** With `split_lock_detect=off` the kernel no longer reports a program that uses split locks (a bus lock that briefly stalls memory access for every core). That only matters for spotting such programs; SteamOS was not slowing them down anyway (`kernel.split_lock_mitigate=0`). `--revert` turns detection back on after a reboot.
- **CPU power in the overlay comes from a coarse copy** of the energy counter (step 10), updated every 0.5 s with 10 mJ steps, so short spikes are smoothed. The raw counter stays root-only. GPU power is the RAPL PP1 (graphics plane) reading and the GPU temperature is the CPU package temperature, because the integrated GPU has no sensors of its own; both come from the patched mangoapp, which only runs with the mangohud package it was built for (otherwise the stock overlay runs, without these two values).
- **HDR uses the gamma-2.2 path.** A true PQ path (`xe.enable_dpcd_backlight=1`) has not been tested.
- **Xe buffer cleanup can hang on specific Valve kernels.** A reservation-lock mismatch is confirmed in the examined `7.2.4-valve1` and `7.2.7-valve2` builds. See [`xe/`](xe/README.md) for evidence, a minimal source patch, verification and manual rebuild/recovery notes. The fix pack does not install this kernel patch.
- **Lighting is not part of this pack**, see the Lighting section above (native on kernel 7.2.7 and later). Never unbind or rebind hid-oxp: it triggers a kernel Oops (`issues/hid_oxp_oops_rebind.txt`).

Upstream bug drafts are in `issues/`.

### Tested configuration

SteamOS 3.10 main 20260827.1000, kernel 7.2.0-valve1-1-neptune-72 (paddles, Wi-Fi/Bluetooth firmware, battery clamp and gyro verified on 7.2.4-valve1 / SteamOS 20260921.1000; all fixes re-verified on 7.2.7-valve2 / SteamOS 20261013.1000), OXP3 BIOS 5.09, panel SDC AMS881KB01-0, SSD Predator GM7 1TB. The script refuses to run on other DMI or OS values (`--force` overrides) and only applies `nvme.noacpi=1` when a GM7 / `1dee:1602` SSD is present (`--force-nvme` overrides). The gyro step additionally requires BIOS 5.09 and InputPlumber 0.78.x (`--force` overrides).

### How it was found

Suspend/resume failures were reproduced 7 out of 7 times with `rtcwake`-timed suspends in game mode, while KDE desktop mode resumed fine. Resume-time kernel logs captured with `dmesg -w` onto an SD card exposed the NVMe reset failure, and `nvme.noacpi=1` fixed it in 2 of 2 tests with S0ix reached. The boot black screen was traced to gamescope HDR, the volume keys to the controller dropping key releases with `evtest`, and the chassis keys with hidraw and UHID report captures plus InputPlumber debug logs.

### Changelog

Releases are named by date (`YYYYMMDD`) from 20261014 on; earlier ones used version numbers.

- **20261016**: speaker route check (step 12) for silent speakers after boot or resume. Display firmware DMC v2.20 (step 11) for SteamOS 20261015.1000, which ships v2.36 and with it the VRR cap from issue #1. GPU power and temperature in the overlay (step 10, patched mangoapp). CPU power in the performance overlay (step 10): a root service publishes a coarse copy of the package energy counter, replacing the opt-in udev rule from 20261015, which made the raw counter world-readable. The battery clamp and the new service detach their sysfs overlays lazily, because a reader holding the file open made the unmount fail and restarts stacked the mounts.
- **20261015**: split-lock flood (step 9, contributed in PR #16). Steam's split locks were reported tens of times a second through steamos-manager, pushing everything else out of the journal and queueing hundreds of thousands of report files for steamos-log-submitter; `split_lock_detect=off` stops the traps, and apply clears the queued split-lock reports. Also: README notes on the CPU power reading in the performance overlay (PR #17) and on the gyro override with BIOS 5.12 (PR #18).
- **20261014**: support for the hid-oxp driver in kernel 7.2.7 (SteamOS 20261013.1000), which adds native ONEXPLAYER 3 lighting and maps the back paddles to F15/F16 by default. The paddle check accepts any two different F13-F24 keys and no longer overrides the driver default. README: lighting section updated.
- **v1.6.1 (2026-09-25)**: the Wi-Fi/Bluetooth step uses the cached firmware package when there is no network, so Wi-Fi comes back after a SteamOS update without USB tethering.
- **v1.6.0 (2026-09-25)**: TDP sync (step 8). The GPU obeys the MSR package PL1, which the firmware leaves at 25 W while TDP tools only set the MMIO PL1, so the GPU was throttled even with a 50 W TDP; a small root service now keeps the MSR PL1 equal to the MMIO PL1. README note on chargers for high TDPs.
- **v1.5.1 (2026-09-25)**: the release is a single archive, `oxp3-fix.tar.gz`, that extracts to `~/oxp3-fix`; the gyro step uses the patched InputPlumber from it.
- **v1.5.0 (2026-09-24)**: experimental, opt-in gyroscope support (step 7, `--gyro` / `--no-gyro`): ACPI override so the kernel sees the BMI260, patched InputPlumber 0.78.0 (source and build notes in `gyro/`, binary in the release, sha256 pinned, automatic fallback to the stock binary), and a drift-relaxing rate filter. The script is now distributed as a release asset, so cloning the repository is not needed. `--help` now prints the complete usage text.
- **v1.4.0 (2026-09-22)**: battery percentage clamp (step 6). The gauge over-reports right after a full charge and Steam showed 101-104 %; a small root service overlays corrected `capacity` / `energy_full` sysfs values, refreshed once a minute.
- **v1.3.1 (2026-09-22)**: the Wi-Fi/Bluetooth step really installs the BE201 firmware: SteamOS' own `linux-firmware-neptune` satisfies the package check but lacks the files, so the step now looks at the driver state and extracts only the missing families from `linux-firmware-intel`.
- **v1.3.0 (2026-09-20)**: step 0, Wi-Fi firmware on a fresh install (`--no-wifi` skips it).
- **v1.2.0 (2026-09-12)**: back paddles work through the hid-oxp driver, and the left/right swap inherited from the OneXPlayer 8 map is removed. `--check` and apply report and re-assert the paddle driver state through sysfs.
- **v1.1.0 (2026-09-10)**: the gamescope HDR lua ships the missing 30-144 Hz `dynamic_modegen`. v1.0.1 only declared `dynamic_refresh_rates = {60, 144}` without the matching mode-generation function, so gamescope could never produce those modes. The timing formula comes from the two real hardware modes (60 Hz and 144 Hz from `modetest -c`) and covers the whole range.
- **v1.0 (2026-09-06)**: initial release.
