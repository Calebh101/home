#!/bin/bash
PARENT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
echo "Copying app build to build... (directory: $PARENT_DIR)"

rm -rf "$PARENT_DIR/build"
cp -r "$PARENT_DIR/app/build/linux/x64/release/bundle" "$PARENT_DIR/build"
echo "Copy complete"