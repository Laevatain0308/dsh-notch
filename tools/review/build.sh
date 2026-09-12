#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
swift build --package-path "$repo/macos" -c release
exec "$repo/macos/.build/release/dsh-notch" --demo
