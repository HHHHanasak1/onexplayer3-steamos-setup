#!/bin/bash
# Builds xevmafix.ko and xehdrfix.ko for one SteamOS kernel package.
#   REPO  the SteamOS repository set: "main" (jupiter-main, holo-main, ...) or a release such as "3.10"
#   PKG   the kernel package, e.g. linux-neptune-73 (its -headers package is installed for the build)
#   VER   the package version the caller expects (the build stops when the repository has another one)
# Runs in an archlinux container: the repository at /src, the results go to /out:
#   /out/kernel                  the kernel release the modules are for (uname -r)
#   /out/xevmafix-<kernel>.ko    (not built when listed in /out/not-needed)
#   /out/xehdrfix-<kernel>.ko
#   /out/not-needed              modules the kernel does not need (xevmafix when its xe driver uses kvmalloc), one per line
# Packages are signature-checked: Arch keys from the container, Valve (holo) keys from ci/holo-keyring.
# Fails when the xe code the modules hook changed, so nothing gets published for that kernel (unless the kernel no
# longer needs that module: then it is listed in /out/not-needed instead).
set -euo pipefail
: "${REPO:?}" "${PKG:?}" "${VER:?}"
MIRROR='https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch'
{
    printf '[options]\nArchitecture = auto\nSigLevel = Required DatabaseOptional\nParallelDownloads = 10\n'
    for r in "jupiter-$REPO" "holo-$REPO" "core-$REPO" "extra-$REPO"; do printf '[%s]\nServer = %s\n' "$r" "$MIRROR"; done
} > /etc/pacman.conf
cp /src/ci/holo-keyring/holo* /usr/share/pacman/keyrings/
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux holo >/dev/null 2>&1
pacman -Syyuu --noconfirm >/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
pacman -S --noconfirm --needed base-devel python "$PKG-headers" >>/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
mkdir -p /tmp/kpkg
pacman -Sw --noconfirm --cachedir /tmp/kpkg "$PKG" >>/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
pacman -Q "$PKG-headers" gcc
hv=$(pacman -Q "$PKG-headers" | cut -d" " -f2)
[ "$hv" = "$VER" ] || { echo "$PKG-headers is $hv in the $REPO repositories, expected $VER"; exit 1; }

K=$(ls /usr/lib/modules)
[ "$(printf '%s\n' "$K" | wc -l)" = 1 ] || { echo "expected one kernel in /usr/lib/modules: $K"; exit 1; }
KPKG=$(ls /tmp/kpkg/"$PKG"-[0-9]*.pkg.tar.zst)
mkdir -p /tmp/kernel
tar -C /tmp/kernel -xf "$KPKG" --wildcards '*/xe.ko*'
XE=$(find /tmp/kernel -name 'xe.ko*' | head -n1)
case "$XE" in
    *.zst) zstd -dqf "$XE" -o /tmp/xe.ko ;;
    *.xz) xz -dc "$XE" > /tmp/xe.ko ;;
    *) cp "$XE" /tmp/xe.ko ;;
esac
rc=0
python3 /src/ci/check-xe.py /tmp/xe.ko /src/xevmafix/xevmafix.c /src/xehdrfix/xehdrfix.c "/usr/lib/modules/$K/build/Module.symvers" || rc=$?
mkdir -p /out
: > /out/not-needed
case "$rc" in
    0) mods="xevmafix xehdrfix" ;;
    3) mods="xehdrfix"; echo xevmafix >> /out/not-needed ;;   # the kernel has the fix itself
    *) exit 1 ;;
esac

for m in $mods; do
    rm -rf "/tmp/$m" && mkdir "/tmp/$m" && cp "/src/$m/$m.c" "/src/$m/Makefile" "/tmp/$m/"
    make -C "/usr/lib/modules/$K/build" M="/tmp/$m" CONFIG_DEBUG_INFO_BTF_MODULES= modules >"/tmp/$m.log" 2>&1 || { tail -40 "/tmp/$m.log"; exit 1; }
    vm=$(modinfo -F vermagic "/tmp/$m/$m.ko" | cut -d' ' -f1)
    [ "$vm" = "$K" ] || { echo "$m: vermagic $vm, expected $K"; exit 1; }
    cp "/tmp/$m/$m.ko" "/out/$m-$K.ko"
done
printf '%s\n' "$K" > /out/kernel
cd /out && sha256sum ./*.ko
