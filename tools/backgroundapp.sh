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
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

(
    sleep 5
    echo "Process starting..." | log
    "$root/build/homeapp" $kioskarg 2>&1 | log
    echo "Process complete" | log
) &> /dev/null &