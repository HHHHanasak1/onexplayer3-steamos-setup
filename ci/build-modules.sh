#!/bin/bash
# Builds xevmafix.ko and xehdrfix.ko for the current SteamOS main kernel (linux-neptune-72 in jupiter-main).
# Runs in an archlinux container: the repository at /src, the results go to /out:
#   /out/kernel                  the kernel release the modules are for (uname -r)
#   /out/xevmafix-<kernel>.ko
#   /out/xehdrfix-<kernel>.ko
# Packages are signature-checked: Arch keys from the container, Valve (holo) keys from ci/holo-keyring.
# Fails when the xe code the modules hook changed, so nothing gets published for that kernel.
set -euo pipefail
MIRROR='https://steamdeck-packages.steamos.cloud/archlinux-mirror/$repo/os/$arch'
{
    printf '[options]\nArchitecture = auto\nSigLevel = Required DatabaseOptional\nParallelDownloads = 10\n'
    for r in jupiter-main holo-main core-main extra-main; do printf '[%s]\nServer = %s\n' "$r" "$MIRROR"; done
} > /etc/pacman.conf
cp /src/ci/holo-keyring/holo* /usr/share/pacman/keyrings/
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux holo >/dev/null 2>&1
pacman -Syyuu --noconfirm >/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
pacman -S --noconfirm --needed base-devel python linux-neptune-72-headers >>/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
mkdir -p /tmp/kpkg
pacman -Sw --noconfirm --cachedir /tmp/kpkg linux-neptune-72 >>/tmp/pacman.log 2>&1 || { tail -30 /tmp/pacman.log; exit 1; }
pacman -Q linux-neptune-72-headers gcc

K=$(ls /usr/lib/modules)
[ "$(printf '%s\n' "$K" | wc -l)" = 1 ] || { echo "expected one kernel in /usr/lib/modules: $K"; exit 1; }
KPKG=$(ls /tmp/kpkg/linux-neptune-72-[0-9]*.pkg.tar.zst)
mkdir -p /tmp/kernel
tar -C /tmp/kernel -xf "$KPKG" --wildcards '*/xe.ko*'
XE=$(find /tmp/kernel -name 'xe.ko*' | head -n1)
case "$XE" in
    *.zst) zstd -dqf "$XE" -o /tmp/xe.ko ;;
    *.xz) xz -dc "$XE" > /tmp/xe.ko ;;
    *) cp "$XE" /tmp/xe.ko ;;
esac
python3 /src/ci/check-xe.py /tmp/xe.ko /src/xevmafix/xevmafix.c /src/xehdrfix/xehdrfix.c "/usr/lib/modules/$K/build/Module.symvers"

mkdir -p /out
for m in xevmafix xehdrfix; do
    rm -rf "/tmp/$m" && mkdir "/tmp/$m" && cp "/src/$m/$m.c" "/src/$m/Makefile" "/tmp/$m/"
    make -C "/usr/lib/modules/$K/build" M="/tmp/$m" CONFIG_DEBUG_INFO_BTF_MODULES= modules >"/tmp/$m.log" 2>&1 || { tail -40 "/tmp/$m.log"; exit 1; }
    vm=$(modinfo -F vermagic "/tmp/$m/$m.ko" | cut -d' ' -f1)
    [ "$vm" = "$K" ] || { echo "$m: vermagic $vm, expected $K"; exit 1; }
    cp "/tmp/$m/$m.ko" "/out/$m-$K.ko"
done
printf '%s\n' "$K" > /out/kernel
cd /out && sha256sum ./*.ko
