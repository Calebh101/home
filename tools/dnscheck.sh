#!/bin/bash
debug=0  # not recommended to enable

debugecho() {
    if [[ debug -gt 0 ]]; then
	echo "$1"
    fi
}

if [[ -z "$1" ]]; then
    echo "Usage: $0 <file> <lookup=0>"
    exit 1
fi

file="$1"

if [ "${2:-0}" -gt 0 ]; then
    lookup=1
else
    lookup=0
fi

if [ ! -f "$file" ]; then
    echo "Error: File '$file' not found."
    exit 1
fi

if [[ $lookup -eq 1 ]]; then
    echo -e "IP Address\tAmount of Occurrences\tMAC Address\tHostname\tVendor"
else
    echo -e "IP Address\tAmount of Occurrences\tMAC Address"
fi

debugecho "Setting..."
ips=0
occurrences=0

debugecho "Outputting..."
while read -r ip count; do
    debugecho "Processing: $ip - $count"
    ((ips++))
    occurrences=$((occurrences + count))

    debugecho "Getting MAC address for $ip..."
    mac=$(arp -n "$ip" | awk '/ether/ {print $3}')

    if [[ $lookup -eq 1 ]]; then
        hostname=$( (timeout 1 avahi-resolve-address "$ip" & sleep 1; wait) 2>/dev/null | awk -F'\t' '{print $2}')
	hostname=${hostname:-"Not found"}

	vendor=$(curl -s https://api.macvendors.com/"$mac" | grep -v '{"errors":{"detail":"Not Found"}}')
	vendor=${vendor:-"Not found"}

        echo -e "$ip\t$count occurrences\t$mac\t$hostname\t$vendor"
    else
        echo -e "$ip\t$count occurrences\t$mac"
    fi
done < <(grep -oE '192\.168\.[0-9]+\.[0-9]+' "$file" | 
          awk '{count[$0]++} END {for (ip in count) print ip "\t" count[ip]}' | 
          sort -nr -k2)

echo ""
echo "Results"
echo -e "Total IP addresses:\t$ips"
echo -e "Total occurrences:\t$occurrences"
