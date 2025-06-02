#!/bin/bash
# A small bash script to automatically update the host.

# -c: Clear log file first
# -a: Reopen app as well

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
git pull 2>&1 | log/home/$user/.Xauthority

for arg in "$@"; do
    if [[ "$arg" == "-a" ]]; then
        echo "Running app..." 2>&1 | log
        export DISPLAY=:0
        export XAUTHORITY="/home/$user/.Xauthority"
        "$dir/build/homeapp --kiosk" > /dev/null 2>&1 &
        break
    fi
done

echo "Process complete." 2>&1 | log
echo "Process complete. Results are in $logfile."