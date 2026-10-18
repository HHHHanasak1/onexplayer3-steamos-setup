# Patched mangoapp: GPU power and temperature for the integrated GPU

Part of step 10 of the fix pack. The performance overlay (mangoapp, from MangoHud) reads GPU power and temperature only from the GPU's hwmon device, and the xe driver creates one only for discrete GPUs, so on the ONEXPLAYER 3 the overlay shows no GPU power and no GPU temperature.

[`mangohud-0.8.3-oxp3-igpu.patch`](mangohud-0.8.3-oxp3-igpu.patch) adds a fallback for an integrated xe GPU without hwmon:

- **GPU power** comes from RAPL PP1 (`/sys/class/powercap/intel-rapl:0:1`, named `uncore` by Linux), the graphics power plane on Intel client CPUs. It is an estimate made by the CPU, like the CPU package power, and it may include closely related blocks (Intel does not document the exact boundary on Panther Lake). The fix pack's `oxp3-rapl-overlay.service` publishes a coarse copy of this counter, because the raw one is root-only.
- **CPU power** comes from RAPL PP0 (`intel-rapl:0:0`, `core`), the CPU cores, instead of the whole package (`intel-rapl:0`), which includes the GPU. Otherwise the GPU's share would be counted twice in the overlay. The fix pack publishes a coarse copy of this counter too. Without a readable `core` zone the package is used, as in stock MangoHud.
- **SoC power** is a new line right after the GPU: the whole package (`intel-rapl:0`), that is CPU cores, GPU and the shared blocks, which is what the TDP limits. It appears wherever GPU power is shown (Steam overlay levels 2 to 4).
- **GPU temperature** is the CPU package temperature (`coretemp`, "Package id 0"): the GPU is on the same chip and has no sensor of its own, so the GPU and CPU temperatures in the overlay are the same value.

## How it is installed

The binary is in the release archive (`mangoapp-oxp3`, sha256 pinned in the script). A systemd user drop-in for `gamescope-mangoapp.service` starts it through `~/oxp3-fix/oxp3-mangoapp-launch.sh`, which runs the stock `/usr/bin/mangoapp` instead when the binary is missing, cannot load a library, was built for a different SteamOS mangohud package, or crashed three times within a minute.

## Building

The patch applies to MangoHud commit `33c2c7dd` plus the three commits Valve cherry-picks in the SteamOS `mangohud 0.8.3.rc1.r24.g33c2c7dd` package. [`build.sh`](build.sh) builds it in an Arch container that uses the SteamOS package repositories, so the binary links the same library versions as the device. It expects the subproject archives from Valve's source package (`mangohud-0.8.3.rc1.r24.g33c2c7dd-4.src.tar.gz` on the SteamOS mirror) and the patch in `~/mh-build/src`.

MangoHud and the bundled subprojects (imgui, implot, spdlog) are MIT licensed.
