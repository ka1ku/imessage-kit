#!/bin/sh
# Builds the helper Messages.app loads: build/IMKitHelper.dylib (arm64e + x86_64, ad-hoc signed).
set -eu
cd "$(dirname "$0")"
mkdir -p build
clang -dynamiclib -fobjc-arc -O2 -arch arm64e -arch x86_64 -mmacosx-version-min=13.0 \
  -framework Foundation IMKitHelper.m -o build/IMKitHelper.dylib
codesign -s - -f build/IMKitHelper.dylib
echo "built $(pwd)/build/IMKitHelper.dylib"
