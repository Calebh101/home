#!/bin/bash
# A simple script to replace pm2.

root="/var/www/home"
script="$root/server/server.js"
app="$root/tools/backgroundapp.sh"
logfile="$root/logs/updatehost.log"

count=0
limit=10

log() {
    while IFS= read -r line; do
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

echo "Starting $app..."
$app

while true; do
    echo "Starting $script... (index: $count)"
    node "$script" "$@"

    seconds=0
    code=$?

    if [[ $code -ne 0 ]]; then
        seconds=5
        ((count++))

        if [ "$count" -eq 10 ]; then
            echo "Server hit $count bad restarts! Stopping..."
            break;
        fi
    fi

    echo "Script stopped with exit code $code. Restarting in $seconds seconds..."
    sleep $seconds
done