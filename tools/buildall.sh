#!/bin/bash
# V. 1.0.0A

SCRIPT_DIR=$(dirname "$(realpath "$0")")
dart run $SCRIPT_DIR/codetest.dart

echo "Starting build and deploy"
cd /var/www/home/app

if [ $? -ne 0 ]; then
    exit 1
fi

echo "Building..."
flutter build web
flutter build linux

echo "Deploying..."
../tools/deployweb.sh
../tools/deployapp.sh

echo "Build and deploy complete"
exit 0