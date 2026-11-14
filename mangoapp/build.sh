#!/bin/bash
# Build mangoapp (MangoHud 8d76620f, the SteamOS mangohud 0.8.4.r235.g8d76620f package, + OXP3 iGPU patch) against the
# SteamOS package set, so the binary links the same library versions as the device. Log: ~/mh-build/build.log
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
pacman -S --noconfirm --needed base-devel git meson glslang glew glfw-x11 libglvnd libx11 libxi libxrandr libxkbcommon libdrm nlohmann-json python python-mako dbus unzip wayland vulkan-icd-loader >>/w/pacman.log 2>&1
pacman -Q glibc gcc >>/w/pacman.log
rm -rf /w/MangoHud && git clone -q https://github.com/flightlessmango/MangoHud.git /w/MangoHud
cd /w/MangoHud && git -c advice.detachedHead=false checkout -q 8d76620f71e92e5f686940404bfa7625a9034213
git apply /w/src/mangohud-oxp3-igpu.patch
# subprojects as in the PKGBUILD's prepare(), from the archives in Valve's source package
cd /w/src && for t in imgui-1.91.6.tar.gz spdlog-v1.14.1.tar.gz vulkan-headers-1.4.346.tar.gz vulkan-utility-libraries-1.4.346.tar.gz; do tar -xzf \$t; done; unzip -oq implot-v0.16.zip
# the meson wrap patches (meson.build files), which makepkg extracts with the other sources
for z in imgui_1.91.6-3_patch.zip spdlog-1.14.1-1-wrap.zip implot-v0.16-1-wrap.zip; do unzip -oq \$z; done
cd /w/MangoHud/subprojects
ln -sfn /w/src/imgui-1.91.6 imgui-1.91.6 && cp -r packagefiles/imgui-1.91.6/. imgui-1.91.6/
ln -sfn /w/src/implot-0.16 .
ln -sfn /w/src/spdlog-1.14.1 spdlog-1.14.1
ln -sfn /w/src/Vulkan-Headers-1.4.346 Vulkan-Headers-1.4.346 && cp -r packagefiles/vulkan-headers/. Vulkan-Headers-1.4.346/
ln -sfn /w/src/Vulkan-Utility-Libraries-1.4.346 Vulkan-Utility-Libraries-1.4.346 && cp -r packagefiles/vulkan-utility-libraries/. Vulkan-Utility-Libraries-1.4.346/
source /etc/makepkg.conf
export CFLAGS CXXFLAGS LDFLAGS
cd /w/MangoHud && rm -rf /w/b && meson setup /w/b --prefix=/usr --libexecdir=lib --buildtype=plain --wrap-mode=nodownload -D append_libdir_mangohud=false -D use_system_spdlog=disabled -D mangoapp=true -D mangohudctl=false -D with_xnvctrl=disabled -D tests=disabled -D with_mangohud_next=false >/w/meson.log 2>&1
meson compile -C /w/b mangoapp 2>&1 | tail -40
strip /w/b/src/mangoapp
ls -l /w/b/src/mangoapp
"
