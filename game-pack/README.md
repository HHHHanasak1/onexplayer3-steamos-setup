# Game pack (optional): Cyberpunk 2077, Resident Evil 4 and Final Fantasy VII Rebirth

Patched Intel Vulkan driver builds and measured per-game settings for the ONEXPLAYER 3 (Arc B390). The fix pack does not need this. You can install it on its own, on SteamOS or on another Linux with the native Steam client and remove it again with one command.

## What you get

All numbers are from one ONEXPLAYER 3 at a 30 W TDP, SDR, with no in-game setting changed between the two columns.

| Game | Before | With the pack | Scene and settings |
|---|---|---|---|
| Final Fantasy VII Rebirth | 52.6 fps, 1% low 39.7 | **72.7 fps, 1% low 58.6** | Gongaga field, 40 s camera spin, 1920x1080, TAA. *Before* is Mesa 26.1.2, the driver SteamOS ships. A ROG Xbox Ally X (Z2 Extreme) measured 55.5 fps in the same scene at 30 W |
| Cyberpunk 2077 | 59.0 fps | **79.3 fps** | Built-in benchmark, Steam Deck preset (FSR). *Before* is SteamOS Mesa 26.1.2. With the CPU clocks capped as well (P 2.0 / E 1.8 / LP 1.5 GHz, EPP balance_performance) and PL2 at 30.5 W it reached 80.5, but those caps aren't part of the pack |
| Resident Evil 4 | 89.8 fps, 1% low 72.5 | **95.4 fps, 1% low 70.5** | Chapter 6, 30 s still + 40 s camera spin. *Before* is already Mesa 26.3, without the pack's patches. Average +6 %, 1% low about the same and only with the SimpleDeckyTDP profile in step 4 (without it the 1% low drops to ~58) |

Where the gains come from:

| Part | What it does | Games |
|---|---|---|
| Mesa 26.3 with the Jay compiler | Newer Intel driver than SteamOS ships. On its own it took Cyberpunk from 59 to 72 fps | all three |
| anv L1/L2 flush + compute copies | Two driver patches for Xe2/Xe3: lighter cache flushes for generic writes, buffer copies on the compute pipeline. Cyberpunk +1.6 fps | Cyberpunk, RE4 |
| FF7R driver build | Shader compiler work aimed at FF7 Rebirth's heaviest passes: atomic fusion and skipping, bounded SSBO loads, mesh varyings packing. The switches are only turned on in FF7R's settings | FF7R |
| vkd3d-proton hostsync | One-line vkd3d-proton fix: the Intel driver no longer pays a full barrier on every submit. Cyberpunk +1.2 fps | Cyberpunk, RE4 |
| CPU topology | The game only sees the 10 cores that share the L3 cache which keeps its worker threads off the 4 LP E-cores. Cyberpunk +2.0 fps and better 1% lows | Cyberpunk, RE4 |
| Xalia off, private shader cache | Proton's accessibility helper off, +0.2 fps. The private cache keeps Steam from pruning the patched driver's shaders after a Steam restart | as listed in `games/` |

## Before you start

- An ONEXPLAYER 3. The installer checks this since the topology and the driver builds are specific to this chip.
- **SteamOS:** install the [fix pack](../README.md) first, with step 14 (SimpleDeckyTDP-Intel) if you want the RE4 profile. Its TDP sync (step 8) and content-driven HDR are part of the numbers above.
- **Another distribution** (Bazzite, CachyOS, Arch, ...): the native Steam client (not Flatpak), `python3` and a TDP tool. `--check` tells you if the GPU is held at a lower power limit than the TDP you set.
- Proton Experimental for the three games. That's what the numbers above used. Other Proton versions are untested.

## Install

**1. Download and unpack** (Desktop Mode > Konsole or any terminal):

```bash
cd ~ && curl -fL https://github.com/kas5852/onexplayer3-steamos-setup/releases/download/game-pack-20261020/oxp3-game-pack.tar.gz | tar -xz
```

This creates `~/oxp3-game-pack`. Keep that folder: the games load the driver from it.

**2. Run the installer:**

```bash
~/oxp3-game-pack/oxp3-game-pack.sh
```

It needs no sudo and it changes no system files. What it does:

- tests each driver build on your system and only uses the ones that load
- writes the per-game settings to `~/.config/oxp3-game-pack/`
- copies the two vkd3d-proton DLLs into the Cyberpunk and RE4 game folders, keeping any file it replaces as `*.oxp3-pack-bak`.

At the end it prints one launch option per game.

**3. Paste the launch options.** In Steam: the game > ⚙ > Properties > General > Launch Options. These are the lines, assuming the pack is in `~/oxp3-game-pack`:

| Game | Launch option |
|---|---|
| Cyberpunk 2077 | `~/oxp3-game-pack/oxp3-run %command% --launcher-skip -skipStartScreen` |
| Resident Evil 4 | `~/oxp3-game-pack/oxp3-run %command%` |
| Final Fantasy VII Rebirth | `~/oxp3-game-pack/oxp3-run %command%` |

If a game already has launch options, keep your own variables in front, for example `MANGOHUD=1 ~/oxp3-game-pack/oxp3-run %command%`.

**4. Per-game power profiles.** Start the game, open SimpleDeckyTDP, turn on the per-game profile and set:

| Game | TDP | GPU frequency | EPP | CPU Boost (SimpleDeckyTDP-Intel) |
|---|---|---|---|---|
| Resident Evil 4 | 30 W | **Range, 650-2200 MHz** | **performance** | Smart |
| Final Fantasy VII Rebirth | 30 W | default | **performance** | default |
| Cyberpunk 2077 | 30 W | default | balance_performance | default |

EPP is under the plugin's advanced options. RE4's GPU cap matters most: without it the faster driver pushes the GPU into the power limit, the clock dips and every dip is a slow frame. With the 2200 cap the 1% low goes from about 58 to 70.

**5. First launch.** Each game builds its shaders again with the new driver the first time (the cache is new). Expect a longer load and some stutter during the first few minutes. Play a little, then judge.

## Check that it works

```bash
~/oxp3-game-pack/oxp3-game-pack.sh --check
```

```
oxp3-game-pack 20261020 check
device: ONE-NETBOOK ONEXPLAYER 3, BIOS ..., SteamOS 20261015.1000, kernel 7.2.7-...
drivers: rt12 ok xmxrt12 ok ff7r ok
topology: 10:0,1,2,3,4,5,6,7,8,9
TDP sync: ok, PL1 30 W
Cyberpunk 2077: installed, settings ok, DLLs ok, launch option ok, last launch 2026-10-20T19:02:11-07:00 pack=on
...
0 problem(s)
```

`pack=on` on the last launch means the game ran with the pack. `pack=on-stock-driver` means the driver build did not load and the game used the system driver.

## Compare it yourself

Put `OXP3_PACK=0` at the front of a game's launch option to run without the pack's driver and settings (the DLLs stay, `--revert` removes those as well). Same scene, same TDP, two or three runs each way and ignore the very first run after a change while shaders compile.

The easiest test is Cyberpunk's built-in benchmark: Steam Deck preset, 30 W, performance overlay off, runs 2 and 3 counted.

## Updates and what can undo it

| Event | Effect | What to do |
|---|---|---|
| SteamOS or distribution update | Usually nothing. If a library changed and a driver build stops loading, that game falls back to the system driver by itself | `--check`, then report a `FAILED` driver |
| Proton update | The game-folder DLLs are a vkd3d-proton build from 2026-10-18 and stay in place which means the game keeps that vkd3d instead of the newer one | Fine for now. Once vkd3d-proton ships the fix, `--revert` and reinstall |
| Game update or Verify integrity | The DLLs are not part of the game files and usually survive. `--check` shows them as missing if not | Re-run the installer |
| A new pack release | | Unpack it over the old one and re-run the installer |

## Remove it

```bash
~/oxp3-game-pack/oxp3-game-pack.sh --revert
```

This puts back any DLL it replaced and deletes the per-game settings and the pack's shader caches. Then delete the `oxp3-run` part from each game's launch options and `~/oxp3-game-pack` if you like.

## Troubleshooting

| Symptom | Fix |
|---|---|
| A game does not start | Set its launch option to just `%command%`, start it once, then run `--check` and post the output |
| Black or flickering patches, missing grass or geometry (FF7R) | Post a screenshot and the spot. `OXP3_PACK=0` in front of the launch option to keep playing meanwhile |
| `MISMATCH` in the TDP sync line | The GPU is held below your TDP. On SteamOS, run the fix pack (step 8) |
| `launch option MISSING` although you pasted it | Steam saves the options when you close the Properties window and `--check` reads them from Steam's config file. Close the window or restart Steam |

## XeSS on the XMX units (optional)

The Cyberpunk driver build includes the [xess-xmx-linux](https://github.com/HHHHanasak1/xess-xmx-linux) patches. With xess-xmx installed and XeSS 2.0.2.68 in the game folder (see its docs/games.md), Cyberpunk runs XeSS on the matrix engines: 87.3 fps on the same device. This combination was tested with the xess-xmx 20261005 kernels. Reports with newer releases are welcome.

## Sources

| Binary | Built from |
|---|---|
| `drivers/rt12` | Mesa main e793bd0 (26.3-devel) + `patches/mesa/0001`, `0002` |
| `drivers/xmxrt12` | the same + xess-xmx-linux `patches/mesa-26.3` 0001-0003 |
| `drivers/ff7r` | Mesa 26.3-devel with the FF7R patch stack. Full source tree as the release asset `mesa-ff7r-src.tar.xz` |
| `dlls/d3d12.dll`, `d3d12core.dll` | vkd3d-proton 0bb64c56 + `patches/vkd3d/0001` |

`patches/proton/0001` is the permanent form of the topology setting (Proton derives the topology from the launch affinity on x86 too). It is not used by the pack. Upstream merge requests for the Mesa, vkd3d-proton and Proton patches are planned and the pack drops each part once its fix ships. Mesa is MIT licensed, vkd3d-proton LGPL 2.1.
