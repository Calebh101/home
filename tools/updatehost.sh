#!/bin/bash
# A small bash script to automatically update the host.

# -c: Clear log file first
# -a: Reopen app as well
# -l: Open live view of pm2 log

dir="/var/www/home"
logfile="$dir/logs/updatehost.log"

log() {
    while IFS= read -r line; do
        echo "$(date -Iseconds): $line" >> "$logfile"
    done
}

for arg in "$@"; do
    if [[ "$arg" == "-c" ]]; then
        echo "Clearing log file..."
        echo "Log file cleared!" > "$logfile"
        break
    fi
done

echo "Starting... (directory: $dir) (logfile: $logfile)" # Tell the user directly in stdout
mkdir "$dir/logs" > /dev/null 2>&1 # Create the directory if it doesn't exist
echo "Updating... (directory: $dir) (logfile: $logfile)" 2>&1 | log
pkill homeapp 2>&1 | log
cd "$dir" 2>&1 | log
git pull 2>&1 | log
pm2 restart "$dir/server/server.js" 2>&1 | log

for arg in "$@"; do
    if [[ "$arg" == "-a" ]]; then
        echo "Running app..." 2>&1 | log
        nohup "$dir/build/homeapp" > /dev/null 2>&1 &
        break
    fi
done

for arg in "$@"; do
    if [[ "$arg" == "-l" ]]; then
        echo "Running pm2 log..." 2>&1 | log
        pm2 log 2>> "$log"
        break
    fi
done

echo "Process complete." 2>&1 | log
echo "Process complete. Results are in $logfile."