
#!/usr/bin/env bash

PROJECT="$HOME/Documents/Projects/victus-sync-app/gui"
APP="$PROJECT/build/victus-sync-gui"
LOG="$HOME/.local/state/victus-sync/build.log"

mkdir -p "$(dirname "$LOG")"

cd "$PROJECT" || exit 1

if cmake -S . -B build > "$LOG" 2>&1 &&
   cmake --build build -j"$(nproc)" >> "$LOG" 2>&1; then

    if [ ! -x "$APP" ]; then
        notify-send -u critical "Victus Sync" "Executable not found!"
        exit 1
    fi

    # Launch the newly compiled application
    "$APP" &

    notify-send "Victus Sync" "Build successful. Application launched!"
else
    notify-send -u critical "Victus Sync" "Build failed. Check build.log"
    exit 1
fi

