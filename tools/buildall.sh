#!/bin/bash
# A small script to build and deploy a new version of the home app.

# Arguments:
    # -c: Just run the code test.

SCRIPT_DIR=$(dirname "$(realpath "$0")")
root="/var/www/home"
NO_APP_BUILD_PRESENT=false
DEBUG=false

dart run $SCRIPT_DIR/codetest.dart

for arg in "$@"; do
    if [[ "$arg" == "-c" ]]; then
        exit 0
    fi
    if [[ "$arg" == "--no-app-build" ]]; then
        NO_APP_BUILD_PRESENT=true
        break
    fi
    if [[ "$arg" == "--debug" ]]; then
        DEBUG=true
        break
    fi
done

echo "Starting build and deploy (debug: $DEBUG)"
cd "$root/app"

if [ $? -ne 0 ]; then
    exit 1
fi

echo "Building..."
dart compile exe "$root/tools/countlines.dart" -o "$root/temp/countlines"

if ! $NO_APP_BUILD_PRESENT; then
    if $DEBUG; then
        flutter build web --debug
        flutter build linux --debug
    else
        flutter build web
        flutter build linux
    fi
fi

echo "Deploying..."
if ! $NO_APP_BUILD_PRESENT; then
    ../tools/deployweb.sh
    ../tools/deployapp.sh
fi

cp "$root/temp/countlines" "$root/build/countlines"
echo "Build and deploy complete"
exit 0