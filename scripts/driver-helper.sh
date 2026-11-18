
#!/usr/bin/env bash

set -u

USER_NAME="kishan"
USER_ID="$(id -u "$USER_NAME")"

ROOT="/home/kishan/Documents/Projects/victus-sync-app"
DRIVER_DIR="/home/kishan/Documents/Projects/victus-sync/omen-fan-control/src/omen_fan_control/data/driver/hp-wmi-omen"
LED="/sys/class/leds/hp::kbd_backlight"

restore() {
    echo "Restoring stock HP driver..."

    rmmod hp_wmi 2>/dev/null || true
    modprobe hp_wmi

    echo "Stock HP driver restored."
}

# Always attempt restoration on exit.
trap restore EXIT

modprobe -r hp_wmi || exit 1

modprobe sparse-keymap || exit 1
modprobe led-class-multicolor || exit 1

insmod "$DRIVER_DIR/hp-wmi.ko" || exit 1

if [[ ! -d "$LED" ]]; then
    echo "Keyboard LED device not found."
    exit 1
fi

chmod a+w "$LED/multi_intensity" "$LED/brightness" || exit 1

echo "Starting Victus Sync as normal user..."

runuser -u "$USER_NAME" -- env \
    HOME="/home/$USER_NAME" \
    USER="$USER_NAME" \
    LOGNAME="$USER_NAME" \
    DISPLAY="${DISPLAY:-}" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
    XDG_RUNTIME_DIR="/run/user/$USER_ID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
    python3 "$ROOT/engine/engine.py" "$@"
