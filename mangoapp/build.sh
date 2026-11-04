#!/bin/bash
# Build mangoapp (MangoHud 33c2c7dd + Valve cherry-picks + OXP3 iGPU patch) against the SteamOS package set, so the
# binary links the same library versions as the device. Log: ~/mh-build/build.log
exec podman run --rm -v /home/deck/mh-build:/w -v /etc/pacman.d/mirrorlist:/etc/pacman.d/mirrorlist.steamos:ro -v /usr/share/pacman/keyrings:/usr/share/pacman/keyrings.steamos:ro -w /w docker.io/library/archlinux:latest bash -c "
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
pacman -Syyuu --noconfirm >/w/pacman.log 2>&1
pacman -S --noconfirm --needed base-devel git meson glslang glew glfw-x11 libglvnd libx11 libxrandr libxkbcommon python python-mako dbus unzip wayland >>/w/pacman.log 2>&1
pacman -Q glibc gcc >>/w/pacman.log
rm -rf /w/MangoHud && git clone -q https://github.com/flightlessmango/MangoHud.git /w/MangoHud
cd /w/MangoHud && git -c advice.detachedHead=false checkout -q 33c2c7ddbb72c15e19a42163d75424d5804f8ec8
git -c user.email=x@x -c user.name=x cherry-pick -n 0805396e579c5f1ea27e2e2a78030d8ef6ce1994 9400280e0daa000def18931c3fce80511d53b1c0 2c1dc5283c045e9a7e424dc913fbafcdcc7e3be1
git apply /w/src/mangohud-oxp3-igpu.patch
cd /w/src && for t in imgui-1.91.6.tar.gz spdlog-v1.14.1.tar.gz vulkan-headers-1.3.283.tar.gz; do tar -xzf \$t; done; unzip -oq implot-v0.16.zip
for z in imgui_1.91.6-3_patch.zip spdlog-1.14.1-1-wrap.zip vulkan-headers-1.3.283-1-wrap.zip implot-v0.16-1-wrap.zip; do unzip -oq \$z; done
cd /w/MangoHud/subprojects && ln -sfn /w/src/imgui-1.91.6 . && ln -sfn /w/src/spdlog-1.14.1 . && ln -sfn /w/src/implot-0.16 . && ln -sfn /w/src/Vulkan-Headers-1.3.283 .
source /etc/makepkg.conf
export CFLAGS CXXFLAGS LDFLAGS
cd /w/MangoHud && rm -rf /w/b && meson setup /w/b --prefix=/usr --libexecdir=lib --buildtype=plain --wrap-mode=nodownload -D append_libdir_mangohud=false -D use_system_spdlog=disabled -D mangoapp=true -D mangohudctl=false -D with_xnvctrl=disabled -D tests=disabled >/w/meson.log 2>&1
meson compile -C /w/b mangoapp 2>&1 | tail -40
strip /w/b/src/mangoapp
ls -l /w/b/src/mangoapp
"
