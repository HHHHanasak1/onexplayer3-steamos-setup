#!/bin/bash
set -u
DEV=i2c-10EC5280:00
SYS=/sys/bus/i2c/devices/$DEV
DIR=${OXP3_GYRO_DIR:-/etc/oxp3-gyro}
RUN=/run/oxp3-gyro
KO=$RUN/bmi270_i2c.ko
IP_YAML=/etc/inputplumber/devices.d/50-onexplayer_3.yaml

log() { echo "oxp3-gyro: $*"; }

driver() { [ -e "$SYS/driver" ] && basename "$(readlink "$SYS/driver")"; }

iio_dir() { local d; d=$(compgen -G "$SYS/iio:device*" | head -n1); [ -n "$d" ] && echo "$d"; }

iio_name() { local d; d=$(iio_dir) && cat "$d/name"; }

wait_for() {
    for _ in $(seq "$2"); do eval "$1" && return 0; sleep 0.2; done
    return 1
}

use_bundled_firmware() {
    if ! compgen -G "/usr/lib/firmware/bmi260-init-data.fw*" >/dev/null && [ -d "$DIR/firmware" ]; then
        printf '%s' "$DIR/firmware" > /sys/module/firmware_class/parameters/path
        log "using bundled firmware from $DIR/firmware"
    fi
}

ensure_yaml() {
    [ -f "$DIR/imu-block.yaml" ] && [ -f "$IP_YAML" ] || return 0
    python3 -I "$DIR/oxp3-gyro-yaml.py" ensure "$IP_YAML" "$DIR/imu-block.yaml"
}

unload() {
    [ -d /sys/module/bmi270_i2c ] && rmmod bmi270_i2c
    rmmod bmi270_core 2>/dev/null
    return 0
}

rebind_bmi160() {
    local now
    modprobe bmi160_i2c 2>/dev/null
    [ -z "$(driver)" ] && echo "$DEV" > /sys/bus/i2c/drivers/bmi160_i2c/bind 2>/dev/null
    now=$(driver)
    log "driver now: ${now:-none (bmi160_i2c binds again at next boot)}"
}

sensor_alive() {
    local d v sum=0
    d=$(iio_dir) || return 1
    for v in accel_x accel_y accel_z; do
        v=$(cat "$d/in_${v}_raw" 2>/dev/null) || return 1
        sum=$(( sum + v * v ))
    done
    [ "$sum" -gt 1000000 ]
}

start() {
    ensure_yaml
    wait_for '[ -e "$SYS" ]' 50 || { log "no $DEV on this machine"; exit 1; }
    if [ "$(driver)" = bmi270_i2c ] && [ "$(iio_name)" = bmi260 ]; then
        log "already bound to bmi270_i2c (bmi260)"
        exit 0
    fi
    use_bundled_firmware
    mkdir -p "$RUN"
    src=$(modinfo -n bmi270_i2c) || { log "bmi270_i2c not in this kernel"; exit 1; }
    python3 -I "$DIR/oxp3-gyro-patch.py" "$src" "$KO" || { log "patching $src failed"; exit 1; }
    [ -n "$(driver)" ] && echo "$DEV" > "/sys/bus/i2c/drivers/$(driver)/unbind"
    unload
    modprobe bmi270_core
    insmod "$KO" || { log "insmod failed"; unload; exit 1; }
    if wait_for '[ "$(driver)" = bmi270_i2c ] && [ "$(iio_name)" = bmi260 ]' 25; then
        log "IMU bound to bmi270_i2c as bmi260"
    else
        log "bmi270_i2c did not bind"
        unload
        exit 1
    fi
}

resume() {
    [ "$(driver)" = bmi270_i2c ] || exit 0
    sleep 1
    sensor_alive && { log "IMU alive after resume"; exit 0; }
    log "IMU silent after resume, reloading"
    unload
    start
}

status() {
    local d c
    echo "driver: $(driver)"
    echo "iio name: $(iio_name)"
    d=$(iio_dir) || return 0
    for c in accel_x accel_y accel_z anglvel_x anglvel_y anglvel_z; do
        printf '%s=%s ' "$c" "$(cat "$d/in_${c}_raw" 2>/dev/null)"
    done
    echo
    echo "accel_scale=$(cat "$d/in_accel_scale" 2>/dev/null) anglvel_scale=$(cat "$d/in_anglvel_scale" 2>/dev/null)"
}

case "${1:-start}" in
    start) start ;;
    stop) unload ;;
    restore) unload; rebind_bmi160 ;;
    resume) resume ;;
    status) status ;;
    *) echo "usage: $0 start|stop|restore|resume|status"; exit 2 ;;
esac
