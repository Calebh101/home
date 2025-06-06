#!/bin/bash
# A simple script to replace pm2.

root="/var/www/home"
script="$root/server/server.js"
app="$root/tools/backgroundapp.sh"
logfile="$root/logs/server.log"

limit=10
args=()
debug=false
log=false

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
        echo "Starting $app..."
        $app
    fi
    if [[ "$arg" == "--debug" ]]; then
        echo "Loading debug..."
        debug=true
    fi

    argcheck "--override-verify" "$arg"
done

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

while true; do
    echo "Starting $script... (index: $count) (command: $script $arginput)"
    seconds=0

    if $debug; then
        node "$script" "$arginput" | log &
        app_pid=$!
        inotifywait -q -e modify,create,delete -r --include '.*\.js$' "$root/server" &
        watch_pid=$!
        wait -n $app_pid $watch_pid
        result=$?

        if ! kill -0 $app_pid 2>/dev/null; then
            wait $app_pid
            code=$?
        else
            echo "File change detected. Stopping app..."
            kill $app_pid
            wait $app_pid
            code=0
        fi
    else
        node "$script" "$arginput" | log
        code=$?
    fi

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