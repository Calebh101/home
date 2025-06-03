#!/bin/bash
# A simple script to replace pm2.

root="/var/www/home"
script="$root/server/server.js"
app="$root/tools/backgroundapp.sh"
logfile="$root/logs/server.log"

limit=10
args=()

cd "$root"
git pull

log() {
    while IFS= read -r line; do
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

argcheck() {
    target="$1"
    input="$2"
    if [[ "$input" == "$target" ]]; then
        echo "Adding arg $target..."
        args+=("$target")
    fi
}

for arg in "$@"; do
    if [[ "$arg" == "--app" ]]; then
        echo "Starting $app..."
        $app
    fi
    argcheck "--override-verify" "$arg"
done

arginput=$(IFS=" "; echo "${args[*]}")
count=0

while true; do
    echo "Starting $script... (index: $count) (command: $script $arginput"
    node "$script" "$arginput"

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