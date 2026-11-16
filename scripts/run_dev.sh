#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_DIR=~/Documents/Projects/victus-sync/omen-fan-control/src/omen_fan_control/data/driver/hp-wmi-omen
LED=/sys/class/leds/hp::kbd_backlight

restore() {
    sudo rmmod hp_wmi 2>/dev/null
    sudo modprobe hp_wmi
    echo "Stock HP driver restored."
}
trap restore EXIT

sudo modprobe -r hp_wmi || exit 1
sudo modprobe sparse-keymap
sudo modprobe led-class-multicolor
sudo insmod "$DRIVER_DIR/hp-wmi.ko" || exit 1
sudo chmod a+w $LED/multi_intensity $LED/brightness

python3 "$ROOT/engine/engine.py" "$@"
