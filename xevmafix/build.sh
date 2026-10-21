#!/bin/bash
exec podman run --rm -v /home/deck/xevmafix-build:/w -v /etc/pacman.d/mirrorlist:/etc/pacman.d/mirrorlist.steamos:ro -w /w docker.io/library/archlinux:latest bash -c "
set -e
cat > /etc/pacman.conf <<P
[options]
Architecture = auto
SigLevel = Never
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
pacman -Syyuu --noconfirm >/w/build.log 2>&1
pacman -S --noconfirm --needed base-devel linux-neptune-72-headers >>/w/build.log 2>&1
pacman -Q linux-neptune-72-headers gcc | tee -a /w/build.log
K=\$(ls /usr/lib/modules | head -n1)
make -C /usr/lib/modules/\$K/build M=/w CONFIG_DEBUG_INFO_BTF_MODULES= modules >>/w/build.log 2>&1
modinfo -F vermagic /w/xevmafix.ko
sha256sum /w/xevmafix.ko
"
