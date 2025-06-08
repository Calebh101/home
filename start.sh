#!/bin/bash
# A simple script to replace pm2.

root="/var/www/home"
serverdir="$root/server"

script="$root/server/server.js"
app="$root/tools/backgroundapp.sh"
logfile="$root/logs/server.log"

limit=10
args=()
debug=false
log=false
app=false

cd "$root"
git pull
clearlog

log() {
    while IFS= read -r line; do
        echo "$line"
        if $log; then
            echo "$line" >> "$logfile"
        fi
    done
}

clearlog() {
    echo "$(date -Iseconds): Log cleared" > "$logfile"
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
        echo "Detected app..."
        app=true
    fi
    if [[ "$arg" == "--debug" ]]; then
        echo "Loading debug..."
        debug=true
    fi

    argcheck "--override-verify" "$arg"
done

if [ "$debug" = false ]; then
    cd "$serverdir"
    echo "Requesting sudo permissions for npm install..."
    sudo npm install
fi

arginput=$(IFS=" "; echo "${args[*]}")
count=0

background_reset() {
    while true; do
        count=0
        echo "Set count to $count"
        sleep 600
    done
}

background_reset &
bg_pid=$!
trap "kill $bg_pid" EXIT

if [ "$app" = true ]; then
    echo "Starting $app..."
    $app
fi

while true; do
    echo "Starting $script... (index: $count) (command: $script $arginput)"
    node "$script" "$arginput" | log

    code=$?
    seconds=0

    if [[ $code -ne 0 ]]; then
        seconds=5
        ((count++))

        if [ "$count" -eq 10 ]; then
            echo "Server hit $count bad restarts! Stopping..."
            break
        fi
    fi

    echo "Script stopped with exit code $code. Restarting in $seconds seconds..."
    sleep $seconds
done