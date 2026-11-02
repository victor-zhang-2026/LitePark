#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TEST_BUILD=".build/parking-board-tests"
mkdir -p "$TEST_BUILD"
# Compile the production types with a separate test entry point; no XCTest/Xcode required.
sed '/^@main/,$d' Sources/ChatGPTLaterQueue/main.swift > "$TEST_BUILD/Runtime.swift"
set -- "$TEST_BUILD/Runtime.swift" Tests/ParkingBoardTests.swift
for source in Sources/ChatGPTLaterQueue/*.swift; do
    case "$source" in */main.swift) ;; *) set -- "$@" "$source" ;; esac
done
xcrun swiftc -parse-as-library -sdk "${LITEPARK_MACOS_SDK:-$(xcrun --show-sdk-path)}" \
    -target "$(uname -m)-apple-macos13.0" "$@" -o "$TEST_BUILD/ParkingBoardTests"
"$TEST_BUILD/ParkingBoardTests"
