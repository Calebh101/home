#!/bin/bash
# A simple script to replace pm2.

root="/var/www/home"
script="$root/server/server.js"
logfile="$root/logs/updatehost.log"

count=0
limit=10

log() {
    while IFS= read -r line; do
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

"$root/tools/backgroundapp.sh"

while true; do
    echo "Starting $script... (index: $count)"
    node "$script" "$@"
    code=$?

    if [[ $code -ne 0 ]]; then
        ((count++))
        if [ "$count" -eq 10 ]; then
            echo "Server hit $count bad restarts! Stopping..."
            break;
        fi
    fi

    echo "Script stopped with exit code $code. Restarting in 5 seconds..."
    sleep 5
done