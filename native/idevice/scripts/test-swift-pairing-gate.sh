#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
task_dir=$(mktemp -d "${TMPDIR:-/tmp}/clocation-pairing-gate.XXXXXX")
trap 'rm -rf "$task_dir"' EXIT HUP INT TERM
swiftc -warnings-as-errors -swift-version 5 -module-cache-path "$task_dir/module-cache" \
    "$repo_dir/packages/location_bridge/ios/location_bridge/Sources/location_bridge/PairingAttemptGate.swift" \
    "$repo_dir/native/idevice/tests/PairingAttemptGateTests.swift" \
    -o "$task_dir/pairing-gate-tests"
"$task_dir/pairing-gate-tests"
