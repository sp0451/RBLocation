#!/bin/sh
# Pinned source -> generated C header + matching device/simulator libraries.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
native_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_dir=$(CDPATH= cd -- "$native_dir/../.." && pwd)
source_commit=e98264c4194e6980173c576ac79a58adce95492b
archive="$native_dir/source/idevice-$source_commit.tar.gz"
patch="$native_dir/patches/aurora-ios.patch"
cargo_bin=${CLOCATION_CARGO:-cargo}
rustc_bin=${CLOCATION_RUSTC:-rustc}
build_dir="$native_dir/.build"
source_dir="$build_dir/idevice-$source_commit"
stage_dir="$build_dir/package"
destination="$repo_dir/packages/location_bridge/ios/location_bridge/IdeviceRuntime.xcframework"
features=ring,remote_pairing,tunnel_tcp_stack,dvt,location_simulation

verify_hash() {
    actual=$(shasum -a 256 "$1" | awk '{print $1}')
    test "$actual" = "$2" || { echo "Pinned input hash mismatch: $1" >&2; exit 1; }
}
verify_hash "$archive" 2f7951cad7b85b6f8ecb1cb05ceb3f9a4a2158b3e78e100fc66d2cff5d15cbc9
verify_hash "$patch" 01d7f11701c83ee9e3167bd9376ea2aa9ae70b6bef84f97f651154b6a72c79e0
verify_hash "$native_dir/Cargo.lock" 735ead5f87f6b44b2ba033abfef3159e0d27dbf7a1bad44da4a305378e4f1131
case $("$rustc_bin" --version) in
    'rustc 1.99.1 '*) ;;
    *) echo 'Rust 1.99.1 is required; use CLOCATION_RUSTC / CLOCATION_CARGO to select it.' >&2; exit 1 ;;
esac

mkdir -p "$build_dir"
# This script owns only these generated paths under its own .build directory.
rm -rf "$source_dir" "$stage_dir"
tar -xzf "$archive" -C "$build_dir"
git -C "$source_dir" apply --check "$patch"
git -C "$source_dir" apply "$patch"
cp "$native_dir/Cargo.lock" "$source_dir/Cargo.lock"
touch "$source_dir/ffi/build.rs"
mkdir -p "$stage_dir/Headers"

export CARGO_TARGET_DIR="$build_dir/target"
export IPHONEOS_DEPLOYMENT_TARGET=26.0
export RUSTFLAGS="--remap-path-prefix=$repo_dir=clocation-source --remap-path-prefix=$build_dir=clocation-build"
cargo_home_dir=${CARGO_HOME:-"$HOME/.cargo"}
RUSTFLAGS="$RUSTFLAGS --remap-path-prefix=$cargo_home_dir=clocation-cargo"
if test -d "$cargo_home_dir"; then
    cargo_physical_dir=$(CDPATH= cd -- "$cargo_home_dir" && pwd -P)
    RUSTFLAGS="$RUSTFLAGS --remap-path-prefix=$cargo_physical_dir=clocation-cargo"
fi

for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    (cd "$source_dir" && "$cargo_bin" build --locked --release --target "$target" \
        -p idevice-ffi --no-default-features --features "$features")
    xcrun strip -S -o "$stage_dir/lib-$target.a" "$CARGO_TARGET_DIR/$target/release/libidevice_ffi.a"
done
cp "$source_dir/ffi/idevice.h" "$stage_dir/Headers/idevice.h"
cat > "$stage_dir/Headers/module.modulemap" <<'MODULE'
module IdeviceRuntime {
  header "idevice.h"
  export *
}
MODULE
xcrun lipo -create "$stage_dir/lib-aarch64-apple-ios-sim.a" "$stage_dir/lib-x86_64-apple-ios.a" \
    -output "$stage_dir/libIdeviceRuntime-simulator.a"
cp "$stage_dir/lib-aarch64-apple-ios.a" "$stage_dir/libIdeviceRuntime-device.a"

for archive_file in "$stage_dir/libIdeviceRuntime-device.a" "$stage_dir/libIdeviceRuntime-simulator.a"; do
    xcrun nm -gU "$archive_file" > "$stage_dir/symbols.txt" 2>/dev/null
    for symbol in aurora_pairable_host_accept aurora_pairable_host_set_cancelled \
        rp_pairing_file_from_bytes rp_pairing_file_to_bytes tunnel_create_rppairing \
        remote_server_connect_rsd location_simulation_new location_simulation_set location_simulation_clear; do
        rg -q "_$symbol$" "$stage_dir/symbols.txt" || { echo "Missing ABI symbol: $symbol" >&2; exit 1; }
    done
done
xcodebuild -create-xcframework \
    -library "$stage_dir/libIdeviceRuntime-device.a" -headers "$stage_dir/Headers" \
    -library "$stage_dir/libIdeviceRuntime-simulator.a" -headers "$stage_dir/Headers" \
    -output "$stage_dir/IdeviceRuntime.xcframework"
verify_hash "$source_dir/Cargo.lock" 735ead5f87f6b44b2ba033abfef3159e0d27dbf7a1bad44da4a305378e4f1131

rm -rf "$destination"
cp -R "$stage_dir/IdeviceRuntime.xcframework" "$destination"
mkdir -p "$repo_dir/artifacts/ios"
(cd "$repo_dir" && find packages/location_bridge/ios/location_bridge/IdeviceRuntime.xcframework \
    -type f -exec shasum -a 256 {} \;) > "$repo_dir/artifacts/ios/idevice-sha256.txt"
echo "Built pinned idevice device + arm64/x86_64 Simulator XCFramework."
