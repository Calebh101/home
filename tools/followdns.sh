#!/bin/bash

file="/var/www/home/log/dnsmasq.log"
ip="$1"

# Check if IP is provided
if [ -n "$ip" ]; then
    ipgrep="grep \"$ip\""
else
    ipgrep=""
fi

echo "Starting dnsmasq follow on file: $file"

# Use tail and grep
if [ -n "$ipgrep" ]; then
    sudo tail -f "$file" | grep "query" | $ipgrep
else
    sudo tail -f "$file" | grep "query"
fi

