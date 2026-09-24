# Experimental gyroscope support

Opt-in step 7 of the fix pack (`./oxp3-apply-fixes.sh --gyro`). This directory holds the sources behind it.

**Status: experimental.** The gyro works and Steam's gyro layouts (gyro to joystick, camera, flick stick) accept it, but the sensor has a temperature-dependent bias about the vertical axis that gravity cannot correct, so drift is *reduced*, not eliminated. Nothing here is enabled unless you ask for it, and `--no-gyro` removes it again.

## Why the gyro needs three things

1. **The kernel cannot see the sensor.** The IMU is a Bosch BMI260 on I2C bus 2 (address 0x68), but the firmware names its ACPI node `10EC5280`. That id belongs to the `bmi160_i2c` driver, which fails with `Error reading chip id` (-121). `bmi270_i2c` supports the BMI260 but only matches the ids `BMI0160` and `BMI0260`. An **ACPI table override** ships a copy of the firmware's `SSDT26` (`Rtd3` / `I2C_DEVT`) with the node renamed to `BMI0260`, and the kernel then exposes a normal IIO device. The table is specific to **BIOS 5.09**, so the script refuses to install it on other versions (`--force` overrides). Source: [`SSDT26-oxp3-imu.dsl`](SSDT26-oxp3-imu.dsl); the compiled table is embedded in `oxp3-apply-fixes.sh` as an `acpi_override.img` cpio image loaded through `GRUB_EARLY_INITRD_LINUX_CUSTOM`.
2. **InputPlumber needs to understand the sensor.** A [patched InputPlumber 0.78.0](inputplumber-0.78.0-oxp3-gyro.patch) adds a mount matrix and bias options to the IIO source, orders the gyro fields the way Steam's Steam Deck HID driver reads them, and feeds them to the virtual Steam Deck controller (`deck-uhid`) at Steam's fixed 4 ms report interval. The yaml entry for the IMU gets the matching keys (the fix pack writes them only when gyro is enabled).
3. **Drift handling.** The new `gyro_steer` module passes the yaw rate through a slow high-pass: it mirrors the angle Steam integrates and folds a small return rate into the stream, so a constant bias becomes a small bounded offset instead of a runaway drift. Response shaping (`curve`, `gain`, `range`) gives small tilts more reach than large ones. It can also learn the bias while the device rests, or map the angle to the left stick instead (`mode=stick`).

## Files the fix pack installs

| File | Purpose |
|---|---|
| `/boot/acpi_override.img` + `/etc/default/grub.d/oxp3-imu.cfg` | the ACPI override, loaded as an early initrd (reboot needed the first time) |
| `~/oxp3-fix/inputplumber-oxp3-gyro` | the patched InputPlumber, downloaded from the GitHub release and checked against a sha256 pinned in the script |
| `~/oxp3-fix/oxp3-inputplumber-launch.sh` + `/etc/systemd/system/inputplumber.service.d/oxp3-gyro-fork.conf` | systemd drop-in that starts the patched build through a launcher; the launcher starts the **stock** `/usr/bin/inputplumber` instead when the patched binary lacks a library or the stock InputPlumber is no longer the 0.78 series, so an OS update cannot leave you without a gamepad |
| `/etc/inputplumber/oxp3-gyro-steer.conf` | tuning, re-read every 2 s without a restart; never overwritten once it exists |
| `~/oxp3-fix/gyro.enabled` / `gyro.declined` | remembers your choice so re-runs after a SteamOS update keep it (or do not ask again) |

`--check` reports all of these, `--no-gyro` and `--revert` remove them (the boot menu reference goes first, then the image).

## Tuning

Edit `/etc/inputplumber/oxp3-gyro-steer.conf` (root); the comments in the file explain each key. The shipped values (`tau=20`, `range=45`, `curve=0.5`, `gain=0.85`) suit gyro-to-joystick steering: small tilts are boosted to about 1.5x near the centre, tapering to about 0.5x at 45 degrees. `curve=0` makes the response linear, lower `gain` calms large angles.

## Building the patched InputPlumber yourself

The release binary was built from upstream `v0.78.0` in an Arch container (it links the current Arch libraries; the launcher falls back to the stock binary if SteamOS lacks any of them). To build your own on the deck (rootless podman):

```bash
git clone https://github.com/ShadowBlip/InputPlumber && cd InputPlumber
git checkout v0.78.0 && git apply /path/to/inputplumber-0.78.0-oxp3-gyro.patch
podman run --rm -v "$PWD":/w -v "$HOME/cargo-home":/root/.cargo -w /w docker.io/library/archlinux:latest bash -c \
  'pacman -Syu --noconfirm --needed rust gcc pkgconf libiio systemd-libs libevdev dbus clang && cargo build --release'
```

Copy `target/release/inputplumber` to `~/oxp3-fix/inputplumber-oxp3-gyro`; the fix pack only downloads when the sha256 of that file differs from the pinned one, so a self-built binary needs its `GYRO_BIN_SHA256` line in the script updated (or run the pieces by hand).

## License

The patch is a derivative of [InputPlumber](https://github.com/ShadowBlip/InputPlumber) and is therefore **GPL-3.0-or-later**, like upstream; the release binary is distributed under the same license and this directory is its corresponding source. The rest of the repository is MIT.
