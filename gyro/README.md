# Experimental gyroscope support

Opt-in step 7 of the fix pack (`./oxp3-apply-fixes.sh --gyro`). This directory holds the sources behind it.

Since release 20261023 the patched InputPlumber is installed for everyone as part of step 5, because it also adds the controller connector (`1a86:fe02`, issue #23). The gyro step itself is the ACPI override and the IMU settings; without it the patched build simply sees no sensor.

**Status: experimental.** The gyro works and Steam's gyro layouts (gyro to joystick, camera, flick stick) accept it, but the sensor has a temperature-dependent bias about the vertical axis that gravity cannot correct, so drift is *reduced*, not eliminated. The gyro is not enabled unless you ask for it, and `--no-gyro` removes it again.

## Why the gyro needs three things

1. **The kernel cannot see the sensor.** The IMU is a Bosch BMI260 on I2C bus 2 (address 0x68), but the firmware names its ACPI node `10EC5280`. That id belongs to the `bmi160_i2c` driver, which fails with `Error reading chip id` (-121). `bmi270_i2c` supports the BMI260 but only matches the ids `BMI0160` and `BMI0260`. An **ACPI table override** ships a copy of the firmware's `SSDT26` (`Rtd3` / `I2C_DEVT`) with the node renamed to `BMI0260`, and the kernel then exposes a normal IIO device. The table is specific to **BIOS 5.09**, so the script refuses to install it on other versions (`--force` overrides). Source: [`SSDT26-oxp3-imu.dsl`](SSDT26-oxp3-imu.dsl); the compiled table is embedded in `oxp3-apply-fixes.sh` as an `acpi_override.img` cpio image loaded through `GRUB_EARLY_INITRD_LINUX_CUSTOM`.
2. **InputPlumber needs to understand the sensor.** A [patched InputPlumber 0.78.0](inputplumber-0.78.0-oxp3-gyro.patch) adds a mount matrix and bias options to the IIO source, orders the gyro fields the way Steam's Steam Deck HID driver reads them, and feeds them to the virtual Steam Deck controller (`deck-uhid`) at Steam's fixed 4 ms report interval. The same patch also lets the OneXPlayer HID driver read the controller connector (`1a86:fe02`) and its G-key (`0x25`), which is not gyro related but is why everyone runs this build now. The yaml entry for the IMU gets the matching keys (the fix pack writes them only when gyro is enabled).
3. **Drift handling.** The new `gyro_steer` module passes the yaw rate through a slow high-pass: it mirrors the angle Steam integrates and folds a small return rate into the stream, so a constant bias becomes a small bounded offset instead of a runaway drift. Optional response shaping (`curve`, `gain`, `range`, off by default) can give small tilts more reach than large ones. It also learns the bias while the device rests (`bias_auto=1`, on by default), and can map the angle to the left stick instead (`mode=stick`).

### BIOS 5.12

On BIOS 5.12 (09/07/2026, EC 0.13) the firmware's `SSDT26` is the same table as on 5.09: same length (0x517C) and OEM revision (0x1000), and its decompiled source differs from [`SSDT26-oxp3-imu.dsl`](SSDT26-oxp3-imu.dsl) only by the override's own edits (OEM revision 0x1001, the `BMI0260` ids and the mount-matrix `_DSD`). At boot `bmi160_i2c` now reads the chip id and reports `Chip id not found: 27`, which is 0x27, the BMI260's id; on 5.09 the read itself failed with -121. So the 5.09 override probably fits 5.12 as well, but that has not been tried yet: the script still skips the gyro step on 5.12 unless you pass `--force`.

### Without the ACPI override (BIOS 5.12, stock InputPlumber)

[`no-override/`](no-override/) is a separate, opt-in route that needs no ACPI override, no reboot and no patched InputPlumber. It is tested on BIOS 5.12 only.

- **How it works:** at boot `oxp3-gyro.service` takes the running kernel's own `bmi270_i2c.ko` and makes a copy in `/run`. In the copy it changes the module's one `BMI0160` ACPI id to `10EC5280` and strips the signature. It then unbinds the IMU from `bmi160_i2c` and loads the copy. `bmi270_i2c` loads `bmi260-init-data.fw` (SteamOS already ships it, and a copy is bundled in `/etc/oxp3-gyro/firmware` in case it ever goes away) and exposes a normal IIO device named `bmi260`. Stock InputPlumber 0.78 picks that device up live, so after install no restart is needed for the sensor.
- **Mount matrix:** one key added to the IMU entry in the fix pack's yaml. With stock 0.78 it is `x: [0, -1, 0]`, `y: [0, 0, 1]`, `z: [-1, 0, 0]`. Verified in game: gyro as mouse turns and tilts the right way.
- **Survives updates:** every file is in `/etc`. The module is re-patched from whatever kernel is running, so a SteamOS update needs no re-run. If the fix pack is re-run, it rewrites the yaml without the matrix key; `oxp3-gyro.service` puts the key back at the next boot.
- **After sleep:** `oxp3-gyro-resume.service` reloads the driver if the sensor went silent across sleep.
- **Install / remove:** `gyro/no-override/install.sh` and `gyro/no-override/uninstall.sh`. Install refuses if step 7 is installed or its override is active.

Trade-offs:

- **Kernel taint:** while the copy is loaded the kernel is tainted `E` (unsigned module).
- **bmi160 rebinding:** once the BMI260 has been initialised, `bmi160_i2c` can no longer probe it (-121) until a reboot. Nothing used that binding anyway.
- **CPU cost:** stock InputPlumber 0.78 reads the six IIO channels through sysfs on every 2.5 ms poll. That is about 9% of one core and roughly +0.2 W while the IMU is bound. `sudo systemctl stop oxp3-gyro` turns it off until the next boot.
- **Scale and axes:** stock 0.78 sends the gyro at 12 instead of 16 counts per deg/s (raise Steam's gyro sensitivity to compensate) and passes the accelerometer through unscaled. Gyro to mouse and gyro to joystick work; modes that rely on gravity probably do not. InputPlumber 0.81+ handles units and axis frames itself, so re-check the matrix after an InputPlumber update.

## Files the fix pack installs

| File | Purpose |
|---|---|
| `/boot/acpi_override.img` + `/etc/default/grub.d/oxp3-imu.cfg` | the ACPI override, loaded as an early initrd (reboot needed the first time) |
| `~/oxp3-fix/inputplumber-oxp3-gyro` | (step 5, everyone) the patched InputPlumber from the release archive `oxp3-fix.tar.gz` (downloaded only if missing), checked against a sha256 pinned in the script |
| `~/oxp3-fix/oxp3-inputplumber-launch.sh` + `/etc/systemd/system/inputplumber.service.d/oxp3-gyro-fork.conf` | (step 5, everyone) systemd drop-in that starts the patched build through a launcher; the launcher starts the **stock** `/usr/bin/inputplumber` instead when the patched binary lacks a library or the stock InputPlumber is no longer the 0.78 series, so an OS update cannot leave you without a gamepad |
| `/etc/inputplumber/oxp3-gyro-steer.conf` | tuning, re-read every 2 s without a restart; never overwritten once it exists |
| `~/oxp3-fix/gyro.enabled` / `gyro.declined` | remembers your choice so re-runs after a SteamOS update keep it (or do not ask again) |

`--check` reports all of these. `--no-gyro` removes the gyro files and keeps the patched InputPlumber; `--revert` removes everything (the boot menu reference goes first, then the image).

## Tuning

Edit `/etc/inputplumber/oxp3-gyro-steer.conf` (root); the comments in the file explain each key. The shipped response is linear (`curve=0`, `gain=1.0`) with `tau=20` drift relaxation. `curve` above 0 boosts small tilts (`curve=0.5` gives about 1.5x near the centre, tapering to about 0.5x at `range` degrees) and a lower `gain` calms large angles; these shaping options are available but not enabled by default. The file is only written when it does not exist, so existing installs keep their own values.

## Building the patched InputPlumber yourself

The release binary was built from upstream `v0.78.0` in an Arch container (it links the current Arch libraries; the launcher falls back to the stock binary if SteamOS lacks any of them). To build your own on the deck (rootless podman):

```bash
git clone https://github.com/ShadowBlip/InputPlumber && cd InputPlumber
git checkout v0.78.0 && git apply /path/to/inputplumber-0.78.0-oxp3-gyro.patch
podman run --rm -v "$PWD":/w -v "$HOME/cargo-home":/root/.cargo -w /w docker.io/library/archlinux:latest bash -c \
  'pacman -Syu --noconfirm --needed rust gcc pkgconf libiio systemd-libs libevdev dbus clang && cargo build --release'
```

Copy `target/release/inputplumber` to `~/oxp3-fix/inputplumber-oxp3-gyro`; the fix pack only downloads when the sha256 of that file differs from the pinned one, so a self-built binary needs its `IPF_BIN_SHA256` line in the script updated (or run the pieces by hand).

## License

The patch is a derivative of [InputPlumber](https://github.com/ShadowBlip/InputPlumber) and is therefore **GPL-3.0-or-later**, like upstream; the release binary is distributed under the same license and this directory is its corresponding source. The rest of the repository is MIT.
