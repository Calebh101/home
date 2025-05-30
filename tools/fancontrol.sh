#!/usr/bin/env bash

# This script was taken and modified from this GitHub repository:
    # https://github.com/JuampiCarosi/fan-control

# Please note: This script is only to be used on the iMac 12,1, due to Linux not being able to communicate with the iMac fan controller directly. If the host machine changes in the future, it will either:
    # A. not need dedicated fan control software, as it should be able to manage temperatures by itself.
    # B. need different fan control software, E.G. if the home system is moved to a newer iMac or a different Mac model.
    # C. rely on passive cooling, which is not a good solution for a 24/7 home system.

CMD="${0##*/}"
SCRIPTPATH="$(realpath "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
sysdir="/sys/devices/platform/applesmc.768"

declare -a control_file label_file output_file label

# Match labels with fan number and get control files
fan_info() {
    local fan="$1"
    control_file[$fan]="$sysdir/fan${fan}_manual"
    label_file[$fan]="$sysdir/fan${fan}_label"
    output_file[$fan]="$sysdir/fan${fan}_output"
    read -r label[$fan] < "${label_file[$fan]}"
    label[$fan]=${label[$fan],,}                  # lowercase
}

fan_info 1
if ! [[ "${label[1]}" =~ ^(exhaust|master|main)$ ]]; then
	fan_info 2
	fan_info 3
fi

# fan() - set fan
# $1 is fan number (starting from 1)
# $2 is percent to apply
fan_function() {
    local manual max min
    local -i fan_100 fan_net fan_final
    local fan="$1"
    local percent="$2"                            # "auto" or 0-100

    # Getting fan files and data from applesmc.768
    read -r manual < "${control_file[$fan]}"

    read -r max < "$sysdir/fan${fan}_max"
    read -r min < "$sysdir/fan${fan}_min"

    if [ "$percent" = "auto" ]; then
        # Switch back fan1 to auto mode
        echo "0" > "${control_file[$fan]}"
        printf "fan mode set to auto"
    else
        #Putting fan on manual mode
        if [ "$manual" = "0" ]; then
            echo "1" > "${control_file[$fan]}"
        fi

        # Calculating the net value that will be given to the fans
        fan_100=$((max - min))
        # Calculating final percentage value
        fan_net=$((percent * fan_100 / 100))
        fan_final=$((fan_net + min))

        # Writing the final value to the applemc files
        if echo "$fan_final" > "${output_file[$fan]}"; then
            printf "fan set to %d rpm.\n" "$fan_final"
        else
            printf "Try running command as sudo\n"
        fi
    fi
}

usage() {
    printf "usage: %s [fan] [percent]\n" "$CMD"
    printf '  fan: "all", "auto", "master", "exhaust", "hdd", "cpu" or "odd"\n'
    printf '  if fan is not "auto", percent is "auto" or a value between 0 and 100\n'
    exit 1
}

if (($# == 0)); then
    printf "Available fans:\n"
    printf "  %s\n" "${label[1]}"
    if ! [[ "${label[1]}" =~ ^(exhaust|master)$ ]]; then
        printf "  %s\n" "${label[2]}"
        printf "  %s\n" "${label[3]}"
	fi
    exit 0
fi

# fan type and value
command="$1"
if [[ "$command" != "auto" ]]; then
    if (( $# == 2 )); then
        percent="$2"
    else
        usage
    fi
fi

case "$command" in
    ### AUTO CONTROL
    auto)
        echo "0" > "${control_file[1]}"
        if [[ "${label[1]}" != "exhaust" ]]; then
		    echo "0" > "${control_file[2]}"
		    echo "0" > "${control_file[3]}"
	    fi
        ;;

    ####  HDD/CPU/ODD CONTROL
    hdd|cpu|odd)
        for i in 1 2 3; do
            if [ "${label[$i]}" = "$command" ]; then
                fan_function "$i" "$percent"
            fi
        done
        ;;

    ### EXHAUST/MASTER CONTROL
    exhaust|master|main)
        fan_function 1 "$percent"
        ;;

    all)
        username=caleb

        sudo -u "$username" jq --argjson percent "$percent" '.fans.speed = $percent' "$PARENT_DIR/server/data.json" > tmp.json && mv tmp.json "$PARENT_DIR/server/data.json"
        sudo chown "$username":"$username" "$PARENT_DIR/server/data.json"

        sudo "$SCRIPTPATH" cpu "$percent"
        sudo "$SCRIPTPATH" odd "$percent"
        sudo "$SCRIPTPATH" hdd "$percent"
        exit 0
        ;;

    *)
        printf 'unknown command %s\n' "$command"
        usage
esac
