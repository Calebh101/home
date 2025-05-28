#!/bin/bash

delay="${1:-0.5}"
max_frames=$(echo "${2:-1800} / $delay" | bc)
i=0

cd /var/www/home
rm -rf frames
mkdir frames
echo "Capturing frames at $delay FPS at a max of $max_frames frames"

while true; do
    echo "Capturing frame $i"
    ffmpeg -f v4l2 -video_size 640x480 -i /dev/video0 -frames:v 1 "frames/frame_$i.jpg" -y >/dev/null 2>&1
    ((i++))
    ls frames/frame_*.jpg 2>/dev/null | sort -V | head -n -"$max_frames" | xargs -r rm
    sleep "$delay"
done
