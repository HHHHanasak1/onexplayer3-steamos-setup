#!/bin/bash
exec podman run --rm -v /home/deck/xehdrfix-build:/w -v /etc/pacman.d/mirrorlist:/etc/pacman.d/mirrorlist.steamos:ro -v /usr/share/pacman/keyrings:/usr/share/pacman/keyrings.steamos:ro -w /w docker.io/library/archlinux:latest bash -c "
set -e
cat > /etc/pacman.conf <<P
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
ParallelDownloads = 10
[jupiter-main]
Include = /etc/pacman.d/mirrorlist.steamos
[holo-main]
Include = /etc/pacman.d/mirrorlist.steamos
[core-main]
Include = /etc/pacman.d/mirrorlist.steamos
[extra-main]
Include = /etc/pacman.d/mirrorlist.steamos
P
# packages are signature-checked: the container trusts the Arch keys it ships plus the deck's Valve (holo) keys
cp /usr/share/pacman/keyrings.steamos/holo* /usr/share/pacman/keyrings/
pacman-key --init >/dev/null 2>&1 && pacman-key --populate archlinux holo >/dev/null 2>&1
pacman -Syyuu --noconfirm >/w/build.log 2>&1
pacman -S --noconfirm --needed base-devel linux-neptune-72-headers >>/w/build.log 2>&1
pacman -Q linux-neptune-72-headers gcc | tee -a /w/build.log
K=\$(ls /usr/lib/modules | head -n1)
make -C /usr/lib/modules/\$K/build M=/w CONFIG_DEBUG_INFO_BTF_MODULES= modules >>/w/build.log 2>&1
modinfo -F vermagic /w/xehdrfix.ko
sha256sum /w/xehdrfix.ko
"
