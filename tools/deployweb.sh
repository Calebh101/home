#!/bin/bash
PARENT_DIR="$(dirname "$(dirname "$(realpath "$0")")")"
echo "Copying web build to public... (directory: $PARENT_DIR)"

rm -rf "$PARENT_DIR/public"
cp -r "$PARENT_DIR/app/build/web" "$PARENT_DIR/public"
echo "Copy complete"