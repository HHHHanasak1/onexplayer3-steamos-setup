# SteamOS on the ONEXPLAYER 3 (Intel Panther Lake): install guide and fix pack

This repository covers everything needed to run SteamOS on the ONEXPLAYER 3:

1. **Part 1** is a step-by-step guide to installing SteamOS with the recovery image.
2. **Part 2** is a fix pack, one script that repairs what does not work out of the box: suspend/resume, the OLED panel (black screen, HDR, refresh rates, VRR), volume keys, the chassis keys and back paddles (also on the controller connector dock), the speakers after boot, the battery percentage, the GPU power limit, the readings in the performance overlay, a split-lock report flood and big games crashing after sleep. Optional: the gyroscope (experimental) and a TDP plugin with a CPU boost mode for this chip.

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

   **Installing to the second SSD (Mini SSD) instead.** `repair_device.sh` always installs to the disk named in its `DISK=` line near the top (`nvme0n1`) and erases it. To install to the other SSD, run `lsblk -o NAME,SIZE,MODEL` first and note the name of the target disk, then before `sudo ./repair_device.sh all` change that line, for example `sed -i 's|nvme0n1|nvme1n1|g' ./repair_device.sh`, and check it with `grep -n nvme ./repair_device.sh`. The disk numbering can differ between boots and machines, so go by size and model, not by the number. (Tip from issue #13.)

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
| **No Wi-Fi / no Bluetooth** (Intel BE201, only SteamOS before 20261015.1000) | SteamOS' `linux-firmware-neptune` lacked the BE201 firmware files | Step 0 extracts only the missing files from the repo's `linux-firmware-intel` (cached in `~/.cache/oxp3-fix`, so later runs work offline). Newer SteamOS ships them, and the step skips itself |
| **Game-mode suspend/resume freeze** | The Predator GM7 NVMe (`1dee:1602`) does not come back from s2idle through the ACPI StorageD3 path (`Disabling device after reset failure: -19`) | Kernel parameter `nvme.noacpi=1`, only when that SSD is present. Deep S0ix is still reached |
| **Big games crash with "out of memory" right after waking from sleep** (FF7 Rebirth, about 2 s after resume, with 11-16 GB free) | On suspend xe moves every GPU buffer out. On resume it rebinds every mapping in one array of 384 bytes per mapping. FF7R has about 33,500 mappings which means 12.9 MB. That's over the 4 MB kmalloc limit which means it fails every time (63 of 63 in a trace) and Mesa reports `execbuf ioctl keeps returning ENOMEM` | `oxp3-xevmafix.service` loads a small module ([`xevmafix/`](xevmafix/README.md)) that lets that one array come from vmalloc, the same change Intel already made in drm-xe-next. Built for one kernel only and skipped on any other |
| **Panel stays black in game mode**, brightness slider does nothing | gamescope drives the OLED (Samsung AMS881KB01-0) in BT.2020/PQ, but xe never enables the panel's HDR backlight channel | A gamescope lua keeps the panel in its native gamma-2.2 mode and lets gamescope tone-map, like the Steam Deck OLED. It also registers the real 30-144 Hz VRR range, and with `content_driven = true` SDR games keep the panel in SDR and scan out directly (RE4 at 30 W: 87 → 93 fps); the panel switches to HDR only while an HDR game presents |
| **Game mode freezes, then goes black** (BIOS 5.11 and later; audio and controls keep working) | Panel Replay with selective update fails on this panel (`Selective fetch area calculation failed`), PSR1 freezes it later, and with PSR off LOBF keeps it black. No module parameter turns LOBF off | `oxp3-panel-fix.service` turns LOBF and PSR/Panel Replay off through xe debugfs before the display manager starts. Only on this panel with BIOS 5.11+ (`--force-panel` overrides). Reboot needed |
| **VRR caps the frame rate at about 70-80 fps** (SteamOS 20261015.1000 and later) | Upstream display firmware DMC v2.36 (`i915/xe3lpd_dmc.bin`); v2.20 works (issue #1) | DMC v2.20 in `/usr/lib/firmware/updates`, which the kernel prefers. Intel firmware, redistributed unmodified ([`firmware/LICENSE.i915`](firmware/LICENSE.i915)). Reboot needed |
| `xe ... DSB 0 poll error` message flood | The xe display state buffer fails on this panel | `options xe enable_dsb=0`. Cosmetic |
| **Volume keys stick** when pressed quickly | The embedded controller drops key-release scancodes | `oxp3-volkey-fix.service` re-emits each volume key as press plus release on a virtual keyboard |
| **Home, Console and Keyboard keys do nothing** | Reported through the MCU keyboard and vendor interfaces | InputPlumber composite device: Home → Steam menu, Console → Quick Access, Keyboard → on-screen keyboard |
| **Home and G-key do nothing with the controllers on the connector dock** (issue #23) | The [controller connector](https://onexplayerstore.com/collections/accessories/products/controller-connector-for-onexplayer-x1) has its own chip (`1a86:fe02`) that sends these keys; stock InputPlumber 0.78 only reads the handheld's `fe00` and drops the G-key code | The patched InputPlumber, now installed for everyone (gyro stays opt-in), also reads `fe02` and maps the G-key to the Steam menu; the stock binary starts instead if the patched one cannot run |
| **Back paddles M1 and M2 do not work** | They need hid-oxp to map them and switch the MCU report mode | hid-oxp maps them to two F13-F24 keys (F15/F16 on kernel 7.2.7) and InputPlumber turns them into the left and right paddle. The script only re-asserts the driver state through sysfs |
| **No sound from the speakers after boot or resume** | The ALC245 jack detection briefly reports headphones; PipeWire keeps the Headphones profile with the speaker amp off | `oxp3-audio-route.service` selects the Speaker profile, only when the jack is empty but a Headphones profile is active |
| **Battery shows 101-104 %** after a full charge | The gauge reports `energy_now` above `energy_full`, and Steam reads the raw sysfs value | `oxp3-battery-clamp.service` overlays corrected `capacity` / `energy_full` values |
| **GPU stays throttled below the TDP you set** | TDP tools write the MMIO package PL1, but the GPU obeys the MSR PL1, which keeps the firmware's 25 W | `oxp3-tdp-sync.service` copies the MMIO PL1 into the MSR PL1 (checked every 2 s) |
| **Journal holds only the last hour, `/var/lib/steamos-log-submitter` grows by hundreds of MB an hour** | Panther Lake traps user-space split locks and Steam causes them continuously; every hit is logged and queued as a report | Kernel parameter `split_lock_detect=off` (like the Steam Deck); apply also deletes the queued split-lock reports. Reboot needed |
| **Performance overlay: no CPU power, no GPU power or temperature** | The RAPL energy counters are root-only (CVE-2020-8694), and xe has no hwmon sensors for an integrated GPU | `oxp3-rapl-overlay.service` publishes coarse world-readable copies (0.5 s, 10 mJ) of the package, CPU core and GPU counters, and a patched mangoapp ([`mangoapp/`](mangoapp/README.md)) shows CPU power (cores), GPU power (RAPL PP1), GPU temperature (= package temperature) and a SoC total on levels 2-4. It falls back to the stock mangoapp when it cannot run |
| **CPU boost is all or nothing** in SimpleDeckyTDP (optional, step 14) | With boost off the cores stop at their base clock; with boost on the E- and LP E-cores also clock up and take power the GPU could use | Installs [SimpleDeckyTDP-Intel](https://github.com/kas5852/SimpleDeckyTDP-Intel) by kas5852 (PR #24), whose CPU Boost is **Off / Smart / Full** per game. Smart caps P / E / LP E-cores at 3.0 / 2.0 / 1.5 GHz: RE4 at 30 W +12 % average fps, +48 % 1% low. See below |
| **No gyroscope** (experimental, opt-in with `--gyro`) | The BMI260's ACPI node is named for the `bmi160` driver, which fails on it | ACPI override (BIOS 5.09); the patched InputPlumber above handles the sensor. Drift is reduced, not eliminated. Details in [`gyro/`](gyro/README.md) |

### Installing and running the fix pack

Everything comes as one archive, `oxp3-fix.tar.gz`, from the latest release. On the deck:

```bash
cd ~ && curl -fL https://github.com/HHHHanasak1/onexplayer3-steamos-setup/releases/latest/download/oxp3-fix.tar.gz | tar -xz
~/oxp3-fix/oxp3-apply-fixes.sh --check     # dry check, no sudo, changes nothing
~/oxp3-fix/oxp3-apply-fixes.sh             # apply: asks for the sudo password, confirms, says if a reboot is needed
~/oxp3-fix/oxp3-apply-fixes.sh --revert    # undo everything, then reboot
```

The archive extracts to `~/oxp3-fix`: the script, the desktop icons, and the binaries some steps use (patched InputPlumber, patched mangoapp, the SimpleDeckyTDP-Intel zip, the xevmafix kernel module) with their source patches. Extracting a newer release over it updates it in place.

**Desktop icons (optional).** For desktop mode, `OXP3-Fix.desktop` runs the fix pack and `OXP3-Revert.desktop` reverts it, each in a Konsole window where you type the sudo password and answer the questions:

```bash
cp ~/oxp3-fix/OXP3-*.desktop ~/Desktop/ && chmod +x ~/Desktop/OXP3-*.desktop
```

Flags: `--yes`, `--force`, `--force-nvme`, `--force-panel`, `--no-wifi`, `--gyro`, `--no-gyro`, `--sdtdp`, `--no-sdtdp`. `--help` prints the full usage.

- **Re-run the script after every SteamOS update.** Updates reset parts of `/etc` and `/usr`; the script is idempotent and runs `steamos-readonly disable` when needed.
- **Optional steps.** An interactive run asks once about the gyroscope and about SimpleDeckyTDP-Intel; the answers are remembered, and `--gyro` / `--no-gyro` / `--sdtdp` / `--no-sdtdp` change them. Binaries come from the release archive with a pinned sha256 and fall back to the stock version if they cannot run.
- **SimpleDeckyTDP-Intel** (needs Decky Loader):
  - The zip is part of the release archive, unmodified from [kas5852's release](https://github.com/kas5852/SimpleDeckyTDP-Intel/releases) (BSD 3-Clause, license inside the zip). It is a community fork, not affiliated with SimpleDeckyTDP.
  - If the original SimpleDeckyTDP is installed, the question says that installing replaces it, and the original is removed only after a yes. Its profiles are copied on the first start, and its settings file stays, so reinstalling it from the Decky store brings them back.
  - Once installed, the plugin updates itself from the fork's releases (System Info page), not through this repo.
  - Smart needs "Enable Manual CPU Controls" in the plugin's advanced options. It sets the TDP like SimpleDeckyTDP, so the TDP sync works as before.
- **On an older SteamOS build without Wi-Fi**, connect USB Ethernet or USB tethering before the first run so step 0 can download the firmware package.
- Remove earlier hacks of your own first, such as boot-time `chvt` scripts or a masked `powerbuttond`.
- Never unbind or rebind hid-oxp (kernel Oops, `issues/hid_oxp_oops_rebind.txt`), and do not write raw commands to the `1a86:fe00` or `1a86:fe02` hidraw devices.
- The volume key fix grabs the i8042 keyboard and forwards every key, including power, through a virtual device; keep that in mind with an external PS/2 keyboard.
- Files go to `/etc`, `/home`, `/usr/lib/firmware`, `~/homebrew/plugins` and, with the gyro, `/boot`. `--revert` removes them all except the Wi-Fi firmware.

### Lighting

The fix pack does not touch lighting. From kernel 7.2.7 (SteamOS 20261013.1000) hid-oxp drives the three light zones natively (`oxp:rgb:joystick_rings`, `oxp:rgb:guide_button`, `oxp:rgb:rear_logo`). For a UI use the [modified fork of HueSync](https://github.com/HHHHanasak1/HueSync/tree/oxp3), a Decky plugin with three independent zones.

### Known issues and limitations

- **Gyroscope: drift is only reduced.** The BMI260's temperature-dependent yaw bias cannot be corrected with gravity. The patched InputPlumber lets the angle relax towards the centre (20 s time constant), so a constant bias becomes an offset of about 1-2 degrees. See [`gyro/README.md`](gyro/README.md).
- **High TDP needs a strong charger.** When the charger reports disconnected, the firmware resets the TDP to its battery limits and the TDP plugin puts its value back a little later. A charger that cannot cover the SoC, screen and charging flaps on and off, so the limit bounces. For TDPs around 50 W use a 100 W USB PD charger.
- **Overlay power values are estimates.** CPU is the cores (RAPL PP0), GPU the graphics plane (PP1), and the TDP limits the whole package, which also covers the memory controller and display (a few watts), so CPU + GPU stays a little below the TDP; the SoC item shows the package total. The GPU temperature is the package temperature. Short spikes are smoothed by the 0.5 s copies.
- **Smart CPU caps stay until a reboot** after SimpleDeckyTDP-Intel is removed.
- **The panel fix (BIOS 5.11+) turns off panel self-refresh,** so static screens draw somewhat more power (not measured). It uses xe debugfs files, which a future kernel may rename; the service then leaves the panel alone and says so in `journalctl -u oxp3-panel-fix`. Driver reports: [xe#8924](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8924), [xe#9517](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/9517), [xe#8557](https://gitlab.freedesktop.org/drm/xe/kernel/-/issues/8557), [Bazzite #5975](https://github.com/ublue-os/bazzite/issues/5975).
- **Split-lock detection is off,** so the kernel no longer reports programs that use split locks. SteamOS did not slow them down anyway (`kernel.split_lock_mitigate=0`).
- **The sleep fix (xevmafix) only loads on the kernel it was built for** (`7.2.7-valve2-1-neptune-72`). After a SteamOS update with a new kernel it's skipped until a rebuilt module ships and big games can crash after sleep again. The real fix is in the kernel: [patch sent to intel-xe](xevmafix/README.md#upstream), [SteamOS #2962](https://github.com/ValveSoftware/SteamOS/issues/2962).
- **HDR uses the gamma-2.2 path.** A true PQ path (`xe.enable_dpcd_backlight=1`) has not been tested.
- **The volume key problem is in the embedded controller firmware;** a firmware update from the vendor would make the forwarder unnecessary.

Upstream bug drafts are in `issues/`.

### Tested configuration

SteamOS main 20261021.1000, kernel 7.2.7-valve2, OXP3 BIOS 5.09, panel SDC AMS881KB01-0, SSD Predator GM7 1TB. The panel fix was found and verified on BIOS 5.12. The script refuses to run on other DMI or OS values (`--force` overrides) and applies `nvme.noacpi=1` only with a GM7 / `1dee:1602` SSD (`--force-nvme` overrides). The patched InputPlumber needs the stock InputPlumber to be 0.78.x; the gyro step also needs BIOS 5.09.

### Changelog

Releases are named by date (`YYYYMMDD`) from 20261014 on.

- **20261023**: the patched InputPlumber is installed for everyone (gyro stays opt-in) and also reads the controller connector, so Home and the G-key work with the controllers on the dock (issue #23).
- **20261022**: big games no longer crash with "out of memory" after waking from sleep (step 15, xevmafix, contributed by kas5852 in PR #26). Overlay: when the kernel skips the GPU energy zone at boot, step 10 now brings it back, so GPU power and the SoC total no longer go missing.
- **20261018-2**: optional SimpleDeckyTDP-Intel (step 14, contributed by kas5852 in PR #24) with an Off / Smart / Full CPU boost. A normal run asks once; the zip comes with the release archive; an installed SimpleDeckyTDP is replaced only after you confirm.
- **20261018**: panel fix for BIOS 5.11 and later (step 13, PR #15). Content-driven HDR (PR #22). Overlay: CPU power is the cores only, new SoC total on levels 2-4, no empty VRAM item.
- **20261016**: speaker route check (step 12), DMC v2.20 for the VRR cap (step 11), CPU and GPU power/temperature in the overlay (step 10).
- **20261015**: split-lock flood (step 9, PR #16); README notes from PR #17 and #18.
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
