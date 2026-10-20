#!/bin/bash
set -uo pipefail

VERSION=20261020
PACK=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/oxp3-game-pack
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/oxp3-game-pack
DLL_LIST=$CONF_DIR/installed-dlls.txt
BAK=.oxp3-pack-bak
DLLS=(d3d12.dll d3d12core.dll)

say() { printf '%s\n' "$*"; }
die() { say "!! $*"; exit 1; }

usage() {
  cat <<EOF
oxp3-game-pack $VERSION: patched Intel driver builds and per-game settings for
Cyberpunk 2077, Resident Evil 4 and Final Fantasy VII Rebirth on the ONEXPLAYER 3.

  $0            install or update (safe to re-run)
  $0 --check    report what is installed and working (paste this in Discord)
  $0 --revert   undo everything except the launch options you pasted into Steam
  --force       skip the ONEXPLAYER 3 check
EOF
  exit 2
}

MODE=install
FORCE=0
for a in "$@"; do
  case $a in
    --check) MODE=check ;;
    --revert) MODE=revert ;;
    --force) FORCE=1 ;;
    *) usage ;;
  esac
done

[ "$(id -u)" != 0 ] || die "run this as your normal user, not with sudo"
[ "$(uname -m)" = x86_64 ] || die "x86_64 only"

DMI_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
BIOS=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || true)
OS_NAME=$(. /etc/os-release 2>/dev/null; echo "${NAME:-?} ${BUILD_ID:-${VERSION_ID:-}}")
if [ "$MODE" = install ] && [ "$FORCE" != 1 ]; then
  if [ "$DMI_VENDOR" != ONE-NETBOOK ] || [[ "$DMI_PRODUCT" != ONEXPLAYER\ 3* ]]; then
    die "this pack is measured on the ONEXPLAYER 3 only (found '$DMI_VENDOR' / '$DMI_PRODUCT'); --force to try anyway"
  fi
fi

steam_root() {
  local d
  for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
    d=$(readlink -f "$d" 2>/dev/null) || continue
    [ -f "$d/steamapps/libraryfolders.vdf" ] && { echo "$d"; return 0; }
  done
  return 1
}

STEAM=$(steam_root) || {
  [ -d "$HOME/.var/app/com.valvesoftware.Steam" ] && die "only Flatpak Steam found; its sandbox cannot see this pack. Use the native Steam package"
  die "no Steam installation found (looked in ~/.local/share/Steam and ~/.steam)"
}

game_dir() {
  local lib acf dir
  while IFS= read -r lib; do
    acf=$lib/steamapps/appmanifest_$1.acf
    [ -f "$acf" ] || continue
    dir=$(sed -n 's/^[[:space:]]*"installdir"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$acf" | head -n1)
    [ -n "$dir" ] && [ -d "$lib/steamapps/common/$dir" ] && { echo "$lib/steamapps/common/$dir"; return 0; }
  done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM/steamapps/libraryfolders.vdf"; echo "$STEAM")
  return 1
}

topology() {
  local c l3=() all=0
  for c in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$c/cache" ] || continue
    all=$((all + 1))
    [ -d "$c/cache/index3" ] && l3+=("${c##*cpu}")
  done
  [ "${#l3[@]}" -gt 0 ] && [ "${#l3[@]}" -lt "$all" ] || return 1
  echo "${#l3[@]}:$(printf '%s\n' "${l3[@]}" | sort -n | paste -sd, -)"
}

conf_get() { sed -n "s/^$2=//p" "$PACK/games/$1.conf.in" | head -n1; }

i686_icd() {
  local j
  for j in /usr/share/vulkan/icd.d/intel_icd.i686.json /usr/share/vulkan/icd.d/intel_icd.i386.json; do
    [ -f "$j" ] && { echo "$j"; return 0; }
  done
  return 1
}

driver_icd() { echo "$PACK/drivers/$1/intel_icd.x86_64.json"; }

write_icd() {
  printf '{ "file_format_version": "1.0.1", "ICD": { "api_version": "1.4.363", "library_arch": "64", "library_path": "%s" } }\n' \
    "$PACK/drivers/$1/libvulkan_intel.so" > "$(driver_icd "$1")"
}

driver_loads() {
  local so=$PACK/drivers/$1/libvulkan_intel.so
  [ -f "$so" ] || return 1
  python3 -I -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1]).vk_icdNegotiateLoaderICDInterfaceVersion' "$so" 2>/dev/null || return 1
  if command -v vulkaninfo >/dev/null 2>&1; then
    VK_DRIVER_FILES=$(driver_icd "$1") DRIRC_CONFIGDIR=$PACK/drivers/$1/drirc.d vulkaninfo --summary 2>/dev/null \
      | grep -q INTEL_OPEN_SOURCE_MESA || return 1
  fi
  return 0
}

APPIDS=(1091500 2050650 2909400)
DRIVERS=(rt12 xmxrt12 ff7r)

md5_of() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

install_dlls() {
  local appid=$1 sub dir f dst
  sub=$(conf_get "$appid" DLLS)
  [ -n "$sub" ] || return 0
  dir=$(game_dir "$appid") || { say "  $(conf_get "$appid" NAME): not installed, DLLs skipped (install the game, then re-run)"; return 0; }
  [ "$sub" = . ] || dir=$dir/$sub
  [ -d "$dir" ] || { say "  !! $dir missing, DLLs skipped"; return 0; }
  for f in "${DLLS[@]}"; do
    dst=$dir/$f
    if [ -e "$dst" ] && [ "$(md5_of "$dst")" != "$(md5_of "$PACK/dlls/$f")" ] && [ ! -e "$dst$BAK" ]; then
      mv "$dst" "$dst$BAK"
    fi
    cp "$PACK/dlls/$f" "$dst"
    grep -qxF "$dst" "$DLL_LIST" 2>/dev/null || echo "$dst" >> "$DLL_LIST"
  done
  say "  $(conf_get "$appid" NAME): vkd3d-proton DLLs copied to $dir"
}

write_conf() {
  local appid=$1 drv=$2 topo=$3 out line icd j
  out=$CONF_DIR/$appid.conf
  {
    if [ "$drv" != none ]; then
      icd=$(driver_icd "$drv")
      j=$(i686_icd) && icd="$icd:$j"
      echo "VK_DRIVER_FILES=$icd"
      echo "DRIRC_CONFIGDIR=$PACK/drivers/$drv/drirc.d"
      echo "OXP3_DRIVER=$PACK/drivers/$drv/libvulkan_intel.so"
    fi
    while IFS= read -r line; do
      case $line in
        NAME=*|DRIVER=*|DLLS=*|LAUNCH=*) continue ;;
        *@TOPO@*) [ -n "$topo" ] || continue; line=${line//@TOPO@/$topo} ;;
      esac
      echo "${line//@CACHE@/$CACHE_DIR}"
    done < "$PACK/games/$appid.conf.in"
  } > "$out.tmp" && mv "$out.tmp" "$out"
}

launch_option() {
  local extra run="'$PACK/oxp3-run'"
  extra=$(conf_get "$1" LAUNCH)
  [[ "$PACK" == "$HOME"/* ]] && [[ "$PACK" != *[[:space:]\'\"]* ]] && run=$'~'"/${PACK#"$HOME"/}/oxp3-run"
  echo "$run %command%${extra:+ $extra}"
}

launch_options_in_steam() {
  python3 -I - "$STEAM" "$1" <<'EOF'
import glob, re, sys
steam, appid = sys.argv[1], sys.argv[2]
for f in glob.glob(steam + "/userdata/*/config/localconfig.vdf"):
    t = open(f, errors="ignore").read()
    for m in re.finditer(r'\n\s*"%s"\s*\n\s*\{' % appid, t):
        depth, i = 1, m.end()
        while depth and i < len(t):
            depth += {"{": 1, "}": -1}.get(t[i], 0)
            i += 1
        lo = re.search(r'"LaunchOptions"\s*"((?:[^"\\]|\\.)*)"', t[m.end():i])
        if lo:
            print(lo.group(1))
            sys.exit(0)
EOF
}

tdp_sync() {
  local msr=/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw mmio=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw a b
  [ -r "$msr" ] && [ -r "$mmio" ] || { echo "unknown (no RAPL)"; return; }
  a=$(( $(cat "$msr") / 1000000 )); b=$(( $(cat "$mmio") / 1000000 ))
  if [ "$a" = "$b" ]; then echo "ok, PL1 $b W"; else echo "MISMATCH: TDP $b W but the GPU obeys $a W (fix pack step 8 fixes this)"; fi
}

check() {
  local bad=0 d appid name drv st dir f lo last
  say "oxp3-game-pack $VERSION check"
  say "device: $DMI_VENDOR $DMI_PRODUCT, BIOS $BIOS, $OS_NAME, kernel $(uname -r)"
  say "system Mesa: $( (pacman -Q vulkan-intel 2>/dev/null || rpm -q mesa-vulkan-drivers 2>/dev/null || echo '?') | head -n1)"
  st=""
  for d in "${DRIVERS[@]}"; do
    if driver_loads "$d"; then st="$st $d ok"; else st="$st $d FAILED"; bad=$((bad + 1)); fi
  done
  say "drivers:$st"
  say "topology: $(topology || echo 'none (all cores share L3)')"
  say "TDP sync: $(tdp_sync)"
  for appid in "${APPIDS[@]}"; do
    name=$(conf_get "$appid" NAME)
    st=""
    if dir=$(game_dir "$appid"); then st="installed"; else say "$name: not installed"; continue; fi
    if [ -f "$CONF_DIR/$appid.conf" ]; then st="$st, settings ok"; else st="$st, settings MISSING"; bad=$((bad + 1)); fi
    if [ -n "$(conf_get "$appid" DLLS)" ]; then
      for f in "${DLLS[@]}"; do
        if [ "$(md5_of "$dir/$(conf_get "$appid" DLLS)/$f")" != "$(md5_of "$PACK/dlls/$f")" ]; then st="$st, $f MISSING (game update or Verify?)"; bad=$((bad + 1)); fi
      done
      [[ "$st" == *MISSING\ \(* ]] || st="$st, DLLs ok"
    fi
    lo=$(launch_options_in_steam "$appid" 2>/dev/null)
    if [[ "$lo" == *oxp3-run* ]]; then st="$st, launch option ok"; else st="$st, launch option MISSING"; bad=$((bad + 1)); fi
    last=$(grep " appid=$appid " "$CACHE_DIR/launch.log" 2>/dev/null | tail -n1 | cut -d' ' -f1,3)
    say "$name: $st${last:+, last launch $last}"
  done
  say "$bad problem(s)"
  return $((bad > 0))
}

revert() {
  local f
  if [ -f "$DLL_LIST" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -e "$f$BAK" ]; then
        mv -f "$f$BAK" "$f" && say "  restored $f"
      elif [ -e "$f" ] && [ "$(md5_of "$f")" = "$(md5_of "$PACK/dlls/${f##*/}")" ]; then
        rm -f "$f" && say "  removed $f"
      fi
    done < "$DLL_LIST"
  fi
  rm -rf "$CONF_DIR" "$CACHE_DIR"
  say "Done. Per-game settings and the private shader caches are gone; the games use Steam's stock setup again."
  say "Last step, by hand: in Steam, Properties > General > Launch Options, delete the oxp3-run part for each game."
}

case $MODE in
  check) check; exit $? ;;
  revert) revert; exit 0 ;;
esac

say "oxp3-game-pack $VERSION"
( cd "$PACK" && sha256sum --quiet -c SHA256SUMS ) || die "pack files are damaged or incomplete; download the archive again"
command -v python3 >/dev/null 2>&1 || die "python3 is needed"
mkdir -p "$CONF_DIR" "$CACHE_DIR"

declare -A DRV_OK
for d in "${DRIVERS[@]}"; do
  write_icd "$d"
  if driver_loads "$d"; then DRV_OK[$d]=1; say "  driver $d: loads"; else DRV_OK[$d]=0; say "  !! driver $d does not load on this system; its games keep the system driver"; fi
done

TOPO=$(topology) && say "  topology: games see only the cores with L3 ($TOPO)" || { TOPO=""; say "  topology: not applicable here"; }

for appid in "${APPIDS[@]}"; do
  drv=$(conf_get "$appid" DRIVER)
  [ "${DRV_OK[$drv]:-0}" = 1 ] || drv=none
  write_conf "$appid" "$drv" "$TOPO"
  install_dlls "$appid"
done

say ""
say "Now paste one line into each game: Steam > game > Properties > General > Launch Options"
for appid in "${APPIDS[@]}"; do
  say "  $(conf_get "$appid" NAME):"
  say "    $(launch_option "$appid")"
done
say ""
say "Then set the per-game SimpleDeckyTDP profiles from README step 4 (RE4: GPU range 650-2200 MHz, EPP performance)."
say "Check any time: $0 --check   Undo: $0 --revert"
