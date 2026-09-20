# SteamOS on the ONEXPLAYER 3 (Intel Panther Lake): install guide and fix pack

This repository covers everything needed to run SteamOS on the ONEXPLAYER 3, from a blank drive to a working machine:

1. **Part 1** is a step-by-step guide to installing SteamOS with the recovery image.
2. **Part 2** is a fix pack, one script that repairs what does not work out of the box: Wi-Fi, suspend/resume, the HDR panel and refresh rates, volume keys, the chassis keys and back paddles.

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
| **No Wi-Fi** (Intel CNVi Wi-Fi, `iwlwifi`) | The firmware files the driver needs for the chip are not installed, and the system is not ready to install them | `pacman -Sy linux-firmware` It needs another network connection for the download, for example USB Ethernet or USB tethering. It is skipped when `linux-firmware` is already installed, and `--no-wifi` skips it explicitly |
| **Game-mode suspend/resume freeze** | The Predator GM7 NVMe (Biwin/Maxio `1dee:1602`) fails to come back from s2idle through the ACPI StorageD3 path (`nvme nvme0: Disabling device after reset failure: -19`), and the root filesystem goes away | Kernel parameter `nvme.noacpi=1` via `/etc/default/grub.d/oxp3-nvme.cfg` plus `update-grub`. Applied only when that SSD is present. Deep S0ix is still reached |
| **Panel stays black in game mode** after boot, session switch or resume; brightness slider does nothing | gamescope enables HDR and xe drives the Samsung AMS881KB01-0 OLED with BT.2020/PQ 10 bpc. The panel implements Intel's eDP HDR interface but the driver never enables its backlight channel, so the output is treated as SDR | A gamescope known-display lua keeps the panel in native gamma-2.2 mode and lets gamescope tone-map internally, the same approach as the Steam Deck OLED. HDR works and the brightness slider starts working |
| **Performance panel sometimes offers only one refresh rate** | The panel has genuine continuous 30-144 Hz VRR, but the lua only declared `dynamic_refresh_rates` without the matching `dynamic_modegen` function, so gamescope never generated any real modes | The same lua now registers the full 30-144 Hz range. The timing formula is derived from, and verified against, the 60 Hz and 144 Hz modes reported by the driver |
| Per-frame `xe ... DSB 0 poll error` kernel message flood | The xe display state buffer fails on this panel | `options xe enable_dsb=0` in `/etc/modprobe.d/xe-oxp3.conf`. Cosmetic, only silences the messages |
| **Volume keys stick** when pressed quickly | The embedded controller drops the key-release scancodes on the i8042 keyboard, so the kernel sees the key held down | `oxp3-volkey-fix.service`, a boot-time evdev forwarder that grabs the raw device and re-emits each volume key as a press plus release on a virtual keyboard without autorepeat |
| **Home, Console and Keyboard keys do nothing** | These keys are reported through the MCU keyboard and vendor interfaces | An InputPlumber composite device plus capability map: Home to Steam menu, Console to Quick Access, Keyboard to the on-screen keyboard |
| **Back paddles M1 and M2 do not work** | They need the hid-oxp driver to map them and switch the MCU report mode | hid-oxp maps M1 and M2 to `KEY_F16` and `KEY_F17` and cycles the report mode at boot. The MCU then emits vendor frames that InputPlumber decodes as the left and right paddle. On the OXP3 the physical left paddle is `0x22`, so the left/right swap inherited from the OneXPlayer 8 map was removed. The script only re-asserts the driver state through sysfs |

### Installing and running the fix pack

```bash
mkdir -p ~/oxp3-fix && cp oxp3-apply-fixes.sh oxp3-volkey-fix.py ~/oxp3-fix/ && chmod +x ~/oxp3-fix/oxp3-apply-fixes.sh
cp OXP3-*.desktop ~/Desktop/ && chmod +x ~/Desktop/OXP3-*.desktop   # optional desktop icons
~/oxp3-fix/oxp3-apply-fixes.sh --check     # dry check, no sudo, changes nothing
~/oxp3-fix/oxp3-apply-fixes.sh             # apply: asks for the sudo password, confirms, says if a reboot is needed
~/oxp3-fix/oxp3-apply-fixes.sh --revert    # undo everything, then reboot
```

Flags: `--yes`, `--force`, `--force-nvme`, `--no-wifi`.

- SteamOS updates may make the root filesystem read-only again, reset `/etc` and remove installed packages. Re-run the script afterwards; it is idempotent. If the filesystem is read-only, the script runs `steamos-readonly disable` first.
- On a machine without working Wi-Fi, connect USB Ethernet or USB tethering before running the script, so the script can download `linux-firmware`. Without any network the step is skipped with a message and the other fixes still run. A reboot is needed afterwards so the driver loads the new firmware.
- Remove earlier hacks of your own first, such as boot-time `chvt` scripts or a masked `powerbuttond`, because they can interfere.
- Do not unbind or rebind hid-oxp, and do not write raw commands to the `1a86:fe00` hidraw device.
- After enabling InputPlumber mid-session, the controller page in Steam may need `sudo systemctl restart inputplumber` or a Steam restart before it shows the controller.
- The volume key fix grabs the i8042 keyboard exclusively and forwards every key, including power, through a virtual device. Keep that in mind if you attach an external PS/2 keyboard.
- Everything is written under `/etc` and `/home`, and `--revert` undoes it.

### Lighting

The fix pack does not touch lighting: the kernel hid-oxp LED interface has no effect on the ONEXPLAYER 3 controller. For lighting control use the [modified fork of HueSync](https://github.com/PPPPatrick0/HueSync/tree/oxp3), a Decky plugin that adds three independently controlled zones: the joystick rings, the Xbox button light and the slogan light. Its README explains how to install it. It is independent of the fix pack, so the two can be installed in either order.

### Known issues and limitations

As of 2026-09-20 these fixes have been in daily use for about half a month. Only two things are known not to work, the gyroscope and XeSS multi frame generation, and no other stability problems have been seen apart from the rare speaker case below.

- **Gyroscope: recognized, but severe drift.** The sensor is a Bosch BMI260 that the kernel does not identify on its own. An ACPI table override makes it probe and deliver data, and with corrected units, axis order and mount matrix the direction is right. Flat-steering use still drifts by several degrees per minute, because the temperature-dependent bias about the vertical axis cannot be corrected with gravity. Static compensation, automatic calibration and no compensation were all tried without a usable result. This pack does not enable the gyroscope. See `issues/03-bmi160.md`.
- **XeSS multi frame generation does not work.** 2x frame generation works, 3x and 4x never engage. As far as we know, XeSS on Linux currently cannot use the XMX units of the GPU and falls back to the DP4a path. Nothing in this pack changes that.
- **Volume key root cause** is in the embedded controller firmware. A firmware update from the vendor would remove the need for the forwarder.
- **HDR uses the gamma-2.2 path.** A true PQ path (`xe.enable_dpcd_backlight=1`) has not been tested.
- **Speakers are very occasionally silent after boot.** A reboot fixes it. Not investigated yet.
- **Lighting is not part of this pack**, see the Lighting section above. Never unbind or rebind hid-oxp: it triggers a kernel Oops (`issues/hid_oxp_oops_rebind.txt`).

Upstream bug drafts are in `issues/`.

### Tested configuration

SteamOS 3.10 main 20260827.1000, kernel 7.2.0-valve1-1-neptune-72 (paddles verified on 7.2.4-valve1), OXP3 BIOS 5.09, panel SDC AMS881KB01-0, SSD Predator GM7 1TB. The script refuses to run on other DMI or OS values (`--force` overrides) and only applies `nvme.noacpi=1` when a GM7 / `1dee:1602` SSD is present (`--force-nvme` overrides).

### How it was found

Suspend/resume failures were reproduced 7 out of 7 times with `rtcwake`-timed suspends in game mode, while KDE desktop mode resumed fine. Resume-time kernel logs captured with `dmesg -w` onto an SD card exposed the NVMe reset failure, and `nvme.noacpi=1` fixed it in 2 of 2 tests with S0ix reached. The boot black screen was traced to gamescope HDR, the volume keys to the controller dropping key releases with `evtest`, and the chassis keys with hidraw and UHID report captures plus InputPlumber debug logs.

### Changelog

- **v1.2.0 (2026-09-12)**: back paddles work through the hid-oxp driver, and the left/right swap inherited from the OneXPlayer 8 map is removed. `--check` and apply report and re-assert the paddle driver state through sysfs.
- **v1.1.0 (2026-09-10)**: the gamescope HDR lua ships the missing 30-144 Hz `dynamic_modegen`. v1.0.1 only declared `dynamic_refresh_rates = {60, 144}` without the matching mode-generation function, so gamescope could never produce those modes. The timing formula comes from the two real hardware modes (60 Hz and 144 Hz from `modetest -c`) and covers the whole range.
- **v1.0 (2026-09-06)**: initial release.
