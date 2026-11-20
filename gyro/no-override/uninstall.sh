#!/bin/bash
set -uo pipefail
dir=/etc/oxp3-gyro
yaml=/etc/inputplumber/devices.d/50-onexplayer_3.yaml

sudo systemctl disable --now oxp3-gyro-resume.service 2>/dev/null
sudo systemctl disable oxp3-gyro.service 2>/dev/null
[ -x "$dir/oxp3-gyro-load.sh" ] && sudo "$dir/oxp3-gyro-load.sh" restore
sudo systemctl stop oxp3-gyro.service 2>/dev/null
if [ -f "$yaml" ] && [ -f "$dir/oxp3-gyro-yaml.py" ]; then
    sudo python3 -I "$dir/oxp3-gyro-yaml.py" remove "$yaml"
fi
sudo rm -f /etc/systemd/system/oxp3-gyro.service /etc/systemd/system/oxp3-gyro-resume.service /etc/modprobe.d/oxp3-gyro.conf
sudo rm -rf "$dir" /run/oxp3-gyro
sudo systemctl daemon-reload
echo "restarting InputPlumber (the controller drops for a second)"
sudo systemctl restart inputplumber.service
echo "gyro removed; reboot to clear the unsigned-module taint and let bmi160_i2c bind again"
