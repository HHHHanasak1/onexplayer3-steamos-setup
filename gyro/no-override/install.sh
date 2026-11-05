#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=/etc/oxp3-gyro
yaml=/etc/inputplumber/devices.d/50-onexplayer_3.yaml
backup=$HOME/oxp3-gyro-backup
restart=1
[ "${1:-}" = --no-restart ] && restart=0

[ "$(cat /sys/class/dmi/id/product_name)" = "ONEXPLAYER 3" ] || { echo "not an ONEXPLAYER 3"; exit 1; }
[ ! -e /sys/bus/i2c/devices/i2c-BMI0260:00 ] || { echo "the ACPI override (step 7) is active; this route is not needed"; exit 1; }
[ -e /sys/bus/i2c/devices/i2c-10EC5280:00 ] || { echo "no 10EC5280 IMU node"; exit 1; }
modinfo -n bmi270_i2c >/dev/null || { echo "kernel has no bmi270_i2c"; exit 1; }
[ -f "$yaml" ] || { echo "missing $yaml: run ./oxp3-apply-fixes.sh first"; exit 1; }
grep -q 'name: .*bmi260' "$yaml" || { echo "$yaml has no IIO source naming bmi260"; exit 1; }
[ ! -e /etc/systemd/system/inputplumber.service.d/oxp3-gyro-fork.conf ] || { echo "step 7 is installed; run ./oxp3-apply-fixes.sh --no-gyro first"; exit 1; }

mkdir -p "$backup"
[ -f "$backup/50-onexplayer_3.yaml.orig" ] || cp "$yaml" "$backup/50-onexplayer_3.yaml.orig"

sudo install -d -m 755 "$dir" "$dir/firmware"
sudo install -m 755 "$here/oxp3-gyro-load.sh" "$dir/oxp3-gyro-load.sh"
for f in oxp3-gyro-patch.py oxp3-gyro-yaml.py imu-block.yaml; do sudo install -m 644 "$here/$f" "$dir/$f"; done
for fw in /usr/lib/firmware/bmi260-init-data.fw*; do [ -f "$fw" ] && sudo install -m 644 "$fw" "$dir/firmware/"; done
compgen -G "$dir/firmware/bmi260-init-data.fw*" >/dev/null || { echo "no bmi260 firmware found to bundle"; exit 1; }
echo "blacklist bmi160_i2c" | sudo tee /etc/modprobe.d/oxp3-gyro.conf >/dev/null
sudo install -m 644 "$here/oxp3-gyro.service" /etc/systemd/system/oxp3-gyro.service
sudo install -m 644 "$here/oxp3-gyro-resume.service" /etc/systemd/system/oxp3-gyro-resume.service
sudo systemctl daemon-reload
sudo systemctl enable oxp3-gyro.service oxp3-gyro-resume.service
sudo systemctl restart oxp3-gyro.service
sudo "$dir/oxp3-gyro-load.sh" status

if [ "$restart" = 1 ]; then
    echo "restarting InputPlumber (the controller drops for a second)"
    sudo systemctl restart inputplumber.service
    sleep 3
    systemctl is-active inputplumber.service
fi
echo "gyro installed"
