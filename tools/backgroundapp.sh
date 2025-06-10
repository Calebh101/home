#!/bin/bash
# A small script to launch and manage the built home app in the background.

root="/var/www/home"
logfile="$root/logs/homeapp.log"
kioskarg="--kiosk"

for arg in "$@"; do
    if [[ "$arg" == "--no-kiosk" ]]; then
        kioskarg=""
        break
    fi
done

echo "Log file cleared!" > "$logfile"

log() {
    while IFS= read -r line; do
        echo "APP: $(date -Iseconds): $line"
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

(
    for i in {5..1}; do
        echo "Starting app in $i..." | log
        sleep 1
    done

    echo "Starting app now.." | log
    "$root/build/homeapp" $kioskarg 2>&1 | log
    echo "App process complete" | log
) &> /dev/null &